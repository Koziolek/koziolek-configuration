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

##
# fake_poweroff {off|on} — wygasza ekran i automatycznie wybudza go po ruchu
# myszy/klawiszu. Korzysta z detect_display_env() (wyżej) zamiast własnej
# detekcji środowiska — ten sam wzorzec co resize_to_full.
#
# Sterowanie monitorem per środowisko:
#   gnome        — gdbus, org.freedesktop.DBus.Properties.Set na PowerSaveMode
#                  (Mutter DisplayConfig; NIE SetPowerSaveMode — ta metoda nie
#                  istnieje, potwierdzone realnym błędem UnknownMethod)
#   x11          — xset dpms (ma natywny DPMS, budzi się sam na ruch/klawisz)
#   sway/wlroots — wlopm --off/--on per output (wlr-output-power-management)
#
# Auto-wybudzenie (watcher w tle, gnome/sway/wlroots — X11 ma własny DPMS):
# `libinput debug-events`, wymaga pakietu libinput-tools ORAZ członkostwa w
# grupie `input` (sudo usermod -aG input $USER + relogin — nie da się
# zastosować w trakcie trwającej sesji, stąd tylko ostrzeżenie i fallback
# bez auto-wybudzenia zamiast twardego błędu).
##
function fake_poweroff() {
    local action="${1:-off}"
    local pidfile="/tmp/fake-poweroff.pid"
    local env
    env="$(detect_display_env)"

    case "$env" in
        gnome | x11 | sway | wlroots) ;;
        *)
            log_error "fake_poweroff: nieobsługiwane środowisko graficzne (detect_display_env='$env')"
            log_info "fake_poweroff: obsługiwane: GNOME (gdbus), X11 (xset), sway/wlroots (wlopm)"
            return 1
            ;;
    esac

    _fp_off() {
        case "$env" in
        gnome)
            gdbus call --session \
                --dest org.gnome.Mutter.DisplayConfig \
                --object-path /org/gnome/Mutter/DisplayConfig \
                --method org.freedesktop.DBus.Properties.Set \
                org.gnome.Mutter.DisplayConfig PowerSaveMode "<int32 3>" >/dev/null
            ;;
        x11)
            xset +dpms
            xset dpms force off
            ;;
        sway | wlroots)
            local out
            for out in $(wlopm | cut -d' ' -f1); do wlopm --off "$out"; done
            ;;
        esac
    }

    _fp_on() {
        case "$env" in
        gnome)
            gdbus call --session \
                --dest org.gnome.Mutter.DisplayConfig \
                --object-path /org/gnome/Mutter/DisplayConfig \
                --method org.freedesktop.DBus.Properties.Set \
                org.gnome.Mutter.DisplayConfig PowerSaveMode "<int32 0>" >/dev/null
            ;;
        x11)
            xset dpms force on
            ;;
        sway | wlroots)
            local out
            for out in $(wlopm | cut -d' ' -f1); do wlopm --on "$out"; done
            ;;
        esac
    }

    case "$action" in
    off)
        _fp_off
        log_info "fake_poweroff: monitor wygaszony ($env)"

        if [[ "$env" != "x11" ]]; then
            if ! command -v libinput >/dev/null 2>&1; then
                log_warn "fake_poweroff: brak libinput — zainstaluj pakiet libinput-tools, żeby auto-wybudzenie działało"
            elif ! groups | grep -qw input; then
                log_warn "fake_poweroff: user nie jest w grupie 'input' — auto-wybudzenie nie zadziała"
                log_info "fake_poweroff: sudo usermod -aG input \$USER, potem wyloguj się i zaloguj ponownie"
            else
                (
                    stdbuf -oL libinput debug-events 2>/dev/null | while IFS= read -r line; do
                        case "$line" in
                        *POINTER_MOTION* | *POINTER_BUTTON* | *KEYBOARD_KEY*)
                            _fp_on
                            break
                            ;;
                        esac
                    done
                    rm -f "$pidfile"
                ) &
                disown
                echo $! >"$pidfile"
            fi
        fi
        ;;
    on)
        _fp_on
        if [[ -f "$pidfile" ]]; then
            kill "$(cat "$pidfile")" 2>/dev/null
            rm -f "$pidfile"
        fi
        log_info "fake_poweroff: monitor przywrócony ($env)"
        ;;
    *)
        log_man "Użycie: fake_poweroff {off|on}"
        return 1
        ;;
    esac
}

export -f fake_poweroff
