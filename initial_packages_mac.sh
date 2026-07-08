#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

PROJECT_NAME='koziolek-configuration'

# Pobiera zdalny skrypt instalacyjny do pliku tymczasowego i próbuje zweryfikować
# go przez sumę kontrolną (git blob sha1 zgodny z tym, co zgłasza GitHub API dla
# danego pliku/repo/ref — działa tylko gdy skrypt jest hostowany na GitHubie).
# Jeśli suma jest niedostępna (brak parametrów gh_* albo API nie odpowiada) ALBO
# się nie zgadza — wypisuje ostrzeżenie i PYTA użytkownika o zgodę na kontynuację.
# Bez zgody funkcja zwraca 1 i nic nie uruchamia.
# Usage: verify_and_run_script "<opis>" "<url>" ["<gh_owner/repo>" "<sciezka>" "<ref>"]
verify_and_run_script() {
    local desc="$1" url="$2" gh_repo="${3:-}" gh_path="${4:-}" gh_ref="${5:-HEAD}"

    local tmp_script
    tmp_script=$(mktemp)
    if ! curl -fsSL "$url" -o "$tmp_script"; then
        echo "❌ Nie udało się pobrać: $desc ($url)"
        rm -f "$tmp_script"
        return 1
    fi

    local checksum_ok=false
    local reason=""

    if [ -n "$gh_repo" ]; then
        local expected_sha actual_sha size
        expected_sha=$(curl -sf "https://api.github.com/repos/${gh_repo}/contents/${gh_path}?ref=${gh_ref}" \
            | grep -o '"sha": *"[0-9a-f]\{40\}"' | head -1 | grep -o '[0-9a-f]\{40\}')
        if [ -z "$expected_sha" ]; then
            reason="Nie udało się pobrać oficjalnej sumy kontrolnej z GitHub API dla: $desc"
        else
            size=$(wc -c < "$tmp_script")
            actual_sha=$( { printf 'blob %d\0' "$size"; cat "$tmp_script"; } | sha1sum | awk '{print $1}')
            if [ "$actual_sha" = "$expected_sha" ]; then
                checksum_ok=true
            else
                reason="Suma kontrolna NIE ZGADZA SIĘ dla: $desc (oczekiwano ${expected_sha}, jest ${actual_sha})"
            fi
        fi
    else
        reason="Brak dostępnej oficjalnej sumy kontrolnej dla: $desc"
    fi

    if ! $checksum_ok; then
        echo "⚠️  $reason"
        echo "⚠️  Uruchomienie niezweryfikowanego skryptu z sieci: $url"
        local reply
        read -r -p "Kontynuować mimo to? [y/N]: " -n 1 -r reply
        echo
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            echo "❌ Przerwano na życzenie użytkownika: $desc"
            rm -f "$tmp_script"
            return 1
        fi
    else
        echo "✓ Suma kontrolna zweryfikowana (git blob sha1 zgodny z GitHub API): $desc"
    fi

    bash "$tmp_script"
    local rc=$?
    rm -f "$tmp_script"
    return $rc
}

install_homebrew() {
    if command -v brew >/dev/null 2>&1; then
        return 0
    fi
    echo "Instalacja Homebrew..."
    verify_and_run_script "instalator Homebrew" \
        "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" \
        "Homebrew/install" "install.sh" "HEAD" || return 1
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
}

