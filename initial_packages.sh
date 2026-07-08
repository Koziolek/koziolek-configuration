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

minimal_tools=(
    curl wget
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packages/apt_packages.sh
source "$SCRIPT_DIR/packages/apt_packages.sh"

all_packages=(
  "${minimal_tools[@]}"
  "${system_tools[@]}"
  "${security_tools[@]}"
  "${graphics_libs[@]}"
  "${gui_libs[@]}"
  "${image_tools[@]}"
  "${diag_tools[@]}"
)

safe_apt_install() {
  local pkg ok_list=()
  for pkg in "$@"; do
    if apt-cache show "$pkg" >/dev/null 2>&1; then
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
    $SUDO apt-get -qq update
    safe_apt_install "${all_packages[@]}"
}

prepare_workspace() {
    set -e

    [ -d "$HOME/workspace/" ] || mkdir "$HOME/workspace/"
    cd "$HOME/workspace/" || return

    if [ ! -d "$HOME/workspace/${PROJECT_NAME}" ]; then
        git clone "https://github.com/Koziolek/${PROJECT_NAME}.git"
        ln -sfn "$HOME/workspace/${PROJECT_NAME}" "$HOME/.${PROJECT_NAME}"
    fi

    if [ ! -L $HOME/.${PROJECT_NAME} ] && [ ! -d $HOME/.${PROJECT_NAME} ]; then
        ln -sfn $HOME/workspace/${PROJECT_NAME} $HOME/.${PROJECT_NAME}
    fi
    set +e
}

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

install_rust_and_difft() {
    if command -v difft &>/dev/null; then
        echo "difftastic już zainstalowany: $(difft --version)"
        return 0
    fi

    local asdf_bin="$HOME/.local/bin/asdf"
    if [ ! -x "$asdf_bin" ]; then
        echo "Błąd: asdf nie jest zainstalowany. Uruchom najpierw install_asdf."
        return 1
    fi

    echo "Dodawanie pluginu rust dla asdf..."
    "$asdf_bin" plugin add rust https://github.com/asdf-community/asdf-rust.git 2>/dev/null || true

    echo "Instalacja najnowszej wersji Rust..."
    "$asdf_bin" install rust latest
    "$asdf_bin" global rust latest

    local cargo_bin
    cargo_bin=$("$asdf_bin" which cargo 2>/dev/null)
    if [ -z "$cargo_bin" ]; then
        echo "Błąd: cargo niedostępne po instalacji Rust"
        return 1
    fi

    echo "Instalacja difftastic..."
    "$cargo_bin" install difftastic
    echo "difftastic zainstalowany pomyślnie"
}

install_sdkman() {
    # get.sdkman.io nie jest statycznym plikiem w repo (dynamiczny endpoint SDKMAN),
    # więc nie ma oficjalnej sumy kontrolnej do zweryfikowania — zawsze zapyta.
    verify_and_run_script "instalator SDKMAN" "https://get.sdkman.io" || return 1
    set +u
    # shellcheck source=/dev/null
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    set -u
    sdk i java
    sdk i maven
    sdk i mvnd

}

install_apps() {
    local DOWNLOAD_DIR="$HOME/Pobrane"
    mkdir -p "$DOWNLOAD_DIR"

    echo "Instalacja aplikacji tylko przez .deb pakiety..."

    # Spotify przez repozytorium
    if ! command -v spotify >/dev/null 2>&1; then
        echo "Instalacja Spotify..."
        curl -sS https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg | $SUDO gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
        echo "deb https://repository.spotify.com stable non-free" | $SUDO tee /etc/apt/sources.list.d/spotify.list >/dev/null
        $SUDO apt-get -qq update && $SUDO apt-get install -qqy spotify-client
    fi

    cd "$DOWNLOAD_DIR" || return 1

    # Przygotuj listę aplikacji do pobrania
    declare -A apps=(
        ["1password"]="https://downloads.1password.com/linux/debian/amd64/stable/1password-latest.deb"
        ["steam"]="https://cdn.akamai.steamstatic.com/client/installer/steam.deb"
    )

    # Pobierz i zainstaluj każdą aplikację
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
    cd $HOME/ || return
    cat "$HOME/.${PROJECT_NAME}/bash/templates/bashrc.template" > "$HOME/.bashrc"
}

cd "$HOME/" || exit 1

install_initial_packages
prepare_workspace
install_asdf
install_rust_and_difft
install_sdkman
install_apps
install_gh
install_docker
prepare_bashrc

maybe_restart
