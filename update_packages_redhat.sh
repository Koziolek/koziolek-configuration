#!/usr/bin/env bash
#
# Raport stanu + aktualizacja dla rodziny RedHat (RHEL/CentOS/Fedora/Rocky/Alma).
# Mirror update_packages.sh — yum zamiast apt. Sekcja "Klucze GPG"
# (refresh_apt_gpg_keys/gpg_fix.sh) pominięta — nie dotyczy modelu kluczy rpm.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

SUDO=''
if (( EUID != 0 )); then
    SUDO='sudo'
fi

# ---------------------------------------------------------------------------
# Package lists — wspólne z initial_packages_redhat.sh przez packages/yum_packages.sh
# ---------------------------------------------------------------------------

minimal_tools=(
    curl wget
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packages/yum_packages.sh
source "$SCRIPT_DIR/packages/yum_packages.sh"

all_yum_packages=(
    "${minimal_tools[@]}"
    "${system_tools[@]}"
    "${security_tools[@]}"
    "${graphics_libs[@]}"
    "${gui_libs[@]}"
    "${image_tools[@]}"
    "${diag_tools[@]}"
    "${boxes_vm[@]}"
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

yum_installed() {
    rpm -q "$1" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Phase 1: Status report
# ---------------------------------------------------------------------------

declare -a YUM_MISSING=()
declare -a YUM_INSTALLED=()
declare -a PACKAGES_UNAVAILABLE=()

check_yum_packages() {
    echo ""
    echo "=== Pakiety yum ==="
    local pkg
    for pkg in "${all_yum_packages[@]}"; do
        if yum_installed "$pkg"; then
            ok "$pkg"
            YUM_INSTALLED+=("$pkg")
        else
            missing "$pkg"
            YUM_MISSING+=("$pkg")
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

# ---------------------------------------------------------------------------
# Phase 2: Update / install
# ---------------------------------------------------------------------------

safe_yum_install() {
    local pkg
    for pkg in "$@"; do
        if ! yum list "$pkg" >/dev/null 2>&1; then
            warn "Pakiet '$pkg' niedostępny w repozytoriach, pomijam"
            PACKAGES_UNAVAILABLE+=("$pkg")
            continue
        fi
        if ! $SUDO yum install -y "$pkg" 2>/dev/null; then
            warn "Instalacja '$pkg' nieudana (błąd zależności)"
            PACKAGES_UNAVAILABLE+=("$pkg")
        fi
    done
}

update_yum_packages() {
    echo ""
    echo "=== Aktualizacja pakietów yum ==="

    if [ "${#YUM_INSTALLED[@]}" -gt 0 ]; then
        info "Aktualizacja zainstalowanych..."
        $SUDO yum update -y "${YUM_INSTALLED[@]}" 2>/dev/null || true
        ok "Zainstalowane zaktualizowane"
    fi

    if [ "${#YUM_MISSING[@]}" -gt 0 ]; then
        info "Instalacja brakujących: ${YUM_MISSING[*]}"
        safe_yum_install "${YUM_MISSING[@]}"
    fi
}

update_gh() {
    echo ""
    echo "=== GitHub CLI ==="
    if command -v gh &>/dev/null; then
        info "Aktualizacja gh..."
        $SUDO yum update -y gh 2>/dev/null || true
        ok "gh zaktualizowany: $(gh --version | head -1)"
    else
        info "Instalacja gh..."
        $SUDO yum install -y yum-utils
        $SUDO yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
        safe_yum_install gh
        ok "gh zainstalowany: $(gh --version | head -1)"
    fi
}

update_docker() {
    echo ""
    echo "=== Docker ==="
    if command -v docker &>/dev/null; then
        info "Aktualizacja Docker Engine..."
        $SUDO yum update -y \
            docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
        ok "Docker zaktualizowany: $(docker --version)"
    else
        warn "Docker nie zainstalowany — uruchom initial_packages_redhat.sh aby zainstalować"
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
        warn "asdf nie zainstalowany — uruchom initial_packages_redhat.sh aby zainstalować"
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
    # zależności semver, a te wymuszają nowszego rustc niż daje asdf.
    "$asdf_bin" exec cargo install --locked difftastic
    ok "difftastic zaktualizowany: $(difft --version)"
}

update_sdkman() {
    echo ""
    echo "=== SDKMAN ==="
    if [ ! -d "$HOME/.sdkman" ]; then
        warn "SDKMAN nie zainstalowany — uruchom initial_packages_redhat.sh aby zainstalować"
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
echo "  update_packages_redhat — raport stanu"
echo "======================================="

check_yum_packages
check_gh
check_docker
check_kubectl
check_asdf
check_difft
check_sdkman

echo ""
echo "======================================="
echo "  Aktualizacja"
echo "======================================="

update_yum_packages
update_gh
update_docker
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
echo ""
ok "Aktualizacja zakończona"
echo "======================================="
