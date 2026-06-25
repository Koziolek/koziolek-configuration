#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---------------------------------------------------------------------------
# Package lists — keep in sync with initial_packages_mac.sh
# ---------------------------------------------------------------------------

system_tools=(
    curl wget git vim unzip zip tree tmux htop neofetch hub
)

shell_tools=(
    bash
    thefuck
    fd
    gnu-time
    gnu-sed
    coreutils
)

image_tools=(
    libheif
    imagemagick
)

diag_tools=(
    smartmontools
)

all_brew_packages=(
    "${system_tools[@]}"
    "${shell_tools[@]}"
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

brew_installed() {
    brew list "$1" &>/dev/null
}

# ---------------------------------------------------------------------------
# Phase 1: Status report
# ---------------------------------------------------------------------------

declare -a BREW_MISSING=()
declare -a BREW_INSTALLED=()
declare -a PACKAGES_UNAVAILABLE=()

check_brew_packages() {
    echo ""
    echo "=== Pakiety brew ==="
    local pkg
    for pkg in "${all_brew_packages[@]}"; do
        if brew_installed "$pkg"; then
            ok "$pkg"
            BREW_INSTALLED+=("$pkg")
        else
            missing "$pkg"
            BREW_MISSING+=("$pkg")
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

refresh_brew_state() {
    info "Odświeżanie stanu Homebrew..."

    # Repair broken symlinks and permissions
    brew cleanup --quiet 2>/dev/null || true

    local doctor_output
    doctor_output=$(brew doctor 2>&1 || true)

    if echo "$doctor_output" | grep -q "Your system is ready to brew"; then
        ok "Homebrew w porządku"
        return 0
    fi

    # Warn about issues but don't abort — many brew doctor warnings are cosmetic
    while IFS= read -r line; do
        [[ "$line" =~ ^Warning ]] && warn "$line"
    done <<< "$doctor_output"

    # Repair broken taps
    local broken_taps
    broken_taps=$(brew tap 2>/dev/null | while read -r tap; do
        brew tap-info "$tap" 2>&1 | grep -q "Error" && echo "$tap"
    done || true)

    if [[ -n "$broken_taps" ]]; then
        warn "Naprawianie uszkodzonych tap: $broken_taps"
        while IFS= read -r tap; do
            brew untap "$tap" 2>/dev/null || true
            brew tap "$tap" 2>/dev/null || warn "Nie udało się naprawić tap: $tap"
        done <<< "$broken_taps"
    fi

    info "brew update..."
    brew update --quiet
    ok "Stan Homebrew odświeżony"
}

update_brew_packages() {
    echo ""
    echo "=== Aktualizacja pakietów brew ==="

    if [ "${#BREW_INSTALLED[@]}" -gt 0 ]; then
        info "Aktualizacja zainstalowanych..."
        brew upgrade "${BREW_INSTALLED[@]}" 2>/dev/null || true
        ok "Zainstalowane zaktualizowane"
    fi

    if [ "${#BREW_MISSING[@]}" -gt 0 ]; then
        info "Instalacja brakujących: ${BREW_MISSING[*]}"
        local pkg
        for pkg in "${BREW_MISSING[@]}"; do
            if ! brew install "$pkg" 2>/dev/null; then
                warn "Instalacja '$pkg' nieudana"
                PACKAGES_UNAVAILABLE+=("$pkg")
            fi
        done
    fi
}

update_gh() {
    echo ""
    echo "=== GitHub CLI ==="
    if command -v gh &>/dev/null; then
        info "Aktualizacja gh..."
        brew upgrade gh 2>/dev/null || true
        ok "gh zaktualizowany: $(gh --version | head -1)"
    else
        info "Instalacja gh..."
        brew install gh
        ok "gh zainstalowany: $(gh --version | head -1)"
    fi
}

update_docker() {
    echo ""
    echo "=== Docker ==="
    if command -v docker &>/dev/null; then
        info "Aktualizacja Docker Desktop..."
        brew upgrade --cask docker 2>/dev/null || true
        ok "Docker zaktualizowany: $(docker --version)"
    else
        warn "Docker nie zainstalowany — uruchom initial_packages_mac.sh aby zainstalować"
    fi
}

update_asdf() {
    echo ""
    echo "=== asdf ==="
    local asdf_bin="$HOME/.local/bin/asdf"
    if [ ! -x "$asdf_bin" ]; then
        warn "asdf nie zainstalowany — uruchom initial_packages_mac.sh aby zainstalować"
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
    local arch
    arch="$(uname -m)"
    [[ "$arch" == "x86_64" ]] && arch="amd64"
    [[ "$arch" == "arm64" ]] && arch="arm64"

    local archive="asdf-${latest_tag}-darwin-${arch}.tar.gz"
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
        warn "SDKMAN nie zainstalowany — uruchom initial_packages_mac.sh aby zainstalować"
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

if ! command -v brew &>/dev/null; then
    echo "❌ Homebrew niedostępny — zainstaluj brew i spróbuj ponownie"
    exit 1
fi

echo "======================================="
echo "  update_packages_mac — raport stanu"
echo "======================================="

check_brew_packages
check_gh
check_docker
check_asdf
check_difft
check_sdkman

echo ""
echo "======================================="
echo "  Aktualizacja"
echo "======================================="

echo ""
echo "=== Stan repozytoriów ==="
refresh_brew_state
update_brew_packages
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
    echo ""
fi
ok "Aktualizacja zakończona"
echo "======================================="
