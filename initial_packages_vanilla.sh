#!/usr/bin/env bash
#
# Instalacja początkowa dla Vanilla OS 2 ("Orchid" i nowsze).
#
# ── Gdzie to leci ────────────────────────────────────────────────────────────
# Vanilla OS jest immutable (ABRoot) — na hoście nie ma `sudo`, `/usr` i `/etc`
# bazy są tylko do odczytu, a `apt` żyje w subsystemie `apx` (kontener podman,
# obraz debianowy). Ten skrypt musi więc lecieć WEWNĄTRZ subsystemu:
#
#     vso shell            # albo:  apx enter
#     bash initial_packages_vanilla.sh
#
# W subsystemie `sudo` działa (rootless podman, użytkownik ma sudo w kontenerze).
#
# ── Czym różni się od initial_packages.sh (Ubuntu) ───────────────────────────
#   • baza to Debian sid, NIE Ubuntu → brak `add-apt-repository universe`
#     (wszystko jest w `main`);
#   • silnik kontenerów: `podman` + `podman-compose` zamiast Dockera
#     (natywne dla Vanilli, rootless, bez grupy `docker`, bez systemd w kontenerze);
#   • brak `systemctl start/enable`, brak `usermod -aG docker`, brak `reboot`;
#   • po `git clone` uruchamiamy `git/migrate_gitconfig.sh` — model include
#     `~/.gitconfig` nie migruje się sam, a stary symlink psuł `git config`;
#   • Steam pominięty (rootless kontener bez przekazania GPU / i386 — bez sensu;
#     na Vanilli to zadanie dla flatpaka na hoście: `com.valvesoftware.Steam`).
#
# Wspólna lista pakietów apt: packages/apt_packages.sh (ta sama co Ubuntu —
# kontener jest debianowy).

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

PROJECT_NAME='koziolek-configuration'
export DEBIAN_FRONTEND=noninteractive

# ── Guard: subsystem, nie immutable host ────────────────────────────────────
if [ ! -f /run/.containerenv ] && [ -z "${container:-}" ]; then
    echo "❌ Ten skrypt musi lecieć WEWNĄTRZ subsystemu apx (kontener), nie na immutable hoście Vanilla OS."
    echo "   Wejdź:   vso shell     (albo:  apx enter)"
    echo "   i dopiero wtedy:   bash $0"
    exit 1
fi
if [ -f /etc/os-release ] && ! grep -qE '^ID_LIKE=.*debian|^ID=(debian|vanilla|ubuntu)' /etc/os-release; then
    echo "⚠️  /etc/os-release nie wygląda na debianową bazę — apt może nie zadziałać."
fi

SUDO=''
if (( EUID != 0 )); then
    SUDO='sudo'
fi

prerequisites=(
    software-properties-common
)

minimal_tools=(
    curl wget
)

# Zainstaluj curl/wget NATYCHMIAST, zanim spróbujemy pobrać cokolwiek innego.
$SUDO apt-get -qq update
for _pkg in "${minimal_tools[@]}"; do
    command -v "$_pkg" >/dev/null 2>&1 || $SUDO apt-get install -qqy "$_pkg"
done
unset _pkg

# Lokalizacja wspólnej listy pakietów: lokalnie względem ${BASH_SOURCE[0]} po
# `git clone`, albo z repo na GitHubie gdy skrypt leci przez `curl ... | bash`.
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/packages/apt_packages.sh" ]; then
    # shellcheck source=packages/apt_packages.sh
    source "$SCRIPT_DIR/packages/apt_packages.sh"
else
    echo "Brak lokalnej kopii packages/apt_packages.sh — pobieram z repo..."
    _packages_tmp=$(mktemp)
    curl -fsSL \
        "https://raw.githubusercontent.com/Koziolek/${PROJECT_NAME}/refs/heads/master/packages/apt_packages.sh" \
        -o "$_packages_tmp"
    # shellcheck disable=SC1090
    source "$_packages_tmp"
    rm -f "$_packages_tmp"
    unset _packages_tmp
