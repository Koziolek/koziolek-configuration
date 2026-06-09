#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

PROJECT_NAME='koziolek-configuration'

if ! command -v brew >/dev/null 2>&1; then
    echo "Instalacja Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
fi

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
    curl -s "https://get.sdkman.io" | bash
    # shellcheck source=/dev/null
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    sdk install java
    sdk install maven
    sdk install mvnd
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

echo "=== Instalacja pakietów macOS ==="
brew update

install_brew_packages "${system_tools[@]}"
install_brew_packages "${shell_tools[@]}"
install_brew_packages "${image_tools[@]}"
install_brew_packages "${diag_tools[@]}"

prepare_workspace
install_asdf
install_rust_and_difft
install_sdkman
install_docker
prepare_bashrc

echo ""
echo "✅ Instalacja zakończona!"
echo "Uruchom nowy terminal lub: source ~/.bashrc"
