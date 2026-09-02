#!/usr/bin/env bash
#
# Aktualizacja pakietów dla Vanilla OS 2 — leci WEWNĄTRZ subsystemu `apx`
# (kontener podman, baza debianowa). Na immutable hoście `apt` nie działa.
#
#     vso shell            # albo:  apx enter
#     bash update_packages_vanilla.sh
#
# Różnice wobec update_packages.sh (Ubuntu):
#   • `podman` + `podman-compose` zamiast Dockera (check_podman / update_podman_compose);
#   • cleanup_stale_sources() — usuwa martwe źródła apt (np. docker.list z suite
#     `orchid`, który zwraca 404), jeśli Docker i tak nie jest zainstalowany;
#   • reszta (asdf, difft, sdkman, gh, kubectl, klucze GPG) — jak w wersji Ubuntu,
#     bo kontener jest debianowy.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

export DEBIAN_FRONTEND=noninteractive

if [ ! -f /run/.containerenv ] && [ -z "${container:-}" ]; then
    echo "❌ Ten skrypt musi lecieć WEWNĄTRZ subsystemu apx, nie na immutable hoście Vanilla OS."
    echo "   Wejdź:   vso shell     (albo:  apx enter)"
    exit 1
fi

SUDO=''
if (( EUID != 0 )); then
    SUDO='sudo'
fi

# ---------------------------------------------------------------------------
# Package lists — wspólne z initial_packages_vanilla.sh przez packages/apt_packages.sh
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

# refresh_apt_gpg_keys — wspólna z update_packages.sh (packages/gpg_fix.sh).
# shellcheck source=packages/gpg_fix.sh
source "$SCRIPT_DIR/packages/gpg_fix.sh"

# Vanilla-specyficzne: usuń martwe źródła apt, jeśli nie da się ich naprawić i nie
# są potrzebne. Konkretnie docker.list (suite `orchid` -> 404) gdy Docker nie jest
# zainstalowany — na Vanilli używamy podmana.
cleanup_stale_sources() {
    echo ""
    echo "=== Martwe źródła apt ==="
    local removed=0

    if [ -f /etc/apt/sources.list.d/docker.list ] && ! command -v docker >/dev/null 2>&1; then
        warn "docker.list obecny, ale Docker niezainstalowany (Vanilla używa podmana)."
        local reply=n
        read -r -p "Usunąć /etc/apt/sources.list.d/docker.list (+ keyring)? [y/N]: " -n 1 -r reply || reply=n
        echo
        if [[ "$reply" =~ ^[YyTt]$ ]]; then
            $SUDO rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
            ok "docker.list usunięty"
            (( removed++ )) || true
        fi
    fi

    if (( removed > 0 )); then
        $SUDO apt-get -qq update || true
    else
        ok "Brak martwych źródeł do wyczyszczenia"
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

check_podman() {
    echo ""
    echo "=== podman / podman-compose ==="
    if command -v podman &>/dev/null; then
        ok "podman: $(podman --version)"
    else
        missing "podman: nie zainstalowany"
    fi
    if command -v podman-compose &>/dev/null; then
        ok "podman-compose: $(podman-compose --version 2>&1 | head -1)"
    else
        missing "podman-compose: nie zainstalowany"
    fi
    if command -v ctop &>/dev/null; then
        ok "ctop: $(ctop -v 2>&1 | head -1)"
    else
        missing "ctop: nie zainstalowany"
    fi
}

check_kubectl() {
    echo ""
    echo "=== kubectl ==="
    if command -v kubectl &>/dev/null; then
        ok "kubectl: $(kubectl version --client 2>/dev/null | head -1)"
    else
        missing "kubectl: nie zainstalowany"
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

update_podman_compose() {
    echo ""
    echo "=== podman / podman-compose ==="
    if command -v podman &>/dev/null; then
        info "Aktualizacja podman + podman-compose..."
        $SUDO apt-get install -qqy --only-upgrade podman podman-compose 2>/dev/null || true
        ok "podman: $(podman --version)"
    else
        info "Instalacja podman + podman-compose..."
        safe_apt_install podman podman-compose
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

update_kubectl() {
    echo ""
    echo "=== kubectl ==="
    local kubectl_version
    kubectl_version=$(curl -Lfs https://dl.k8s.io/release/stable.txt)
    if [ -z "$kubectl_version" ]; then
        warn "Nie udało się pobrać wersji kubectl"
        return 0
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)

    if ! curl -fsSL "https://dl.k8s.io/release/${kubectl_version}/bin/linux/amd64/kubectl" \
            -o "$tmp_dir/kubectl"; then
        warn "Nie udało się pobrać kubectl ${kubectl_version}, pomijam aktualizację"
    elif ! curl -fsSL "https://dl.k8s.io/release/${kubectl_version}/bin/linux/amd64/kubectl.sha256" \
            -o "$tmp_dir/kubectl.sha256"; then
        warn "Nie udało się pobrać sumy sha256 dla kubectl ${kubectl_version}, pomijam aktualizację"
    elif ! (cd "$tmp_dir" && echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c - --status); then
        warn "Suma sha256 kubectl ${kubectl_version} nie zgadza się z release'em — pomijam aktualizację"
    else
        $SUDO install -o root -g root -m 755 "$tmp_dir/kubectl" /usr/local/bin/kubectl
        ok "kubectl zaktualizowany: $(kubectl version --client 2>/dev/null | head -1) (suma sha256 zweryfikowana)"
    fi
    rm -rf "$tmp_dir"
}

update_asdf() {
    echo ""
    echo "=== asdf ==="
    local asdf_bin="$HOME/.local/bin/asdf"
    if [ ! -x "$asdf_bin" ]; then
        warn "asdf nie zainstalowany — uruchom initial_packages_vanilla.sh aby zainstalować"
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
    # --locked: użyj Cargo.lock difftastica. Bez tego cargo dobiera najnowsze
    # zależności semver, a te (np. tree-sitter-language) wymuszają nowszego rustc
    # niż daje asdf → "rustc X is not supported by the following packages".
    "$asdf_bin" exec cargo install --locked difftastic
    ok "difftastic zaktualizowany: $(difft --version)"
}

update_sdkman() {
    echo ""
    echo "=== SDKMAN ==="
    if [ ! -d "$HOME/.sdkman" ]; then
        warn "SDKMAN nie zainstalowany — uruchom initial_packages_vanilla.sh aby zainstalować"
        return 0
    fi
    info "Aktualizacja SDKMAN..."
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
echo "  update_packages_vanilla — raport stanu"
echo "======================================="

check_apt_packages
check_gh
check_podman
check_kubectl
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
cleanup_stale_sources
update_apt_packages
update_gh
update_podman_compose
update_kubectl
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
