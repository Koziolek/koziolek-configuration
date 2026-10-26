#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

PROJECT_NAME='koziolek-configuration'
export DEBIAN_FRONTEND=noninteractive

SUDO=''
if (( $EUID != 0 )); then
    SUDO='sudo'
fi

prerequisites=(
    software-properties-common
)

minimal_tools=(
    curl wget
)

# Zainstaluj curl/wget NATYCHMIAST, zanim spróbujemy pobrać cokolwiek innego.
# Obu potrzebujemy dalej (install_gh, install_apps), a wget nie musi być zainstalowany.
$SUDO apt-get -qq update
for _pkg in "${minimal_tools[@]}"; do
    command -v "$_pkg" >/dev/null 2>&1 || $SUDO apt-get install -qqy "$_pkg"
done
unset _pkg

# Katalog skryptu: biblioteki (listy pakietów, helpery) leżą obok. Skrypt zawsze leci z klona
# repo (install.sh -> initial_packages.sh), nie przez samodzielne `curl | bash`.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMONS_DIR="$SCRIPT_DIR/../commons"

# shellcheck source=packages/commons/apt_packages.sh
source "$COMMONS_DIR/apt_packages.sh"

# verify_and_run_script — wspólna z mac/install.sh/vanilla/install.sh
# (packages/commons/verify_and_run_script.sh).
# shellcheck source=packages/commons/verify_and_run_script.sh
source "$COMMONS_DIR/verify_and_run_script.sh"
# shellcheck source=packages/commons/sdk_tools_apply.sh
source "$COMMONS_DIR/sdk_tools_apply.sh"
# shellcheck source=packages/commons/lang_packages_apply.sh
source "$COMMONS_DIR/lang_packages_apply.sh"

all_packages=(
  "${minimal_tools[@]}"
  "${system_tools[@]}"
  "${security_tools[@]}"
  "${graphics_libs[@]}"
  "${gui_libs[@]}"
  "${image_tools[@]}"
  "${diag_tools[@]}"
  "${build_libs[@]}"
  "${boxes_vm[@]}"
)

safe_apt_install() {
  local pkg ok_list=()
  for pkg in "$@"; do
    # `apt-cache show` sam w sobie NIE wystarcza: pakiety przejściowe/dummy
    # (np. w trakcie transformacji nazwy w Debian sid) mają metadane/opis,
    # więc `apt-cache show` przechodzi, ale nie mają realnego kandydata do
    # instalacji na tej architekturze — dopiero `apt-get install` by to
    # wykrył, wywalając na CAŁEJ liście pakietów naraz (patrz #124).
    # `apt-cache policy` mówi wprost "Candidate: (none)" w takim przypadku.
    if apt-cache policy "$pkg" 2>/dev/null | grep -q 'Candidate: (none)'; then
      echo "⚠️ Package '$pkg' has no installation candidate, skipping"
    elif apt-cache show "$pkg" >/dev/null 2>&1; then
      ok_list+=("$pkg")
    else
      echo "⚠️ Package '$pkg' not found, skipping"
    fi
  done

  if [ "${#ok_list[@]}" -gt 0 ]; then
    echo "Installing: ${ok_list[*]}"
    $SUDO apt-get install -qqy "${ok_list[@]}"
  else
    echo "❌ No valid packages to install."
  fi
}

install_initial_packages() {
    # we need some universe repos
    $SUDO apt-get -qq update
    safe_apt_install "${prerequisites[@]}"
    $SUDO add-apt-repository -y universe
    # apt-get update z zapisem do logu (czyta go fix apt-gpg), potem naprawy: uszkodzony pakiet *-dkms
    # zablokowałby apt-get install na swoim postinst.
    fixes_refresh_apt_log
    apply_fixes pre-apt
    safe_apt_install "${all_packages[@]}"
    apply_fixes post-apt
}