fi

# verify_and_run_script — wspólna z initial_packages.sh/initial_packages_mac.sh
# (packages/verify_and_run_script.sh), ten sam wzorzec lokalnie-albo-z-GitHuba co wyżej.
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
    $SUDO apt-get -qq update
    safe_apt_install "${prerequisites[@]}"
    # Debian sid — wszystko w `main`, brak komponentu `universe` (to Ubuntu).
    $SUDO apt-get -qq update
    safe_apt_install "${all_packages[@]}"
}

# prepare_workspace — wspólna z install.sh/initial_packages.sh/initial_packages_mac.sh
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

# Model include ~/.gitconfig (stub -> ~/.gitconfig.generated) nie migruje się sam.
# Maszyna zainicjowana pod starym modelem ma martwy symlink ~/.gitconfig, który
# psuje `git config` przy każdym starcie powłoki. migrate_gitconfig.sh jest
# bezpieczne do wielokrotnego uruchomienia.
migrate_gitconfig() {
    local mig="$HOME/.${PROJECT_NAME}/git/migrate_gitconfig.sh"
    if [ -f "$mig" ]; then
        echo "Migracja ~/.gitconfig na model include..."
        bash "$mig" || echo "⚠️ migrate_gitconfig.sh zakończone błędem — sprawdź ~/.gitconfig ręcznie"
    fi
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

    echo "Instalacja aplikacji przez .deb / repozytoria (bez Steam — patrz nagłówek)..."

    # Spotify — przez repozytorium. Klucz scoped przez signed-by= (nie trusted.gpg.d —
    # to zaufałoby kluczowi dla WSZYSTKICH repo apt, nie tylko Spotify).
    if ! command -v spotify >/dev/null 2>&1; then
        echo "Instalacja Spotify..."
        set +e
        $SUDO mkdir -p /etc/apt/keyrings
        curl -sS https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg \
            | $SUDO gpg --dearmor --yes -o /etc/apt/keyrings/spotify.gpg
        echo "deb [signed-by=/etc/apt/keyrings/spotify.gpg] https://repository.spotify.com stable non-free" \
            | $SUDO tee /etc/apt/sources.list.d/spotify.list >/dev/null
        $SUDO apt-get -qq update && $SUDO apt-get install -qqy spotify-client
        [ $? -ne 0 ] && echo "⚠️ Spotify — instalacja nieudana, pomijam"
        set -e
    fi

    cd "$DOWNLOAD_DIR" || return 1

    local -A apps=(
        ["1password"]="https://downloads.1password.com/linux/debian/amd64/stable/1password-latest.deb"
    )

    local app deb_file
    for app in "${!apps[@]}"; do
        deb_file="${app}.deb"
        set +e
        if [ ! -f "$deb_file" ] || [ $(($(date +%s) - $(stat -c %Y "$deb_file" 2>/dev/null || echo 0))) -gt 86400 ]; then
            echo "Pobieranie $app..."
            wget -O "$deb_file" "${apps[$app]}"
        fi
        echo "Instalacja $app..."
        $SUDO apt-get install -qqy "./$deb_file" || echo "⚠️ $app — instalacja nieudana, pomijam"
        set -e
    done

    echo "Aplikacje przetworzone."
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

# Pobiera ctop, weryfikuje sumę sha256 z release'a i instaluje do /usr/local/bin.
# ctop działa też z podmanem (docker-compat API socket).
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
        rm -rf "$tmp_dir"; return 0
    fi
    if ! curl -fsSL "https://github.com/bcicen/ctop/releases/download/${ctop_version}/sha256sums.txt" \
            -o "$tmp_dir/sha256sums.txt"; then
        echo "⚠️ Nie udało się pobrać sha256sums.txt dla ctop ${ctop_version}, pomijam instalację"
        rm -rf "$tmp_dir"; return 0
    fi
    if ! (cd "$tmp_dir" && grep " ${ctop_bin}\$" sha256sums.txt | sha256sum -c - --status); then
        echo "⚠️ Suma sha256 ctop ${ctop_version} nie zgadza się z release'em — pomijam instalację"
        rm -rf "$tmp_dir"; return 0
    fi

    $SUDO install -m 755 "$tmp_dir/$ctop_bin" /usr/local/bin/ctop
    rm -rf "$tmp_dir"
    echo "✓ ctop ${ctop_version} zainstalowany (suma sha256 zweryfikowana)"
}

