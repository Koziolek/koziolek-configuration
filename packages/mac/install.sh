#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

PROJECT_NAME='koziolek-configuration'

# Katalog skryptu: biblioteki (listy pakietów, helpery) leżą obok. Skrypt zawsze leci z klona
# repo (install.sh -> initial_packages.sh), nie przez samodzielne `curl | bash`.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMONS_DIR="$SCRIPT_DIR/../commons"

# verify_and_run_script — wspólna z ubuntu/install.sh/vanilla/install.sh
# (packages/commons/verify_and_run_script.sh).
# shellcheck source=packages/commons/verify_and_run_script.sh
source "$COMMONS_DIR/verify_and_run_script.sh"
# shellcheck source=packages/commons/sdk_tools_apply.sh
source "$COMMONS_DIR/sdk_tools_apply.sh"

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

# Homebrew musi istnieć przed czymkolwiek dalej (w tym przed brew-instalacją
# minimal_tools poniżej) — przeniesione na początek, zamiast czekać do końca pliku.
install_homebrew || exit 1

# macOS ma curl wbudowany, ale nie wget — dociągamy oba przez brew od razu,
# analogicznie do apt w ubuntu/install.sh (Linux).
for _pkg in "${minimal_tools[@]}"; do
    command -v "$_pkg" >/dev/null 2>&1 || brew install "$_pkg"
done
unset _pkg

# Wspólna lista pakietów: $SCRIPT_DIR już wyliczone na górze pliku (verify_and_run_script).
# shellcheck source=packages/mac/brew_packages.sh
source "$SCRIPT_DIR/brew_packages.sh"

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

# prepare_workspace — wspólna z install.sh/ubuntu/install.sh/vanilla/install.sh
# (packages/commons/prepare_workspace.sh).
# shellcheck source=packages/commons/prepare_workspace.sh
source "$COMMONS_DIR/prepare_workspace.sh"

# link_claude_skills — podlinkowanie skilli z repo klaudyna do ~/.claude/skills
# (packages/commons/link_claude_skills.sh).
# shellcheck source=packages/commons/link_claude_skills.sh
source "$COMMONS_DIR/link_claude_skills.sh"

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

install_difft() {
    if command -v difft &>/dev/null; then
        echo "✓ difftastic już zainstalowany: $(difft --version)"
        return 0
    fi

    local asdf_bin="$HOME/.local/bin/asdf"
    if [ ! -x "$asdf_bin" ]; then
        echo "Błąd: asdf nie jest zainstalowany"
        return 1
    fi

    local cargo_bin
    cargo_bin=$("$asdf_bin" which cargo 2>/dev/null || true)
    [ -z "$cargo_bin" ] && { echo "Błąd: cargo niedostępne"; return 1; }

    # --locked: użyj Cargo.lock difftastica (inaczej nowsze zależności wymuszają
    # nowszego rustc niż daje asdf).
    "$cargo_bin" install --locked difftastic
    echo "✓ difftastic zainstalowany"
}

install_sdkman() {
    if [ -d "$HOME/.sdkman" ]; then
        echo "✓ SDKMAN już zainstalowany"
        install_sdkman_tools
        return 0
    fi
    # get.sdkman.io nie jest statycznym plikiem w repo (dynamiczny endpoint SDKMAN),
    # więc nie ma oficjalnej sumy kontrolnej do zweryfikowania — zawsze zapyta.
    verify_and_run_script "instalator SDKMAN" "https://get.sdkman.io" || return 1
    install_sdkman_tools
}

install_claude() {
    if command -v claude &>/dev/null || brew list --cask claude-code &>/dev/null; then
        echo "✓ Claude Code już zainstalowany"
        return 0
    fi
    echo "Instalacja Claude Code..."
    brew install --cask claude-code
}

install_calibre() {
    if command -v calibre &>/dev/null || brew list --cask calibre &>/dev/null; then
        echo "✓ calibre już zainstalowany"
        return 0
    fi
    echo "Instalacja calibre..."
    # Oficjalnie: DMG przeciągany do Aplikacji (calibre-ebook.com/pl/download_osx) —
    # cask Homebrew robi to samo bez ręcznej pracy.
    brew install --cask calibre
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
        # `rm` przed `cp`: gdy `~/.bashrc` jest symlinkiem na szablon, `>` obcinałoby cel przez symlink.
        rm -f "$HOME/.bashrc"
        cp "$template" "$HOME/.bashrc"
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

install_brew_packages "${minimal_tools[@]}"
install_brew_packages "${system_tools[@]}"
install_brew_packages "${shell_tools[@]}"
install_brew_packages "${image_tools[@]}"
install_brew_packages "${diag_tools[@]}"

prepare_workspace
install_asdf
install_asdf_tools
install_difft
install_sdkman
install_gh
install_claude
install_calibre
link_claude_skills
install_docker
prepare_bashrc

echo ""
echo "✅ Instalacja zakończona!"
echo "Uruchom nowy terminal lub: source ~/.bashrc"