# apply_fixes — rejestr napraw (#144), wspólny z update.sh. Tu fazy pre-apt/post-apt: bez nich uszkodzony
# pakiet *-dkms (stan iF, np. v4l2loopback-dkms: "DKMS tree already contains") blokuje każdy
# `apt-get install` (dpkg próbuje go dokończyć przy każdej instalacji). Wymaga ok/warn/info i $SUDO.
ok()   { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
# shellcheck source=packages/commons/fixes_apply.sh
source "$COMMONS_DIR/fixes_apply.sh"

# prepare_workspace — wspólna z install.sh/mac/install.sh/vanilla/install.sh
# (packages/commons/prepare_workspace.sh).
# shellcheck source=packages/commons/prepare_workspace.sh
source "$COMMONS_DIR/prepare_workspace.sh"

# link_claude_skills — podlinkowanie skilli z repo klaudyna do ~/.claude/skills
# (packages/commons/link_claude_skills.sh).
# shellcheck source=packages/commons/link_claude_skills.sh
source "$COMMONS_DIR/link_claude_skills.sh"

# install_git_bug — git-bug z GitHub Releases do ~/.local/bin, bez sudo
# (packages/commons/git_bug.sh).
# shellcheck source=packages/commons/git_bug.sh
source "$COMMONS_DIR/git_bug.sh"

install_asdf() {
    echo "Pobieranie informacji o najnowszej wersji asdf..."

    LATEST_TAG=$(curl -s https://api.github.com/repos/asdf-vm/asdf/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$LATEST_TAG" ]; then
        echo "Błąd: nie udało się pobrać informacji o najnowszej wersji"
        return 1
    fi

    echo "Najnowsza wersja: $LATEST_TAG"
    mkdir -p "$HOME/.local/bin"

    DOWNLOAD_URL="https://github.com/asdf-vm/asdf/releases/download/${LATEST_TAG}/asdf-${LATEST_TAG}-linux-amd64.tar.gz"

    echo "Pobieranie asdf z: $DOWNLOAD_URL"
    cd "$HOME/.local/bin"
    set +e
    curl -L "$DOWNLOAD_URL" -o "asdf-${LATEST_TAG}-linux-amd64.tar.gz"
    local curl_status=$?
    set -e
    if [ $curl_status -ne 0 ]; then
        echo "Błąd: nie udało się pobrać archiwum"
        return 1
    fi
    if [ -d "asdf" ]; then
        echo "Usuwanie poprzedniej instalacji asdf..."
        rm -rf "asdf"
    fi
    set +e
    tar -xzf "asdf-${LATEST_TAG}-linux-amd64.tar.gz"
    local tar_status=$?
    set -e
    if [ $tar_status -ne 0 ]; then
        echo "Błąd: nie udało się rozpakować archiwum"
        return 1
    fi
    rm -f "asdf-${LATEST_TAG}-linux-amd64.tar.gz"

    echo "asdf $LATEST_TAG został pomyślnie zainstalowany w $HOME/.local/bin/"
    echo "Dodaj następujące linie do swojego .bashrc:"
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo "source \$HOME/.local/bin/asdf/asdf.sh"
    echo "source \$HOME/.local/bin/asdf/completions/asdf.bash"
}

install_sdkman() {
    # get.sdkman.io nie jest statycznym plikiem w repo (dynamiczny endpoint SDKMAN),
    # więc nie ma oficjalnej sumy kontrolnej do zweryfikowania — zawsze zapyta.
    verify_and_run_script "instalator SDKMAN" "https://get.sdkman.io" || return 1
    install_sdkman_tools
}

install_claude() {
    if command -v claude &>/dev/null || [ -x "$HOME/.local/bin/claude" ]; then
        echo "✓ Claude Code już zainstalowany"
        return 0
    fi
    echo "Instalacja Claude Code..."
    # claude.ai/install.sh nie jest plikiem w repo GitHuba — brak oficjalnej sumy
    # kontrolnej, więc verify_and_run_script zawsze zapyta o zgodę (jak przy SDKMAN).
    verify_and_run_script "instalator Claude Code" "https://claude.ai/install.sh" || {
        echo "⚠️  Claude Code pominięty — zainstaluj ręcznie: curl -fsSL https://claude.ai/install.sh | bash"
        return 0
    }
}

# calibre_install_deps — libxcb-cursor (Qt xcb) przed instalatorem calibre
# shellcheck source=packages/commons/calibre_deps.sh
source "$COMMONS_DIR/calibre_deps.sh"

install_calibre() {
    if command -v calibre &>/dev/null; then
        echo "✓ calibre już zainstalowany"
        return 0
    fi
    echo "Instalacja calibre (oficjalny instalator binarny)..."
    calibre_install_deps
    # Strona calibre odradza pakiety dystrybucji (często nieaktualne) — używamy instalatora
    # z calibre-ebook.com. Brak oficjalnej sumy kontrolnej; błąd nie przerywa skryptu.
    { [ -z "$SUDO" ] || $SUDO -v; } \
        && wget -nv -O- https://download.calibre-ebook.com/linux-installer.sh | $SUDO sh /dev/stdin || {
        echo "⚠️  calibre pominięty — zainstaluj ręcznie: sudo -v && wget -nv -O- https://download.calibre-ebook.com/linux-installer.sh | sudo sh /dev/stdin"
        return 0
    }
}

install_apps() {
    local DOWNLOAD_DIR="$HOME/Pobrane"
    mkdir -p "$DOWNLOAD_DIR"

    echo "Instalacja aplikacji tylko przez .deb pakiety..."

    # Spotify przez repozytorium. Klucz scoped przez signed-by= (nie trusted.gpg.d —
    # to zaufałoby kluczowi dla WSZYSTKICH repo apt, nie tylko Spotify).
    if ! command -v spotify >/dev/null 2>&1; then
        echo "Instalacja Spotify..."
        $SUDO mkdir -p /etc/apt/keyrings
        curl -sS https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg \
            | $SUDO gpg --dearmor --yes -o /etc/apt/keyrings/spotify.gpg
        echo "deb [signed-by=/etc/apt/keyrings/spotify.gpg] https://repository.spotify.com stable non-free" \
            | $SUDO tee /etc/apt/sources.list.d/spotify.list >/dev/null
        $SUDO apt-get -qq update && $SUDO apt-get install -qqy spotify-client
    fi

    cd "$DOWNLOAD_DIR" || return 1

    # Przygotuj listę aplikacji do pobrania
    local -A apps=(
        ["1password"]="https://downloads.1password.com/linux/debian/amd64/stable/1password-latest.deb"
        ["steam"]="https://cdn.akamai.steamstatic.com/client/installer/steam.deb"
    )

    # Pobierz i zainstaluj każdą aplikację
    local app deb_file
    for app in "${!apps[@]}"; do
        deb_file="${app}.deb"

        if [ ! -f "$deb_file" ] || [ $(($(date +%s) - $(stat -c %Y "$deb_file" 2>/dev/null || echo 0))) -gt 86400 ]; then
            echo "Pobieranie $app..."
            wget -O "$deb_file" "${apps[$app]}"
        fi

        echo "Instalacja $app..."
        $SUDO apt-get install -qqy "./$deb_file"
    done

    # Specjalna konfiguracja dla Steam (architektura 32-bit)
    if [ -f "steam.deb" ]; then
        echo "Konfiguracja Steam (biblioteki 32-bit)..."
        $SUDO dpkg --add-architecture i386
        $SUDO apt-get update
        $SUDO apt-get install -qqy lib32gcc-s1 libc6-i386
        $SUDO apt-get install -fqqy  # napraw zależności
    fi

    echo "Wszystkie aplikacje zostały zainstalowane!"
}


install_gh() {
    if command -v gh &>/dev/null; then
        echo "✓ gh już zainstalowany: $(gh --version | head -1)"
        return 0
    fi

    echo "Instalacja GitHub CLI..."
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
    echo "✓ gh zainstalowany: $(gh --version | head -1)"
}

# Pobiera ctop, weryfikuje sumę sha256 z release'a i dopiero wtedy instaluje do
# /usr/local/bin. Przy niezgodności sumy: warning i rezygnacja z instalacji
# (nie zostawiamy niezweryfikowanej binarki w PATH roota).
install_ctop() {
    local ctop_version
    ctop_version=$(curl -sf https://api.github.com/repos/bcicen/ctop/releases/latest \
        | grep '"tag_name":' | cut -d '"' -f 4)
    if [ -z "$ctop_version" ]; then
        echo "⚠️ Nie udało się pobrać wersji ctop, pomijam instalację"
        return 0
    fi

    local ctop_bin="ctop-${ctop_version#v}-linux-amd64"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    if ! curl -fsSL "https://github.com/bcicen/ctop/releases/download/${ctop_version}/${ctop_bin}" \
            -o "$tmp_dir/$ctop_bin"; then
        echo "⚠️ Nie udało się pobrać ctop ${ctop_version}, pomijam instalację"
        rm -rf "$tmp_dir"
        return 0
    fi
    if ! curl -fsSL "https://github.com/bcicen/ctop/releases/download/${ctop_version}/sha256sums.txt" \
            -o "$tmp_dir/sha256sums.txt"; then
        echo "⚠️ Nie udało się pobrać sha256sums.txt dla ctop ${ctop_version}, pomijam instalację"
        rm -rf "$tmp_dir"
        return 0
    fi

    if ! (cd "$tmp_dir" && grep " ${ctop_bin}\$" sha256sums.txt | sha256sum -c - --status); then
        echo "⚠️ Suma sha256 ctop ${ctop_version} nie zgadza się z release'em — pomijam instalację"
        rm -rf "$tmp_dir"
        return 0
    fi

    $SUDO install -m 755 "$tmp_dir/$ctop_bin" /usr/local/bin/ctop
    rm -rf "$tmp_dir"
    echo "✓ ctop ${ctop_version} zainstalowany (suma sha256 zweryfikowana)"
}

# Pobiera kubectl z oficjalnego releasu Kubernetes (dl.k8s.io), weryfikuje sumę
# sha256 opublikowaną obok binarki i dopiero wtedy instaluje do /usr/local/bin.
# Nie ma go w domyślnych repo apt (bez dodawania cudzego repozytorium) — stąd
# ta sama metoda co ctop, zamiast apt.
install_kubectl() {
    local kubectl_version
    kubectl_version=$(curl -Lfs https://dl.k8s.io/release/stable.txt)
    if [ -z "$kubectl_version" ]; then
        echo "⚠️ Nie udało się pobrać wersji kubectl, pomijam instalację"
        return 0
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)

    if ! curl -fsSL "https://dl.k8s.io/release/${kubectl_version}/bin/linux/amd64/kubectl" \
            -o "$tmp_dir/kubectl"; then
        echo "⚠️ Nie udało się pobrać kubectl ${kubectl_version}, pomijam instalację"
        rm -rf "$tmp_dir"
        return 0
    fi
    if ! curl -fsSL "https://dl.k8s.io/release/${kubectl_version}/bin/linux/amd64/kubectl.sha256" \
            -o "$tmp_dir/kubectl.sha256"; then
        echo "⚠️ Nie udało się pobrać sumy sha256 dla kubectl ${kubectl_version}, pomijam instalację"
        rm -rf "$tmp_dir"
        return 0
    fi

    if ! (cd "$tmp_dir" && echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c - --status); then
        echo "⚠️ Suma sha256 kubectl ${kubectl_version} nie zgadza się z release'em — pomijam instalację"
        rm -rf "$tmp_dir"
        return 0
    fi

    $SUDO install -o root -g root -m 755 "$tmp_dir/kubectl" /usr/local/bin/kubectl
    rm -rf "$tmp_dir"
    echo "✓ kubectl ${kubectl_version} zainstalowany (suma sha256 zweryfikowana)"
}

install_docker() {
    echo "Instalacja Docker i docker-ctop..."
    
    # Usuń stare wersje Docker jeśli istnieją
    echo "Usuwanie starych wersji Docker..."
    $SUDO apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    
    # Dodaj klucz GPG Docker
    echo "Dodawanie klucza GPG Docker..."
    $SUDO mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Dodaj repozytorium Docker
    echo "Dodawanie repozytorium Docker..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Aktualizuj listę pakietów z nowym repozytorium
    $SUDO apt-get -qq update
    
    # Zainstaluj Docker Engine
    echo "Instalacja Docker Engine..."
    safe_apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Uruchom i włącz Docker service
    echo "Uruchamianie Docker service..."
    $SUDO systemctl start docker
    $SUDO systemctl enable docker
    
    # Dodaj użytkownika do grupy docker (aby można było uruchamiać bez sudo)
    echo "Dodawanie użytkownika $USER do grupy docker..."
    $SUDO groupadd docker 2>/dev/null || true  # grupa może już istnieć
    $SUDO usermod -aG docker $USER
    
    # Zainstaluj docker-ctop
    echo "Instalacja docker-ctop..."
    install_ctop

    # Sprawdź instalację
    echo "Sprawdzanie instalacji..."
    docker --version
    docker-compose --version
    command -v ctop &>/dev/null && ctop -v || echo "⚠️ ctop niedostępny, pomijam sprawdzenie"
    
    echo "Docker i docker-ctop zostały pomyślnie zainstalowane!"
    echo "Użytkownik $USER został dodany do grupy docker."
    echo ""
}

maybe_restart() {
    echo "UWAGA: Aby móc uruchamiać Docker bez sudo, musisz się wylogować i zalogować ponownie,"
    echo "lub zrestartować komputer, żeby zmiany w grupach zostały zaaplikowane."
    echo ""
    read -p "Czy chcesz zrestartować komputer teraz? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[YyTt]$ ]]; then
        echo "Restartowanie systemu..."
        $SUDO reboot
    else
        echo "Pamiętaj o wylogowaniu i ponownym zalogowaniu lub restarcie systemu!"
        echo "Możesz też uruchomić: newgrp docker"
    fi
}

prepare_bashrc() {
    cd "$HOME/" || return
    # `rm` przed `cp`: gdy `~/.bashrc` jest symlinkiem na szablon, `>` obcinałoby cel przez symlink.
    rm -f "$HOME/.bashrc"
    cp "$HOME/.${PROJECT_NAME}/bash/templates/bashrc.template" "$HOME/.bashrc"
}

cd "$HOME/" || exit 1

install_initial_packages
prepare_workspace
install_asdf
install_asdf_tools
install_lang_packages
install_sdkman
install_apps
install_gh
install_claude
install_calibre
install_git_bug
link_claude_skills
install_kubectl
install_docker
prepare_bashrc

maybe_restart
