#!/usr/bin/env bash
#
# Wykrywanie "kontekstu" środowiska + ładowanie plików per-kontekst.
#
# Motywacja: `$OS_TYPE` (uname -s) rozróżnia tylko Darwin/Linux. To za mało —
# Ubuntu, Debian, Vanilla OS i WSL to różne środowiska z różnymi ścieżkami,
# menedżerami pakietów i quirkami (Vanilla: kontener + Xwayland + brak Dockera).
#
# Model: `detect_context()` zwraca JEDNO słowo (liść), a `context_chain()`
# rozwija je w łańcuch od najbardziej ogólnego do najbardziej szczegółowego:
#
#     darwin  -> darwin
#     ubuntu  -> linux debian ubuntu
#     vanilla -> linux debian vanilla
#     debian  -> linux debian
#     wsl     -> linux debian wsl (WSL jest w praktyce zawsze Ubuntu/Debian pod spodem —
#                                   dziedziczy apt/hub z debian.sh)
#     redhat  -> linux redhat     (RHEL/CentOS/Fedora/Rocky/Alma — rodzina yum,
#                                   osobna od debian)
#     linux   -> linux            (fallback)
#
# `load_contexts()` sourcuje `bash/contexts/<c>.sh` w tej kolejności — plik
# bardziej szczegółowy widzi i nadpisuje to, co ustawił ogólniejszy.
#
# `$CONFIG_CONTEXT` (liść) jest eksportowane z main.sh, żeby widziały je też
# podsystemy git/services/tmux. `context_is <name>` sprawdza przynależność do
# łańcucha (np. `context_is debian` jest prawdą i dla ubuntu, i dla vanilla).
#
# Wymuszenie (testy/debug): `export CONFIG_CONTEXT_FORCE=vanilla`.
#
# Ten plik jest sourcowany WCZEŚNIE (z main.sh, przed bash/main.sh) — NIE może
# zależeć od helperów z bash_functions.sh (log_*, source_if_exists). load_contexts
# używa source_if_exists, więc jest wołane później, już z bash/main.sh.

detect_context() {
    if [ -n "${CONFIG_CONTEXT_FORCE:-}" ]; then
        printf '%s\n' "$CONFIG_CONTEXT_FORCE"
        return 0
    fi

    if [ "$(uname -s)" = "Darwin" ]; then
        printf 'darwin\n'
        return 0
    fi

    # WSL — środowisko ważniejsze niż dystrybucja pod spodem
    if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        printf 'wsl\n'
        return 0
    fi

    local os_release="${OS_RELEASE_FILE:-/etc/os-release}"
    local id="" id_like=""
    if [ -r "$os_release" ]; then
        # parsujemy, nie sourcujemy — żeby nie wstrzykiwać zmiennych do środowiska
        id=$(sed -n 's/^ID=//p' "$os_release" | tr -d '"' | head -1)
        id_like=$(sed -n 's/^ID_LIKE=//p' "$os_release" | tr -d '"' | head -1)
    fi

    case "$id" in
        vanilla) printf 'vanilla\n'; return 0 ;;
        ubuntu)  printf 'ubuntu\n';  return 0 ;;
        debian)  printf 'debian\n';  return 0 ;;
        rhel|centos|fedora|rocky|almalinux) printf 'redhat\n'; return 0 ;;
    esac

    case " $id_like " in
        *" debian "*|*" ubuntu "*) printf 'debian\n'; return 0 ;;
        *" rhel "*|*" fedora "*)   printf 'redhat\n'; return 0 ;;
    esac

    printf 'linux\n'
}

context_chain() {
    local ctx="${1:-${CONFIG_CONTEXT:-$(detect_context)}}"
    case "$ctx" in
        darwin)  printf 'darwin\n' ;;
        vanilla) printf 'linux\ndebian\nvanilla\n' ;;
        ubuntu)  printf 'linux\ndebian\nubuntu\n' ;;
        wsl)     printf 'linux\ndebian\nwsl\n' ;;
        debian)  printf 'linux\ndebian\n' ;;
        redhat)  printf 'linux\nredhat\n' ;;
        linux|*) printf 'linux\n' ;;
    esac
}

# context_is <name> — czy <name> jest w łańcuchu bieżącego kontekstu.
context_is() {
    local want="$1" c
    while IFS= read -r c; do
        [ "$c" = "$want" ] && return 0
    done < <(context_chain)
    return 1
}

# load_contexts — sourcuje bash/contexts/<c>.sh dla każdego ogniwa łańcucha.
# Wołane z bash/main.sh (po załadowaniu bash_functions.sh — potrzebuje source_if_exists).
load_contexts() {
    local dir="${CONTEXTS_DIR:-${BASH_CONFIGURATION_DIR:-}/contexts}"
    local c
    while IFS= read -r c; do
        source_if_exists "$c" "$dir"
    done < <(context_chain)
}

export -f detect_context
export -f context_chain
export -f context_is
export -f load_contexts
