#!/usr/bin/env bash
#
# Jednoplikowy bootstrap konfiguracji koziolek-configuration.
#
#     curl -fsSL https://raw.githubusercontent.com/Koziolek/koziolek-configuration/master/install.sh | bash
#     wget -qO-  https://raw.githubusercontent.com/Koziolek/koziolek-configuration/master/install.sh | bash
#
# Co robi — i nic więcej:
#   1. instaluje git (jeśli brak),
#   2. klonuje repo do ~/workspace/koziolek-configuration (+ symlink ~/.koziolek-configuration),
#   3. uruchamia initial_packages.sh Z KLONA — to on wykrywa system (bash/contexts/detect.sh),
#      rozróżnia host od subsystemu Vanilla OS i wybiera packages/initial_packages_<system>.sh.
#
# Cała logika wyboru systemu żyje w jednym miejscu (klon), nie ma jej kopii tutaj. Dla repo już
# sklonowanego ten sam krok 3 robi ręcznie:  ./initial_packages.sh   /   ./update_packages.sh
#
# Leci przez potok (`... | bash`) — NIE może zależeć od ${BASH_SOURCE[0]} jako ścieżki do pliku
# i niczego poza sobą nie pobiera z sieci (poza `git clone`).
#
# Zmienne środowiskowe:
#   KOZIOLEK_REF       — gałąź/tag do sklonowania (domyślnie domyślna gałąź repo); dotyczy tylko
#                        świeżego klona, istniejący klon zostaje nietknięty
#   PROJECT_CLONE_URL  — adres klona (domyślnie HTTPS; testy podstawiają lokalne repo)

set -Eeuo pipefail
trap 'echo "❌ install.sh: błąd w linii $LINENO"; exit 1' ERR

PROJECT_NAME='koziolek-configuration'
CLONE_URL="${PROJECT_CLONE_URL:-https://github.com/Koziolek/${PROJECT_NAME}.git}"
REF="${KOZIOLEK_REF:-}"

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

# ── 2. Klon repo ───────────────────────────────────────────────────────────
# Idempotentny, bez pull (lokalne zmiany użytkownika są nietykalne). Świeży klon
# respektuje KOZIOLEK_REF.
clone_repo() {
    local dir="$HOME/workspace/${PROJECT_NAME}"
    local link="$HOME/.${PROJECT_NAME}"

    mkdir -p "$HOME/workspace"

    if [ ! -d "$dir" ]; then
        if [ -n "$REF" ]; then
            git clone --branch "$REF" "$CLONE_URL" "$dir"
        else
            git clone "$CLONE_URL" "$dir"
        fi
    fi

    if [ ! -L "$link" ] && [ ! -d "$link" ]; then
        ln -sfn "$dir" "$link"
    fi
}

main() {
    ensure_git
    clone_repo

    local target="$HOME/.${PROJECT_NAME}/initial_packages.sh"
    if [ ! -f "$target" ]; then
        echo "❌ Brak $target po klonie repo." >&2
        exit 1
    fi

    echo "▶ Uruchamiam initial_packages.sh ..."
    bash "$target"

    echo ""
    echo "✅ Gotowe. Otwórz nowy terminal albo:  exec bash -l"
}

main "$@"