minimal_tools=(
    curl wget
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packages/brew_packages.sh
source "$SCRIPT_DIR/packages/brew_packages.sh"

install_brew_packages() {
    local pkg
    for pkg in "$@"; do
        if brew list "$pkg" &>/dev/null; then
            echo "✓ $pkg już zainstalowany"
        else
            echo "Instalacja $pkg..."
            brew install "$pkg" || echo "⚠️ Nie udało się zainstalować $pkg, pomijam"
        fi
    done
}

prepare_workspace() {
    [ -d "$HOME/workspace/" ] || mkdir "$HOME/workspace/"
    cd "$HOME/workspace/" || return

    if [ ! -d "$HOME/workspace/${PROJECT_NAME}" ]; then
        git clone "https://github.com/Koziolek/${PROJECT_NAME}.git"
        ln -sfn "$HOME/workspace/${PROJECT_NAME}" "$HOME/.${PROJECT_NAME}"
    fi

    if [ ! -L "$HOME/.${PROJECT_NAME}" ] && [ ! -d "$HOME/.${PROJECT_NAME}" ]; then
        ln -sfn "$HOME/workspace/${PROJECT_NAME}" "$HOME/.${PROJECT_NAME}"
    fi
}

install_asdf() {
    if command -v asdf &>/dev/null; then
        echo "✓ asdf już zainstalowany"
        return 0
    fi

    echo "Pobieranie najnowszej wersji asdf..."
    local latest_tag
    latest_tag=$(curl -sf https://api.github.com/repos/asdf-vm/asdf/releases/latest \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$latest_tag" ]; then
        echo "Błąd: nie udało się pobrać wersji asdf"
        return 1
    fi

    local arch
    arch="$(uname -m)"
    [[ "$arch" == "x86_64" ]] && arch="amd64"
    [[ "$arch" == "arm64" ]] && arch="arm64"

    local archive="asdf-${latest_tag}-darwin-${arch}.tar.gz"
    local url="https://github.com/asdf-vm/asdf/releases/download/${latest_tag}/${archive}"

    mkdir -p "$HOME/.local/bin"
    cd "$HOME/.local/bin"
    curl -L "$url" -o "$archive"
    tar -xzf "$archive"
    rm -f "$archive"
    echo "✓ asdf $latest_tag zainstalowany w $HOME/.local/bin/"
}

install_rust_and_difft() {
    if command -v difft &>/dev/null; then
        echo "✓ difftastic już zainstalowany: $(difft --version)"
        return 0
    fi

    local asdf_bin="$HOME/.local/bin/asdf"
    if [ ! -x "$asdf_bin" ]; then
        echo "Błąd: asdf nie jest zainstalowany"
        return 1
    fi

    "$asdf_bin" plugin add rust https://github.com/asdf-community/asdf-rust.git 2>/dev/null || true
    "$asdf_bin" install rust latest
    "$asdf_bin" global rust latest

    local cargo_bin
    cargo_bin=$("$asdf_bin" which cargo 2>/dev/null)
    [ -z "$cargo_bin" ] && { echo "Błąd: cargo niedostępne"; return 1; }

    "$cargo_bin" install difftastic
    echo "✓ difftastic zainstalowany"
}

install_sdkman() {
    if [ -d "$HOME/.sdkman" ]; then
        echo "✓ SDKMAN już zainstalowany"
        return 0
    fi
    # get.sdkman.io nie jest statycznym plikiem w repo (dynamiczny endpoint SDKMAN),
    # więc nie ma oficjalnej sumy kontrolnej do zweryfikowania — zawsze zapyta.
    verify_and_run_script "instalator SDKMAN" "https://get.sdkman.io" || return 1
    set +u
    # shellcheck source=/dev/null
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    set -u
    sdk install java
    sdk install maven
    sdk install mvnd
}

install_gh() {
    if command -v gh &>/dev/null; then
        echo "✓ gh już zainstalowany: $(gh --version | head -1)"
        return 0
    fi
    echo "Instalacja GitHub CLI..."
    brew install gh
    echo "✓ gh zainstalowany: $(gh --version | head -1)"
}

install_docker() {
    if command -v docker &>/dev/null; then
        echo "✓ Docker już zainstalowany"
        return 0
    fi
    echo "Instalacja Docker Desktop na macOS wymaga ręcznego pobrania:"
    echo "  https://www.docker.com/products/docker-desktop/"
    echo "Albo: brew install --cask docker"
    read -r -p "Zainstalować przez brew cask? [y/N] " response
    if [[ "${response,,}" == "y" ]]; then
        brew install --cask docker
    fi
}

prepare_bashrc() {
    local template="$HOME/.${PROJECT_NAME}/bash/templates/bashrc.template"
    if [ -f "$template" ]; then
        cat "$template" > "$HOME/.bashrc"
    fi
    # On Mac, .bash_profile sources .bashrc if it exists
    if [ ! -f "$HOME/.bash_profile" ]; then
        cat > "$HOME/.bash_profile" <<'EOF'
if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
EOF
    fi
}

install_homebrew || exit 1

echo "=== Instalacja pakietów macOS ==="
brew update

install_brew_packages "${minimal_tools[@]}"
install_brew_packages "${system_tools[@]}"
install_brew_packages "${shell_tools[@]}"
install_brew_packages "${image_tools[@]}"
install_brew_packages "${diag_tools[@]}"

prepare_workspace
install_asdf
install_rust_and_difft
install_sdkman
install_gh
install_docker
prepare_bashrc

echo ""
echo "✅ Instalacja zakończona!"
echo "Uruchom nowy terminal lub: source ~/.bashrc"
