#!/usr/bin/env bash
# Kontekst: vanilla (Vanilla OS 2). Ładowany po `linux` i `debian`.
# Powłoka konfiguracji żyje w kontenerze `apx-vso-pico`; host jest immutable.
#
# DOCELOWO:
#   • helper mostka do hosta: h_host() { distrobox-host-exec "$@"; }
#   • instalacja pakietów: apx / abroot pkg (nie apt na hoście)

# --- Silnik kontenerów: podman (Vanilla nie ma Dockera) -------------------
# Funkcje w functions.d/040_function_docker.sh używają ${DOCKER_CLI:-docker}.
export DOCKER_CLI="podman"
if command -v podman-compose >/dev/null 2>&1; then
    export DOCKER_COMPOSE="podman-compose"
fi

# Socket rootless podmana — narzędzia mówiące po Docker API (ctop, compose v2,
# binarka docker-compose v5) używają go przez DOCKER_HOST.
_psock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock"
[ -S "$_psock" ] && export DOCKER_HOST="unix://$_psock"
unset _psock

# --- fix-net: resolv.conf kontenera -> host (przeniesione z bash_aliases.sh) --
# Było BŁĘDNIE aliasem dla całego "nie-Darwin"; to jest wyłącznie Vanilla
# (kontener apx montuje własny resolv.conf, DNS hosta bywa potrzebny ręcznie).
alias fix-net='sudo umount /etc/resolv.conf && sudo mount --rbind -o rslave /run/host/etc/resolv.conf /etc/resolv.conf'

# --- Czcionka konsoli tekstowej (TTY) -----------------------------------------
# Bez poprawnie wystartowanego tmuxa konsola wirtualna (Ctrl+Alt+F<n>) pokazuje domyślną
# czcionkę jądra bez polskich znaków. Lat2-Terminus16 (Latin-2, z mapą unicode) je ma.
# Tylko prawdziwy VT: TERM=linux + terminal na stdout. Terminal graficzny i tmux
# (TERM=xterm-*/tmux-*/screen-*) pomija się sam; w subsystemie apx bez dostępu do VT
# `setfont` kończy się błędem — milczymy. Zmiana nietrwała (do restartu / `setfont` bez
# argumentów). Inna czcionka: VANILLA_CONSOLE_FONT=…, wyłączenie: VANILLA_CONSOLE_FONT="".
vanilla_console_font() {
    local font="${VANILLA_CONSOLE_FONT-Lat2-Terminus16}"
    [ -n "$font" ] || return 0
    [ "${TERM:-}" = "linux" ] && [ -t 1 ] || return 0
    command -v setfont >/dev/null 2>&1 || return 0
    setfont "$font" >/dev/null 2>&1 || true
    return 0
}
vanilla_console_font
