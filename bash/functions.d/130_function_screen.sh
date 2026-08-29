#!/usr/bin/env bash

##
# Wykrywa środowisko graficzne (desktop/session) i zwraca (echo) jedno słowo:
# "darwin", "gnome", "sway", "wlroots", "x11", "wayland" — albo pustą linię
# i status 1, gdy nierozpoznane. Kolejność sprawdzania: GNOME (gdbus) ma
# priorytet nad X11, bo Mutter obsługuje oba przez tę samą metodę.
#
# Wydzielona, żeby funkcje sterujące ekranem (np. fake_poweroff) nie musiały
# powtarzać własnej detekcji.
##
function detect_display_env() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        echo "darwin"
        return 0
    fi

    local desktop="${XDG_CURRENT_DESKTOP:-}"
    local session="${XDG_SESSION_TYPE:-}"

    if [[ "$desktop" == *GNOME* ]] && command -v gdbus >/dev/null 2>&1; then
        echo "gnome"
        return 0
    fi

    if [[ "$session" == "x11" ]] || [ -n "${DISPLAY:-}" ]; then
        echo "x11"
        return 0
    fi

    if [[ "$session" == "wayland" ]]; then
        if command -v swaymsg >/dev/null 2>&1; then
            echo "sway"
            return 0
        fi
        if command -v wlopm >/dev/null 2>&1; then
            echo "wlroots"
            return 0
        fi
        echo "wayland"
        return 0
    fi

    echo ""
    return 1
}

export -f detect_display_env
