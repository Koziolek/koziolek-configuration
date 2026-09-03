#!/usr/bin/env bash
#
# Jednoplikowy bootstrap konfiguracji koziolek-configuration.
#
#     curl -fsSL https://raw.githubusercontent.com/Koziolek/koziolek-configuration/master/install.sh | bash
#     wget -qO-  https://raw.githubusercontent.com/Koziolek/koziolek-configuration/master/install.sh | bash
#
# Co robi:
#   1. wykrywa system (współdzieli detect_context z bash/contexts/detect.sh),
#   2. klonuje repo do ~/workspace/koziolek-configuration (+ symlink ~/.koziolek-configuration),
#   3. uruchamia właściwy packages/initial_packages_*.sh, który instaluje pakiety i stawia ~/.bashrc.
#
# Dla repo już sklonowanego — ten sam dispatch bez pobierania niczego z sieci:
#   ./initial_packages.sh   /   ./update_packages.sh
#
# Leci przez potok (`... | bash`) — NIE może zależeć od ${BASH_SOURCE[0]} jako
# ścieżki do pliku. Wszystkie zasoby ciągnie z RAW_BASE/REF.
#
# Zmienne środowiskowe:
#   KOZIOLEK_REF          — gałąź repo, z której lecą zasoby install.sh (domyślnie master)
#   INSTALL_DISPATCH_DRY_RUN — jeśli ustawione: wypisz wybrany skrypt i wyjdź (testy)
#   CONTAINERENV_FILE, HOST_OS_RELEASE_FILE — pośrednictwo dla testów (patrz niżej)

set -Eeuo pipefail
trap 'echo "❌ install.sh: błąd w linii $LINENO"; exit 1' ERR

PROJECT_NAME='koziolek-configuration'
REF="${KOZIOLEK_REF:-master}"
RAW_BASE="https://raw.githubusercontent.com/Koziolek/${PROJECT_NAME}/refs/heads/${REF}"

CONTAINERENV_FILE="${CONTAINERENV_FILE:-/run/.containerenv}"
HOST_OS_RELEASE_FILE="${HOST_OS_RELEASE_FILE:-/run/host/etc/os-release}"

_fetch() {
    # _fetch <ścieżka-w-repo> <plik-docelowy>
    curl -fsSL "$RAW_BASE/$1" -o "$2"
}

# ── 1. Minimalne narzędzia: curl (jest, skoro tu jesteśmy) + git ────────────
ensure_git() {
    command -v git >/dev/null 2>&1 && return 0

    if [ "$(uname -s)" = "Darwin" ]; then
        echo "git niedostępny. Uruchom:  xcode-select --install"
        echo "a po instalacji Command Line Tools — ponów ten sam curl | bash."
        xcode-select --install 2>/dev/null || true
        exit 1
    fi

    echo "Instalacja git..."
    local sudo=''
    (( EUID != 0 )) && sudo='sudo'
    $sudo apt-get -qq update
    $sudo apt-get install -qqy git
}

# ── 2. Wykrycie kontekstu ──────────────────────────────────────────────────
detect_ctx() {
    # Wymuszenie (testy/debug) — bez sięgania po sieć.
    if [ -n "${CONFIG_CONTEXT_FORCE:-}" ]; then
        printf '%s\n' "$CONFIG_CONTEXT_FORCE"
        return 0
    fi
    local tmp
    tmp=$(mktemp)
    _fetch "bash/contexts/detect.sh" "$tmp"
    # shellcheck disable=SC1090
    . "$tmp"
    rm -f "$tmp"
    detect_context
}