# Pobiera kubectl z dl.k8s.io, weryfikuje sumę sha256 i instaluje do /usr/local/bin.
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
        rm -rf "$tmp_dir"; return 0
    fi
    if ! curl -fsSL "https://dl.k8s.io/release/${kubectl_version}/bin/linux/amd64/kubectl.sha256" \
            -o "$tmp_dir/kubectl.sha256"; then
        echo "⚠️ Nie udało się pobrać sumy sha256 dla kubectl ${kubectl_version}, pomijam instalację"
        rm -rf "$tmp_dir"; return 0
    fi
    if ! (cd "$tmp_dir" && echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c - --status); then
        echo "⚠️ Suma sha256 kubectl ${kubectl_version} nie zgadza się z release'em — pomijam instalację"
        rm -rf "$tmp_dir"; return 0
    fi

    $SUDO install -o root -g root -m 755 "$tmp_dir/kubectl" /usr/local/bin/kubectl
    rm -rf "$tmp_dir"
    echo "✓ kubectl ${kubectl_version} zainstalowany (suma sha256 zweryfikowana)"
}

# Vanilla: podman + podman-compose zamiast Dockera. Rootless, bez grupy `docker`,
# bez systemd w kontenerze. Podpięcie DOCKER_HOST/socketu do narzędzi mówiących
# po docker-API (ctop, services/) → to zadanie dla kontekstu `vanilla`.
install_podman_compose() {
    echo "Instalacja podman + podman-compose (silnik kontenerów VanillaOS)..."
    safe_apt_install podman podman-compose
    install_ctop

    echo "Weryfikacja:"
    command -v podman         >/dev/null 2>&1 && podman --version         || echo "  podman: niedostępny"
    command -v podman-compose >/dev/null 2>&1 && podman-compose --version || echo "  podman-compose: niedostępny"
    echo ""
    echo "ℹ️  podman jest rootless. Dla narzędzi po docker-API (ctop, docker compose):"
    echo "    systemctl --user enable --now podman.socket"
    echo "    export DOCKER_HOST=unix://\$XDG_RUNTIME_DIR/podman/podman.sock"
    echo "    (kontekst 'vanilla' ustawi to automatycznie — krok 6 planu)"
}

prepare_bashrc() {
    cd "$HOME/" || return
    cat "$HOME/.${PROJECT_NAME}/bash/templates/bashrc.template" > "$HOME/.bashrc"
}

final_notes() {
    echo ""
    echo "======================================================================"
    echo "  Instalacja początkowa VanillaOS zakończona."
    echo "======================================================================"
    echo "  • Przeładuj powłokę:   exec bash -l"
    echo "  • Docker/Compose:      podman + podman-compose (rootless)."
    echo "  • Steam:               na Vanilli przez flatpak na HOŚCIE, nie tutaj:"
    echo "                           flatpak install flathub com.valvesoftware.Steam"
    echo "  • Narzędzia sprzętowe z diag_tools (dmidecode, nvme-cli, smartmontools)"
    echo "    w rootless-kontenerze mają ograniczony dostęp do /dev — pełna"
    echo "    diagnostyka sprzętu: projekt fix-comp (patrz README)."
    echo ""
}

cd "$HOME/" || exit 1

install_initial_packages
prepare_workspace
migrate_gitconfig
install_asdf
install_rust_and_difft
install_sdkman
install_apps
install_gh
install_kubectl
install_podman_compose
prepare_bashrc
final_notes
