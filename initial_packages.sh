#!/usr/bin/env bash

PROJECT_NAME='koziolek-configuration'

SUDO=''
if (( $EUID != 0 )); then
    SUDO='sudo'
fi

system_tools=(
  curl wget git vim unzip zip tree tmux htop thefuck neofetch hub xdotool lsb-release
)

security_tools=(
  gnupg gnupg2 apt-transport-https ca-certificates software-properties-common
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

all_packages=(
  "${system_tools[@]}"
  "${security_tools[@]}"
  "${graphics_libs[@]}"
  "${gui_libs[@]}"
  "${image_tools[@]}"
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
    sudo apt-get install -qqy "${ok_list[@]}"
  else
    echo "❌ No valid packages to install."
  fi
}

install_initial_packages() {
    # we need some universe repos
    $SUDO add-apt-repository universe -qy
    $SUDO apt-get -qq update
    safe_apt_install "${all_packages[@]}"
}

prepare_workspace() {
    set -e

    [ -d $HOME/workspace/ ] || mkdir workspace
    cd workspace || return

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
    curl -L "$DOWNLOAD_URL" -o "asdf-${LATEST_TAG}-linux-amd64.tar.gz"

    if [ $? -ne 0 ]; then
        echo "Błąd: nie udało się pobrać archiwum"
        return 1
    fi
    if [ -d "asdf" ]; then
        echo "Usuwanie poprzedniej instalacji asdf..."
        rm -rf "asdf"
    fi
    tar -xzf "asdf-${LATEST_TAG}-linux-amd64.tar.gz"

    if [ $? -ne 0 ]; then
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
    curl -s "https://get.sdkman.io" | bash
    source "$HOME/.sdkman/bin/sdkman-init.sh"
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
    
    # Zainstaluj docker-compose (standalone)
    echo "Instalacja docker-compose..."
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d '"' -f 4)
    $SUDO curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    $SUDO chmod +x /usr/local/bin/docker-compose
    
    # Zainstaluj docker-ctop
    echo "Instalacja docker-ctop..."
    CTOP_VERSION=$(curl -s https://api.github.com/repos/bcicen/ctop/releases/latest | grep '"tag_name":' | cut -d '"' -f 4)
    $SUDO curl -L "https://github.com/bcicen/ctop/releases/download/${CTOP_VERSION}/ctop-${CTOP_VERSION#v}-linux-amd64" -o /usr/local/bin/ctop
    $SUDO chmod +x /usr/local/bin/ctop
    
    # Sprawdź instalację
    echo "Sprawdzanie instalacji..."
    docker --version
    docker-compose --version
    ctop -v
    
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

cd $HOME/ || return

install_initial_packages
prepare_workspace
install_asdf
install_sdkman
install_apps
install_docker
prepare_bashrc

maybe_restart
