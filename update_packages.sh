#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

export DEBIAN_FRONTEND=noninteractive

SUDO=''
if (( EUID != 0 )); then
    SUDO='sudo'
fi

# ---------------------------------------------------------------------------
# Package lists — wspólne z initial_packages.sh przez packages/apt_packages.sh
# ---------------------------------------------------------------------------

minimal_tools=(
    curl wget
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packages/apt_packages.sh
source "$SCRIPT_DIR/packages/apt_packages.sh"

all_apt_packages=(
    "${minimal_tools[@]}"
    "${system_tools[@]}"
    "${security_tools[@]}"
    "${graphics_libs[@]}"
    "${gui_libs[@]}"
    "${image_tools[@]}"
    "${diag_tools[@]}"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'
C_NC='\033[0m'

ok()      { printf "${C_GREEN}✓${C_NC} %s\n" "$*"; }
missing() { printf "${C_RED}✗${C_NC} %s\n" "$*"; }
warn()    { printf "${C_YELLOW}⚠${C_NC} %s\n" "$*"; }
info()    { printf "  %s\n" "$*"; }

apt_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -qc "ok installed"
}

declare -a REPOS_DEAD=()

KEYSERVER="hkps://keyserver.ubuntu.com"
KEYRING_DIR="/etc/apt/keyrings"

refresh_apt_gpg_keys() {
    info "Sprawdzanie kluczy GPG repozytoriów apt..."
    $SUDO mkdir -p "$KEYRING_DIR"

    # Remove expired imported keys so they can be re-fetched fresh
    local keyfile removed=0
    for keyfile in "$KEYRING_DIR"/imported-*.gpg; do
        [[ -f "$keyfile" ]] || continue
        if gpg --show-keys "$keyfile" 2>/dev/null | grep -q '\[expired\]'; then
            warn "Usuwanie wygasłego klucza: $(basename "$keyfile")"
            $SUDO rm -f "$keyfile"
            (( removed++ )) || true
        fi
    done
    (( removed > 0 )) && info "Usunięto $removed wygasłych kluczy"

    local update_output
    update_output=$($SUDO apt-get update 2>&1 || true)

    # Detect dead repositories (404 / no Release file)
    while IFS= read -r line; do
        local dead_url
        dead_url=$(echo "$line" | grep -oE 'https?://[^[:space:]]+' | head -1 || true)
        [[ -z "$dead_url" ]] && continue
        REPOS_DEAD+=("$dead_url")
    done < <(echo "$update_output" | grep -E '404|nie ma pliku Release|does not have a Release file' || true)

    # Pair each missing key with the repo URL that reported it — needed to scope
    # signed-by= to that one repo instead of trusting the key for all of apt.
    local pairs
    pairs=$(echo "$update_output" \
        | grep -E 'GPG error' \
        | grep -oE '[a-zA-Z]+://[^ ]+ .*NO_PUBKEY [0-9A-F]+' \
        | sed -E 's#^([a-zA-Z]+://[^ ]+) .*NO_PUBKEY ([0-9A-F]+).*#\2 \1#' \
        | sort -u || true)

    if [[ -z "$pairs" ]]; then
        ok "Klucze GPG w porządku"
        return 0
    fi

    warn "Brakujące klucze GPG:"
    while read -r k u; do warn "  - $k ($u)"; done <<<"$pairs"

    local fixed=0 unbound=0
    while read -r key repo_url; do
        [[ -z "$key" ]] && continue

        info "Pobieranie klucza $key z $KEYSERVER..."
        local tmp_keyring
        tmp_keyring=$(mktemp)
        if ! gpg --no-default-keyring --keyring "$tmp_keyring" --keyserver "$KEYSERVER" --recv-keys "$key" 2>/dev/null; then
            warn "Klucz $key: nie udało się pobrać z keyserver"
            rm -f "$tmp_keyring" "${tmp_keyring}~"
            continue
        fi
        info "Fingerprint klucza $key (repo: $repo_url):"
        gpg --no-default-keyring --keyring "$tmp_keyring" --fingerprint

        local keyring_file="$KEYRING_DIR/imported-${key}.gpg"
        gpg --no-default-keyring --keyring "$tmp_keyring" --export "$key" \
            | $SUDO tee "$keyring_file" > /dev/null
        $SUDO chmod 644 "$keyring_file"
        rm -f "$tmp_keyring" "${tmp_keyring}~"

        # Bind the key to the specific source file via signed-by= instead of
        # trusting it globally through trusted.gpg.d.
        local host bound=0 src_file
        host=$(echo "$repo_url" | sed -E 's#^[a-zA-Z]+://([^/]+).*#\1#')
        for src_file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
            [[ -f "$src_file" ]] || continue
            grep -q "$host" "$src_file" || continue
            if grep -q 'signed-by=' "$src_file"; then
                continue
            fi
            $SUDO sed -i -E \
                -e "s#^(deb(-src)?)([[:space:]]+)\[#\1\3[signed-by=${keyring_file} #" \
                -e "t" \
                -e "s#^(deb(-src)?)([[:space:]]+)(https?://)#\1\3[signed-by=${keyring_file}] \4#" \
                "$src_file"
            ok "Klucz $key przypięty do $src_file (signed-by=${keyring_file})"
            bound=1
            break
        done

        if [[ $bound -eq 0 ]]; then
            warn "Nie znaleziono pliku źródła dla $repo_url — klucz zapisany w $keyring_file, ale NIE dowiązany do repo."
            (( unbound++ )) || true
        fi

        (( fixed++ )) || true
    done <<<"$pairs"

    if (( fixed > 0 )); then
        info "apt-get update po naprawie kluczy..."
        $SUDO apt-get -qq update 2>&1 | grep -v '^Pobieranie\|^Stary\|^Zign\|^Hit' || true
    fi

    (( unbound > 0 )) && warn "$unbound klucz(e) nie dowiązano automatycznie — apt nadal będzie zgłaszał NO_PUBKEY."
}

# ---------------------------------------------------------------------------
# Phase 1: Status report
# ---------------------------------------------------------------------------

declare -a APT_MISSING=()
declare -a APT_INSTALLED=()
declare -a PACKAGES_UNAVAILABLE=()

check_apt_packages() {
    echo ""
    echo "=== Pakiety apt ==="
    local pkg
    for pkg in "${all_apt_packages[@]}"; do
        if apt_installed "$pkg"; then
            ok "$pkg"
            APT_INSTALLED+=("$pkg")
        else
            missing "$pkg"
            APT_MISSING+=("$pkg")
        fi
    done
}

check_gh() {
    echo ""
    echo "=== GitHub CLI ==="
    if command -v gh &>/dev/null; then
        ok "gh: $(gh --version | head -1)"
    else
        missing "gh: nie zainstalowany"
    fi
}

check_docker() {
    echo ""
    echo "=== Docker ==="
    if command -v docker &>/dev/null; then
        ok "docker: $(docker --version)"
    else
        missing "docker: nie zainstalowany"
    fi
    if command -v ctop &>/dev/null; then
        ok "ctop: $(ctop -v 2>&1 | head -1)"
    else
        missing "ctop: nie zainstalowany"
    fi
}

check_asdf() {
    echo ""
    echo "=== asdf ==="
    local asdf_bin="$HOME/.local/bin/asdf"
    if [ -x "$asdf_bin" ]; then
        ok "asdf: $("$asdf_bin" version 2>/dev/null || echo 'zainstalowany')"
    else
        missing "asdf: nie zainstalowany"
    fi
}

check_difft() {
    echo ""
    echo "=== difftastic ==="
    if command -v difft &>/dev/null; then
        ok "difft: $(difft --version)"
    else
        missing "difft: nie zainstalowany"
    fi
}

check_sdkman() {
    echo ""
    echo "=== SDKMAN ==="
    if [ -d "$HOME/.sdkman" ]; then
        local ver
        ver=$(cat "$HOME/.sdkman/var/version" 2>/dev/null || echo 'zainstalowany')
        ok "sdkman: $ver"
    else
        missing "sdkman: nie zainstalowany"
    fi
}

check_apps() {
    echo ""
    echo "=== Aplikacje ==="
    if command -v spotify &>/dev/null || apt_installed spotify-client; then
        ok "spotify"
    else
        missing "spotify: nie zainstalowany"
    fi
    if apt_installed 1password; then
        ok "1password"
    else
        missing "1password: nie zainstalowany"
    fi
    if command -v steam &>/dev/null || apt_installed steam; then
        ok "steam"
    else
        missing "steam: nie zainstalowany"
    fi
}

# ---------------------------------------------------------------------------
# Phase 2: Update / install
# ---------------------------------------------------------------------------

safe_apt_install() {
    local pkg
    for pkg in "$@"; do
        if ! apt-cache show "$pkg" >/dev/null 2>&1; then
            warn "Pakiet '$pkg' niedostępny w repozytoriach, pomijam"
            PACKAGES_UNAVAILABLE+=("$pkg")
            continue
        fi
        if ! $SUDO apt-get install -qqy "$pkg" 2>/dev/null; then
            warn "Instalacja '$pkg' nieudana (błąd zależności lub architektury)"
            PACKAGES_UNAVAILABLE+=("$pkg")
        fi
    done
}

update_apt_packages() {
    echo ""
    echo "=== Aktualizacja pakietów apt ==="

    if [ "${#APT_INSTALLED[@]}" -gt 0 ]; then
        info "Aktualizacja zainstalowanych..."
        $SUDO apt-get install -qqy --only-upgrade "${APT_INSTALLED[@]}" 2>/dev/null || true
        ok "Zainstalowane zaktualizowane"
    fi

    if [ "${#APT_MISSING[@]}" -gt 0 ]; then
        info "Instalacja brakujących: ${APT_MISSING[*]}"
        safe_apt_install "${APT_MISSING[@]}"
    fi
}

update_gh() {
    echo ""
    echo "=== GitHub CLI ==="
    if command -v gh &>/dev/null; then
        info "Aktualizacja gh..."
        $SUDO apt-get install -qqy --only-upgrade gh 2>/dev/null || true
        ok "gh zaktualizowany: $(gh --version | head -1)"
    else
        info "Instalacja gh..."
        $SUDO mkdir -p -m 755 /etc/apt/keyrings
        local keyring=/etc/apt/keyrings/githubcli-archive-keyring.gpg
        local tmpkey
        tmpkey="$(mktemp)"
        wget -nv -O "$tmpkey" https://cli.github.com/packages/githubcli-archive-keyring.gpg
        $SUDO install -o root -g root -m 644 "$tmpkey" "$keyring"
        rm -f "$tmpkey"
        echo "deb [arch=$(dpkg --print-architecture) signed-by=${keyring}] https://cli.github.com/packages stable main" \
            | $SUDO tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        $SUDO apt-get -qq update
        safe_apt_install gh
        ok "gh zainstalowany: $(gh --version | head -1)"
    fi
}

update_docker() {
    echo ""
    echo "=== Docker ==="
    if command -v docker &>/dev/null; then
        info "Aktualizacja Docker Engine..."
        $SUDO apt-get install -qqy --only-upgrade \
            docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
        ok "Docker zaktualizowany: $(docker --version)"
    else
        warn "Docker nie zainstalowany — uruchom initial_packages.sh aby zainstalować"
    fi

    info "Aktualizacja ctop..."
    local ctop_version
    ctop_version=$(curl -sf https://api.github.com/repos/bcicen/ctop/releases/latest \
        | grep '"tag_name":' | cut -d '"' -f 4)
    if [ -z "$ctop_version" ]; then
        warn "Nie udało się pobrać wersji ctop"
    else
        local ctop_bin="ctop-${ctop_version#v}-linux-amd64"
        local tmp_dir
        tmp_dir=$(mktemp -d)

        if ! curl -fsSL "https://github.com/bcicen/ctop/releases/download/${ctop_version}/${ctop_bin}" \
                -o "$tmp_dir/$ctop_bin"; then
            warn "Nie udało się pobrać ctop ${ctop_version}, pomijam aktualizację"
        elif ! curl -fsSL "https://github.com/bcicen/ctop/releases/download/${ctop_version}/sha256sums.txt" \
                -o "$tmp_dir/sha256sums.txt"; then
            warn "Nie udało się pobrać sha256sums.txt dla ctop ${ctop_version}, pomijam aktualizację"
        elif ! (cd "$tmp_dir" && grep " ${ctop_bin}\$" sha256sums.txt | sha256sum -c - --status); then
            warn "Suma sha256 ctop ${ctop_version} nie zgadza się z release'em — pomijam aktualizację"
        else
            $SUDO install -m 755 "$tmp_dir/$ctop_bin" /usr/local/bin/ctop
            ok "ctop zaktualizowany: $(ctop -v 2>&1 | head -1) (suma sha256 zweryfikowana)"
        fi
        rm -rf "$tmp_dir"
    fi
}

update_asdf() {
    echo ""
    echo "=== asdf ==="
    local asdf_bin="$HOME/.local/bin/asdf"
    if [ ! -x "$asdf_bin" ]; then
        warn "asdf nie zainstalowany — uruchom initial_packages.sh aby zainstalować"
        return 0
    fi

    local current_version latest_tag
    current_version=$("$asdf_bin" version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo '')
    latest_tag=$(curl -sf https://api.github.com/repos/asdf-vm/asdf/releases/latest \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$latest_tag" ]; then
        warn "Nie udało się pobrać najnowszej wersji asdf"
        return 0
    fi

    if [ "$current_version" = "$latest_tag" ]; then
        ok "asdf już w najnowszej wersji: $current_version"
        return 0
    fi

    info "Aktualizacja asdf $current_version → $latest_tag..."
    local archive="asdf-${latest_tag}-linux-amd64.tar.gz"
    cd "$HOME/.local/bin"
    curl -sL "https://github.com/asdf-vm/asdf/releases/download/${latest_tag}/${archive}" -o "$archive"
    rm -rf asdf
    tar -xzf "$archive"
    rm -f "$archive"
    ok "asdf zaktualizowany do $latest_tag"
}

update_difft() {
    echo ""
    echo "=== difftastic ==="
    local asdf_bin="$HOME/.local/bin/asdf"
    if [ ! -x "$asdf_bin" ]; then
        warn "asdf niedostępny — pomijam aktualizację difftastic"
        return 0
    fi
    if ! "$asdf_bin" list rust 2>/dev/null | grep -q '[0-9]'; then
        warn "Rust nie zainstalowany w asdf — pomijam aktualizację difftastic"
        return 0
    fi
    info "Aktualizacja difftastic..."
    "$asdf_bin" exec cargo install difftastic
    ok "difftastic zaktualizowany: $(difft --version)"
}

update_sdkman() {
    echo ""
    echo "=== SDKMAN ==="
    if [ ! -d "$HOME/.sdkman" ]; then
        warn "SDKMAN nie zainstalowany — uruchom initial_packages.sh aby zainstalować"
        return 0
    fi
    info "Aktualizacja SDKMAN..."
    # Run in subshell — sdk selfupdate may call exit internally
    (
        set +eu
        # shellcheck source=/dev/null
        source "$HOME/.sdkman/bin/sdkman-init.sh"
        sdk selfupdate
    ) || true

    info "Aktualizacja SDK (java, maven, mvnd)..."
    (
        set +eu
        # shellcheck source=/dev/null
        source "$HOME/.sdkman/bin/sdkman-init.sh"
        sdk upgrade java  || true
        sdk upgrade maven || true
        sdk upgrade mvnd  || true
    )
    ok "SDKMAN zaktualizowany"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "======================================="
echo "  update_packages — raport stanu"
echo "======================================="

check_apt_packages
check_gh
check_docker
check_asdf
check_difft
check_sdkman
check_apps

echo ""
echo "======================================="
echo "  Aktualizacja"
echo "======================================="

echo ""
echo "=== Klucze GPG ==="
refresh_apt_gpg_keys
update_apt_packages
update_gh
update_docker
update_asdf
update_difft
update_sdkman

echo ""
echo "======================================="
if [ "${#PACKAGES_UNAVAILABLE[@]}" -gt 0 ]; then
    echo ""
    warn "Pakiety niedostępne w repozytoriach (wymagają ręcznej interwencji):"
    for pkg in "${PACKAGES_UNAVAILABLE[@]}"; do
        warn "  - $pkg"
    done
fi
if [ "${#REPOS_DEAD[@]}" -gt 0 ]; then
    echo ""
    warn "Martwe repozytoria (404 / brak Release) — usuń ręcznie z /etc/apt/sources.list.d/:"
    for repo in "${REPOS_DEAD[@]}"; do
        warn "  - $repo"
    done
fi
echo ""
ok "Aktualizacja zakończona"
echo "======================================="
