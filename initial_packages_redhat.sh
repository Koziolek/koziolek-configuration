#!/usr/bin/env bash
#
# Instalacja początkowa dla rodziny RedHat (RHEL, CentOS, Fedora, Rocky, Alma).
# Mirror initial_packages.sh (Ubuntu/Debian) — menedżer pakietów: yum.
#
# Różnice względem initial_packages.sh:
#   • yum zamiast apt-get; `epel-release` jako odpowiednik `add-apt-repository
#     universe` (best-effort — na czystej Fedorze epel-release nie istnieje,
#     safe_yum_install to pomija);
#   • install_apps() pomija Spotify/1Password/Steam — dystrybuowane jako .deb /
#     apt-repo, brak sensownego 1:1 na yum (zainstaluj ręcznie: flatpak / .rpm);
#   • install_gh()/install_docker() używają oficjalnych repo yum zamiast apt;
#   • install_asdf/install_rust_and_difft/install_sdkman/install_kubectl —
#     bez zmian, OS-agnostyczne (curl + binarki/tarball).

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

PROJECT_NAME='koziolek-configuration'

SUDO=''
if (( EUID != 0 )); then
    SUDO='sudo'
fi

prerequisites=(
    epel-release
)

minimal_tools=(
    curl wget
)

# Zainstaluj curl/wget NATYCHMIAST, zanim spróbujemy pobrać cokolwiek innego.
for _pkg in "${minimal_tools[@]}"; do
    command -v "$_pkg" >/dev/null 2>&1 || $SUDO yum install -y "$_pkg"
done
unset _pkg

# Lokalizacja wspólnej listy pakietów: jeśli skrypt leży na dysku (po `git
# clone`), source'ujemy plik lokalnie względem ${BASH_SOURCE[0]}. Gdy skrypt
# leci przez `curl ... | bash` (BASH_SOURCE puste), pobieramy ten sam plik
# z repo na GitHubie i source'ujemy z pliku tymczasowego (patrz initial_packages.sh).
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/packages/yum_packages.sh" ]; then
    # shellcheck source=packages/yum_packages.sh
    source "$SCRIPT_DIR/packages/yum_packages.sh"
else
    echo "Brak lokalnej kopii packages/yum_packages.sh — pobieram z repo..."
    _packages_tmp=$(mktemp)
    curl -fsSL \
        "https://raw.githubusercontent.com/Koziolek/${PROJECT_NAME}/refs/heads/master/packages/yum_packages.sh" \
        -o "$_packages_tmp"
    # shellcheck disable=SC1090
    source "$_packages_tmp"
    rm -f "$_packages_tmp"
    unset _packages_tmp
fi

# verify_and_run_script — wspólna z initial_packages.sh/initial_packages_mac.sh/
# initial_packages_vanilla.sh (packages/verify_and_run_script.sh), ten sam wzorzec
# lokalnie-albo-z-GitHuba co wyżej.
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

all_packages=(
  "${minimal_tools[@]}"
  "${system_tools[@]}"
  "${security_tools[@]}"
  "${graphics_libs[@]}"
  "${gui_libs[@]}"
  "${image_tools[@]}"
  "${diag_tools[@]}"
  "${boxes_vm[@]}"
)

safe_yum_install() {
  local pkg ok_list=()
  for pkg in "$@"; do
    if yum list "$pkg" >/dev/null 2>&1; then
      ok_list+=("$pkg")
    else
      echo "⚠️ Package '$pkg' not found, skipping"
    fi
  done

  if [ "${#ok_list[@]}" -gt 0 ]; then
    echo "Installing: ${ok_list[*]}"
    $SUDO yum install -y "${ok_list[@]}"
  else
    echo "❌ No valid packages to install."
  fi
}

install_initial_packages() {
    # epel-release: odpowiednik `add-apt-repository universe`. Best-effort —
    # na czystej Fedorze pakiet nie istnieje (repo już ma to, co daje EPEL na RHEL).
    $SUDO yum install -y epel-release 2>/dev/null || echo "ℹ️ epel-release niedostępny — pomijam (prawdopodobnie Fedora)"
    safe_yum_install "${all_packages[@]}"
}

# prepare_workspace — wspólna z install.sh/initial_packages.sh/initial_packages_mac.sh/
# initial_packages_vanilla.sh (packages/prepare_workspace.sh), ten sam wzorzec
# lokalnie-albo-z-GitHuba co wyżej.
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
    # --locked: użyj Cargo.lock difftastica. Bez tego cargo dobiera najnowsze
    # zależności semver, a te (np. tree-sitter-language) wymuszają nowszego rustc
    # niż daje asdf → "rustc X is not supported by the following packages".
    "$cargo_bin" install --locked difftastic
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
    echo "⚠️ Spotify/1Password/Steam są dystrybuowane jako .deb / repo apt —"
    echo "   brak sensownego instalatora yum, pomijam. Zainstaluj ręcznie:"
    echo "   • Spotify:  flatpak install flathub com.spotify.Client"
    echo "   • 1Password: https://1password.com/downloads/linux (oficjalne repo yum jest, ale różni się per dystrybucja)"
    echo "   • Steam:    https://repo.steampowered.com (RPM Fusion / oficjalne .rpm Valve)"
}

install_gh() {
    if command -v gh &>/dev/null; then
        echo "✓ gh już zainstalowany: $(gh --version | head -1)"
        return 0
    fi

    echo "Instalacja GitHub CLI..."
    $SUDO yum install -y yum-utils
    $SUDO yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
    safe_yum_install gh
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
# OS-agnostyczne — ta sama metoda co w initial_packages.sh.
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
    $SUDO yum remove -y docker docker-client docker-client-latest docker-common \
        docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true

    # Repo Dockera różni się per dystrybucja (fedora vs centos/rhel-kompatybilne).
    local docker_repo_flavor="centos"
    if [ -r /etc/os-release ] && grep -q '^ID=fedora' /etc/os-release; then
        docker_repo_flavor="fedora"
    fi

    echo "Dodawanie repozytorium Docker ($docker_repo_flavor)..."
    $SUDO yum install -y yum-utils
    $SUDO yum-config-manager --add-repo "https://download.docker.com/linux/${docker_repo_flavor}/docker-ce.repo"

    # Zainstaluj Docker Engine
    echo "Instalacja Docker Engine..."
    safe_yum_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Uruchom i włącz Docker service
    echo "Uruchamianie Docker service..."
    $SUDO systemctl start docker
    $SUDO systemctl enable docker

    # Dodaj użytkownika do grupy docker (aby można było uruchamiać bez sudo)
    echo "Dodawanie użytkownika $USER do grupy docker..."
    $SUDO groupadd docker 2>/dev/null || true  # grupa może już istnieć
    $SUDO usermod -aG docker "$USER"

    # Zainstaluj docker-ctop
    echo "Instalacja docker-ctop..."
    install_ctop

    # Sprawdź instalację
    echo "Sprawdzanie instalacji..."
    docker --version
    docker compose version 2>/dev/null || echo "⚠️ docker compose niedostępny, pomijam sprawdzenie"
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
install_kubectl
install_docker
prepare_bashrc

maybe_restart
