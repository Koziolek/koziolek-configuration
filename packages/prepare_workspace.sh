#!/usr/bin/env bash
# Wspólna funkcja prepare_workspace dla install.sh, initial_packages_ubuntu.sh,
# initial_packages_mac.sh i initial_packages_vanilla.sh.
# Sourcowane, nie wykonywane — tylko definicja funkcji.
#
# Klonuje repo konfiguracji do ~/workspace/${PROJECT_NAME} i podpina symlink
# ~/.${PROJECT_NAME}. Idempotentne: istniejący katalog → nic nie robi
# (żadnego pull — lokalne zmiany użytkownika są nietykalne).
#
# Wymaga zmiennej PROJECT_NAME u wołającego. Adres klona można nadpisać
# zmienną PROJECT_CLONE_URL (domyślnie HTTPS — świeża maszyna nie ma klucza SSH).

prepare_workspace() {
    local project="${PROJECT_NAME:?PROJECT_NAME nie ustawione}"
    local url="${PROJECT_CLONE_URL:-https://github.com/Koziolek/${project}.git}"

    set -e

    [ -d "$HOME/workspace/" ] || mkdir "$HOME/workspace/"
    cd "$HOME/workspace/" || return

    if [ ! -d "$HOME/workspace/${project}" ]; then
        git clone "$url"
        ln -sfn "$HOME/workspace/${project}" "$HOME/.${project}"
    fi

    if [ ! -L "$HOME/.${project}" ] && [ ! -d "$HOME/.${project}" ]; then
        ln -sfn "$HOME/workspace/${project}" "$HOME/.${project}"
    fi

    set +e
}
