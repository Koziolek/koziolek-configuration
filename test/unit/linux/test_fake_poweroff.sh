#!/usr/bin/env bash
# fake_poweroff (bash/functions.d/130_function_screen.sh) — routing przez
# detect_display_env(), sterowanie monitorem per środowisko (gdbus/xset/wlopm),
# watcher auto-wybudzenia (libinput) i jego zależności (pakiet + grupa 'input').
# Mockuje gdbus/xset/wlopm/libinput/groups — bez tego testy zależałyby od realnego
# środowiska graficznego hosta/kontenera.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

_LOG="$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
_SCREEN="$PROJECT_ROOT/bash/functions.d/130_function_screen.sh"

# _run <env-assignments> <tool-mocks> <fake_poweroff-args...>
# env-assignments: zmienne XDG_*/WAYLAND_DISPLAY konsumowane przez detect_display_env.
# tool-mocks: definicje funkcji gdbus/xset/wlopm/libinput/groups przed sourcowaniem.
_run() {
    local env_assign="$1" mocks="$2"
    shift 2
    env -u WAYLAND_DISPLAY -u DISPLAY -u XDG_SESSION_TYPE -u XDG_CURRENT_DESKTOP \
        bash --norc --noprofile -c "
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        $env_assign
        $mocks
        . '$_LOG' 2>/dev/null
        . '$_SCREEN' 2>/dev/null
        fake_poweroff $*
    " 2>&1
}

# --- GNOME (X11 lub Wayland — gdbus ma priorytet) ---------------------------

testGnomeOffCallsGdbusPowerSaveMode3() {
    local out
    out="$(_run 'XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=GNOME DISPLAY=:0' \
        'gdbus() { echo "GDBUS_CALL:$*" >&2; }; export -f gdbus' \
        off)"
    assertContains 'GNOME off musi wywołać gdbus z PowerSaveMode 3' "$out" 'PowerSaveMode <int32 3>'
    assertContains 'GNOME off musi zalogować wygaszenie środowiska' "$out" 'wygaszony (gnome)'
}

testGnomeOnCallsGdbusPowerSaveMode0() {
    local out
    out="$(_run 'XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=GNOME DISPLAY=:0' \
        'gdbus() { echo "GDBUS_CALL:$*" >&2; }; export -f gdbus' \
        on)"
    assertContains 'GNOME on musi wywołać gdbus z PowerSaveMode 0' "$out" 'PowerSaveMode <int32 0>'
    assertContains 'GNOME on musi zalogować przywrócenie' "$out" 'przywrócony (gnome)'
}

# --- X11 (bez GNOME) — DPMS, bez watchera -----------------------------------

testX11OffCallsXsetDpms() {
    local out
    out="$(_run 'XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=XFCE DISPLAY=:0' \
        'xset() { echo "XSET_CALL:$*"; }; export -f xset' \
        off)"
    assertContains 'X11 off musi wywołać xset dpms force off' "$out" 'XSET_CALL:dpms force off'
}

testX11OffDoesNotStartWatcher() {
    # X11 ma natywny DPMS — nie powinien w ogóle sprawdzać libinput/grupy.
    local out
    out="$(_run 'XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=XFCE DISPLAY=:0' \
        'xset() { :; }; export -f xset
         libinput() { echo "LIBINPUT_CALLED"; }; export -f libinput' \
        off)"
    assertNotContains 'X11 nie może odpalać watchera libinput' "$out" 'LIBINPUT_CALLED'
    assertNotContains 'X11 nie może ostrzegać o libinput/grupie input' "$out" 'libinput'
}

# --- sway/wlroots — wlopm ----------------------------------------------------

testWlrootsOffCallsWlopmPerOutput() {
    local out
    out="$(_run 'WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=sway' \
        'swaymsg() { :; }; export -f swaymsg
         wlopm() { if [ "$1" = "--off" ]; then echo "WLOPM_OFF:$2"; else echo "eDP-1 enabled"; fi; }; export -f wlopm' \
        off)"
    assertContains 'sway/wlroots off musi wywołać wlopm --off na wykrytym outpucie' "$out" 'WLOPM_OFF:eDP-1'
}

# --- watcher: zależności (libinput-tools + grupa input) ---------------------

testOffWithoutLibinputWarns() {
    local out
    out="$(_run 'WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=sway' \
        'swaymsg() { :; }; export -f swaymsg
         wlopm() { :; }; export -f wlopm' \
        off)"
    assertContains 'brak libinput musi dać ostrzeżenie o libinput-tools' "$out" 'libinput-tools'
}

testOffWithLibinputButWithoutGroupWarns() {
    local out
    out="$(_run 'WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=sway' \
        'swaymsg() { :; }; export -f swaymsg
         wlopm() { :; }; export -f wlopm
         libinput() { :; }; export -f libinput
         groups() { echo "user adm sudo"; }; export -f groups' \
        off)"
    assertContains 'brak grupy input musi dać ostrzeżenie' "$out" "grupie 'input'"
    assertContains 'ostrzeżenie musi podać komendę usermod' "$out" 'usermod -aG input'
}

testOffWithLibinputAndGroupStartsWatcherWithoutWarning() {
    # libinput debug-events zamockowany tak, żeby od razu zwrócić EOF — watcher
    # kończy się natychmiast, bez wiszącego procesu w tle po teście.
    local out
    out="$(_run 'WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=sway' \
        'swaymsg() { :; }; export -f swaymsg
         wlopm() { :; }; export -f wlopm
         libinput() { :; }; export -f libinput
         stdbuf() { shift 1; "$@"; }; export -f stdbuf
         groups() { echo "user input"; }; export -f groups' \
        off)"
    assertNotContains 'z libinput i grupą input nie może być ostrzeżenia o libinput-tools' "$out" 'libinput-tools'
    assertNotContains 'z libinput i grupą input nie może być ostrzeżenia o grupie' "$out" "grupie 'input'"
}

# --- nieobsługiwane środowisko / zła akcja ----------------------------------

testUnsupportedEnvReturnsError() {
    local out rc=0
    out="$(_run '' '' off)" || rc=$?
    assertNotEquals 'nierozpoznane środowisko musi zwrócić błąd' 0 "$rc"
    assertContains "$out" 'nieobsługiwane środowisko graficzne'
}

testInvalidActionShowsUsage() {
    local out rc=0
    out="$(_run 'XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=GNOME DISPLAY=:0' \
        'gdbus() { :; }; export -f gdbus' \
        bogus)" || rc=$?
    assertNotEquals 'zła akcja musi zwrócić błąd' 0 "$rc"
    assertContains "$out" 'Użycie: fake_poweroff'
}

testFakePoweroffUsesDetectDisplayEnvNotOwnDetection() {
    # Regresja z issue #20: fake_poweroff ma korzystać z detect_display_env(),
    # nie duplikować własnej detekcji XDG_CURRENT_DESKTOP/XDG_SESSION_TYPE.
    local body
    body="$(bash --norc --noprofile -c ". '$_SCREEN' 2>/dev/null; declare -f fake_poweroff")"
    assertContains 'fake_poweroff musi wołać detect_display_env' "$body" 'detect_display_env'
    assertNotContains 'fake_poweroff nie może sam czytać XDG_CURRENT_DESKTOP' "$body" 'XDG_CURRENT_DESKTOP'
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
