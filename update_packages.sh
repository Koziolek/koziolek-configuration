#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

export DEBIAN_FRONTEND=noninteractive

SUDO=''
if (( EUID != 0 )); then
    SUDO='sudo'
fi

# ---------------------------------------------------------------------------
# Package lists — keep in sync with initial_packages.sh
# ---------------------------------------------------------------------------

system_tools=(
    curl wget git vim unzip zip tree tmux htop thefuck neofetch hub xdotool lsb-release iproute2
)

security_tools=(
    gnupg gnupg2 apt-transport-https ca-certificates
)

graphics_libs=(
    libatomic1 libgl1-mesa-dri libglx-mesa0 libegl1-mesa libgles2-mesa
    mesa-utils mesa-utils-extra libglvnd0 libglx0 libegl1 libgles2 libvulkan1
)

gui_libs=(
    gconf2-common gconf-service libgconf-2-4 libgdk-pixbuf2.0-0 libxcb-xtest0 libxcb-xinerama0
)

image_tools=(
    libheif-examples
)

diag_tools=(
    memtester stress-ng dmidecode pciutils lm-sensors smartmontools nvme-cli
)

all_apt_packages=(
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

# Maps repo hostname → "key_url|keyring_path"
# key_url may be armored (.asc) or binary (.gpg) — both handled via gpg --dearmor
declare -A _APT_GPG_KNOWN_REPOS=(
    ["repository.spotify.com"]="https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.gpg|/etc/apt/trusted.gpg.d/spotify.gpg"
    ["cli.github.com"]="https://cli.github.com/packages/githubcli-archive-keyring.gpg|/etc/apt/keyrings/githubcli-archive-keyring.gpg"
    ["download.docker.com"]="https://download.docker.com/linux/ubuntu/gpg|/etc/apt/keyrings/docker.gpg"
)

declare -a REPOS_DEAD=()

_gpg_save_key() {
    local src_file="$1" dst_path="$2"
    local tmp_out
    tmp_out="$(mktemp)"
    # Dearmor only if ASCII-armored; binary keys pass through as-is
    if grep -qE '^-----BEGIN' "$src_file" 2>/dev/null; then
        gpg --dearmor < "$src_file" > "$tmp_out" 2>/dev/null || { rm -f "$tmp_out"; return 1; }
    else
        cp "$src_file" "$tmp_out"
    fi
    $SUDO mkdir -p "$(dirname "$dst_path")"
    $SUDO install -o root -g root -m 644 "$tmp_out" "$dst_path"
    rm -f "$tmp_out"
}

refresh_apt_gpg_keys() {
    info "Sprawdzanie kluczy GPG repozytoriów apt..."

    local update_output
    update_output=$($SUDO apt-get update 2>&1 || true)

    # Detect dead repositories (404 / no Release file)
    while IFS= read -r line; do
        local dead_url
        dead_url=$(echo "$line" | grep -oE 'https?://[^[:space:]]+' | head -1 || true)
        [[ -z "$dead_url" ]] && continue
        REPOS_DEAD+=("$dead_url")
    done < <(echo "$update_output" | grep -E '404|nie ma pliku Release|does not have a Release file' || true)

    local -A keys_to_fix=()
    while IFS= read -r line; do
        local key_id repo_url
        key_id=$(echo "$line" | grep -oE 'NO_PUBKEY [0-9A-F]+' | awk '{print $2}' || true)
        repo_url=$(echo "$line" | grep -oE 'https?://[^[:space:]]+' | head -1 || true)
        [[ -z "$key_id" ]] && continue
        keys_to_fix["$key_id"]="${repo_url:-unknown}"
    done <<< "$update_output"

    if [ "${#keys_to_fix[@]}" -eq 0 ]; then
        ok "Klucze GPG w porządku"
        return 0
    fi

    warn "Brakujące klucze GPG: ${!keys_to_fix[*]}"

    local key_id repo_url hostname fixed=0
    for key_id in "${!keys_to_fix[@]}"; do
        repo_url="${keys_to_fix[$key_id]}"
        hostname=$(echo "$repo_url" | sed -E 's|https?://([^/]+).*|\1|' || true)

        info "Naprawa klucza $key_id (${hostname:-nieznane repo})..."

        local known_entry="${_APT_GPG_KNOWN_REPOS[$hostname]:-}"
        if [[ -n "$known_entry" ]]; then
            local key_url keyring_path tmpkey
            key_url="${known_entry%%|*}"
            keyring_path="${known_entry##*|}"
            tmpkey="$(mktemp)"
            if wget -qO "$tmpkey" "$key_url" 2>/dev/null; then
                _gpg_save_key "$tmpkey" "$keyring_path"
                rm -f "$tmpkey"
                ok "Klucz $key_id: pobrano z $key_url → $keyring_path"
                (( fixed++ )) || true
                continue
            fi
            rm -f "$tmpkey"
            warn "Klucz $key_id: oficjalny URL niedostępny, próba keyserver..."
        fi

        local recovered=/etc/apt/trusted.gpg.d/recovered-keys.gpg
        local tmprecovered
        tmprecovered="$(mktemp)"
        if gpg \
                --keyserver keyserver.ubuntu.com \
                --no-default-keyring \
                --keyring "$tmprecovered" \
                --recv-keys "$key_id" 2>/dev/null; then
            _gpg_save_key "$tmprecovered" "$recovered"
            rm -f "$tmprecovered"
            ok "Klucz $key_id: pobrano z keyserver.ubuntu.com → $recovered"
            (( fixed++ )) || true
        else
            rm -f "$tmprecovered"
            warn "Klucz $key_id: nie udało się naprawić"
        fi
    done

    if (( fixed > 0 )); then
        info "apt-get update po naprawie kluczy..."
        $SUDO apt-get -qq update 2>&1 | grep -v '^Pobieranie\|^Stary\|^Zign\|^Hit' || true
    fi
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
    ctop_version=$(curl -s https://api.github.com/repos/bcicen/ctop/releases/latest \
        | grep '"tag_name":' | cut -d '"' -f 4)
    if [ -n "$ctop_version" ]; then
        $SUDO curl -sL \
            "https://github.com/bcicen/ctop/releases/download/${ctop_version}/ctop-${ctop_version#v}-linux-amd64" \
            -o /usr/local/bin/ctop
        $SUDO chmod +x /usr/local/bin/ctop
        ok "ctop zaktualizowany: $(ctop -v 2>&1 | head -1)"
    else
        warn "Nie udało się pobrać wersji ctop"
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
