#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

PROJECT_NAME='koziolek-configuration'

# Lokalizacja skryptu: potrzebna już tu (przed install_homebrew, które woła
# verify_and_run_script) — nie tylko przy okazji brew_packages.sh niżej. Jeśli skrypt
# leży na dysku (po `git clone`), source'ujemy pliki lokalnie względem ${BASH_SOURCE[0]}.
# Gdy leci przez `curl ... | bash` (BASH_SOURCE puste), pobieramy je z repo na GitHubie.
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# verify_and_run_script — wspólna z initial_packages.sh/initial_packages_vanilla.sh
# (packages/verify_and_run_script.sh).
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/packages/verify_and_run_script.sh" ]; then
    # shellcheck source=packages/verify_and_run_script.sh
    source "$SCRIPT_DIR/packages/verify_and_run_script.sh"
else
    _vars_tmp=$(mktemp)
    curl -fsSL \
        "https://raw.githubusercontent.com/Koziolek/${PROJECT_NAME}/refs/heads/master/packages/verify_and_run_script.sh" \
        -o "$_vars_tmp"
    # shellcheck disable=SC1090
    source "$_vars_tmp"
    rm -f "$_vars_tmp"
    unset _vars_tmp
fi

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
# analogicznie do apt w initial_packages.sh (Linux).
for _pkg in "${minimal_tools[@]}"; do
    command -v "$_pkg" >/dev/null 2>&1 || brew install "$_pkg"
done
unset _pkg

# Wspólna lista pakietów: $SCRIPT_DIR już wyliczone na górze pliku (verify_and_run_script).
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/packages/brew_packages.sh" ]; then
    # shellcheck source=packages/brew_packages.sh
    source "$SCRIPT_DIR/packages/brew_packages.sh"
else
    echo "Brak lokalnej kopii packages/brew_packages.sh — pobieram z repo..."
    _packages_tmp=$(mktemp)
    curl -fsSL \
        "https://raw.githubusercontent.com/Koziolek/${PROJECT_NAME}/refs/heads/master/packages/brew_packages.sh" \
        -o "$_packages_tmp"
    # shellcheck disable=SC1090
    source "$_packages_tmp"
    rm -f "$_packages_tmp"
    unset _packages_tmp
fi

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

# prepare_workspace — wspólna z install.sh/initial_packages.sh/initial_packages_vanilla.sh
# (packages/prepare_workspace.sh), ten sam wzorzec lokalnie-albo-z-GitHuba co wyżej.
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/packages/prepare_workspace.sh" ]; then
    # shellcheck source=packages/prepare_workspace.sh
    source "$SCRIPT_DIR/packages/prepare_workspace.sh"
else
    _pw_tmp=$(mktemp)
    curl -fsSL \
        "https://raw.githubusercontent.com/Koziolek/${PROJECT_NAME}/refs/heads/master/packages/prepare_workspace.sh" \
        -o "$_pw_tmp"
    # shellcheck disable=SC1090
    source "$_pw_tmp"
    rm -f "$_pw_tmp"
    unset _pw_tmp
fi

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

    # --locked: użyj Cargo.lock difftastica (inaczej nowsze zależności wymuszają
    # nowszego rustc niż daje asdf).
    "$cargo_bin" install --locked difftastic
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
