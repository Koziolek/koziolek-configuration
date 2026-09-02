#!/usr/bin/env bash
# Linux: detect_display_env / resize_to_full pod Wayland.
# Regresja: Xwayland ustawia $DISPLAY=:0, więc "DISPLAY => X11" kierowało
# resize_to_full na xdotool w sesji Wayland (błędy XGetWindowProperty).

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

_SCREEN="$PROJECT_ROOT/bash/functions.d/130_function_screen.sh"
_STARTUP="$PROJECT_ROOT/bash/functions.d/000_functions_startup.sh"

# _detect <env-assignments> <tool-mocks>
_detect() {
    env -u WAYLAND_DISPLAY -u DISPLAY -u XDG_SESSION_TYPE -u XDG_CURRENT_DESKTOP \
        bash --norc --noprofile -c "
        uname() { echo 'Linux'; }; export -f uname
        $2
        unset -f detect_display_env 2>/dev/null
        . '$_SCREEN' 2>/dev/null
        $1 detect_display_env
    "
}

testWaylandXwaylandNotDetectedAsX11() {
    local out
    out="$(_detect 'WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=sway' \
                   'swaymsg() { :; }; export -f swaymsg')"
    assertEquals 'sesja Wayland nie może być wykryta jako x11' 'sway' "$out"
}

testWaylandGnomeDetectedAsGnome() {
    local out
    out="$(_detect 'WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME' \
                   'gdbus() { :; }; export -f gdbus')"
    assertEquals 'GNOME/Wayland => gnome' 'gnome' "$out"
}

testWaylandWithoutToolsFallsBackToWayland() {
    local out
    out="$(_detect 'WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME' \
                   'PATH=/nonexistent')"
    assertEquals 'Wayland bez gdbus/swaymsg => wayland' 'wayland' "$out"
}

testPureX11StillDetectedAsX11() {
    local out
    out="$(_detect 'DISPLAY=:0 XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=XFCE' 'PATH=/nonexistent')"
    assertEquals 'czyste X11 => x11' 'x11' "$out"
}

testDetectDisplayEnvHasNoUnameGuard() {
    # Guard Darwin przeniesiony do bash/contexts/darwin.sh (cień).
    local body
    body="$(bash --norc --noprofile -c ". '$_SCREEN' 2>/dev/null; declare -f detect_display_env")"
    assertNotContains 'wersja Linux detect_display_env nie może sprawdzać uname' "$body" 'uname'
}

testResizeToFullDoesNotCallXdotoolUnderWayland() {
    local out
    out="$(env -u WAYLAND_DISPLAY -u DISPLAY -u XDG_SESSION_TYPE -u XDG_CURRENT_DESKTOP \
        bash --norc --noprofile -c "
        uname() { echo 'Linux'; }; export -f uname
        export WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME
        xdotool() { echo 'XDOTOOL-CALLED'; }; export -f xdotool
        gdbus() { :; }; export -f gdbus
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        . '$_SCREEN' 2>/dev/null
        . '$_STARTUP' 2>/dev/null
        resize_to_full 2>&1
    ")"
    assertNotContains 'resize_to_full nie może wołać xdotool pod Wayland' "$out" 'XDOTOOL-CALLED'
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