# ── 3. host vs subsystem Vanilla OS ────────────────────────────────────────
# detect_context zwraca 'vanilla' tylko na immutable hoście (ID=vanilla w
# /etc/os-release). Wewnątrz subsystemu apx /etc/os-release mówi 'debian' —
# rozpoznajemy go po /run/host/etc/os-release (bind z hosta).
# Zwraca kontekst na stdout. Kod 2 = jesteśmy na immutable hoście Vanilla
# (instalacja tu niemożliwa) — wołający ma przerwać.
#
# Duplikat resolve_vanilla_subsystem()/context_package_suffix() z
# bash/contexts/detect.sh — celowo NIE fetchowany stamtąd: install.sh z
# CONFIG_CONTEXT_FORCE ustawionym (testy) musi działać w 100% offline, bez
# żadnego zapytania sieciowego, a detect_ctx() poniżej fetchuje detect.sh
# tylko gdy FORCE nie jest ustawiony.
resolve_vanilla() {
    local ctx="$1"

    local in_container=0
    { [ -f "$CONTAINERENV_FILE" ] || [ -n "${container:-}" ]; } && in_container=1

    if [ "$ctx" = "vanilla" ] && [ "$in_container" -eq 0 ]; then
        printf '%s\n' "$ctx"
        return 2
    fi

    if [ "$in_container" -eq 1 ] && [ -r "$HOST_OS_RELEASE_FILE" ]; then
        local host_id host_like
        host_id=$(sed -n 's/^ID=//p' "$HOST_OS_RELEASE_FILE" | tr -d '"' | head -1)
        host_like=$(sed -n 's/^ID_LIKE=//p' "$HOST_OS_RELEASE_FILE" | tr -d '"' | head -1)
        case " $host_id $host_like " in
            *" vanilla "*) ctx="vanilla" ;;
        esac
    fi

    printf '%s\n' "$ctx"
}

# ── 4. Mapowanie kontekst → skrypt ────────────────────────────────────────
# Zwraca nazwę skryptu na stdout, kod 1 dla nieobsługiwanego systemu.
select_script() {
    case "$1" in
        darwin)                 echo "initial_packages_mac.sh" ;;
        vanilla)                echo "initial_packages_vanilla.sh" ;;
        ubuntu|debian|wsl)      echo "initial_packages_ubuntu.sh" ;;
        redhat)                 echo "initial_packages_redhat.sh" ;;
        *)                      return 1 ;;
    esac
}

main() {
    ensure_git

    local ctx script rc

    ctx=$(detect_ctx)

    rc=0; ctx=$(resolve_vanilla "$ctx") || rc=$?
    if [ "$rc" -eq 2 ]; then
        echo "❌ Jesteś na immutable hoście Vanilla OS — apt/instalacja tu nie zadziała." >&2
        echo "   Wejdź do subsystemu:   vso shell        (albo:  apx enter)" >&2
        echo "   i ponów:   curl -fsSL $RAW_BASE/install.sh | bash" >&2
        exit 1
    fi

    if ! script=$(select_script "$ctx"); then
        echo "❌ Nieobsługiwany system (kontekst: '$ctx')." >&2
        echo "   Obsługiwane: Ubuntu/Debian, macOS, Vanilla OS 2, WSL, RedHat/CentOS/Fedora." >&2
        exit 1
    fi

    echo "▶ System: $ctx  →  $script"

    if [ -n "${INSTALL_DISPATCH_DRY_RUN:-}" ]; then
        echo "$script"
        exit 0
    fi

    # ── 5. Klon repo ──────────────────────────────────────────────────────
    local tmp
    tmp=$(mktemp)
    _fetch "packages/prepare_workspace.sh" "$tmp"
    # shellcheck disable=SC1090
    . "$tmp"
    rm -f "$tmp"
    prepare_workspace

    # ── 6. Właściwy instalator pakietów (lokalny, z klona) ────────────────
    local target="$HOME/.${PROJECT_NAME}/packages/$script"
    if [ ! -f "$target" ]; then
        echo "❌ Brak $target po klonie repo." >&2
        exit 1
    fi
    echo "▶ Uruchamiam $script ..."
    bash "$target"

    # ── 7. ────────────────────────────────────────────────────────────────
    echo ""
    echo "✅ Gotowe. Otwórz nowy terminal albo:  exec bash -l"
}

main "$@"
