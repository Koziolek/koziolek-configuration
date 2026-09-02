#!/usr/bin/env bash

##
# Wykrywa środowisko graficzne (desktop/session) i zwraca (echo) jedno słowo:
# "gnome", "sway", "wlroots", "x11", "wayland" — albo pustą linię i status 1,
# gdy nierozpoznane. Kolejność sprawdzania: GNOME (gdbus) ma priorytet nad X11,
# bo Mutter obsługuje oba przez tę samą metodę.
#
# Wersja Linux. Na macOS bash/contexts/darwin.sh cieniuje ją tak, by zwracała
# "darwin". Wydzielona, żeby funkcje sterujące ekranem (np. fake_poweroff) nie
# musiały powtarzać własnej detekcji.
##
function detect_display_env() {
    local desktop="${XDG_CURRENT_DESKTOP:-}"
    local session="${XDG_SESSION_TYPE:-}"

    # Wayland ma priorytet nad $DISPLAY: pod Wayland Xwayland i tak ustawia
    # $DISPLAY=:0 (widać to np. w kontenerze apx Vanilla OS), więc heurystyka
    # "$DISPLAY => X11" jest fałszywa i kieruje na xdotool, który sypie błędami.
    if [ -n "${WAYLAND_DISPLAY:-}" ] || [[ "$session" == "wayland" ]]; then
        if [[ "$desktop" == *GNOME* ]] && command -v gdbus >/dev/null 2>&1; then
            echo "gnome"
            return 0
        fi
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

    # GNOME pod X11 — Mutter obsługuje oba warianty tą samą metodą Eval.
    if [[ "$desktop" == *GNOME* ]] && command -v gdbus >/dev/null 2>&1; then
        echo "gnome"
        return 0
    fi

    if [[ "$session" == "x11" ]] || [ -n "${DISPLAY:-}" ]; then
        echo "x11"
        return 0
    fi

    echo ""
    return 1
}

export -f detect_display_env
