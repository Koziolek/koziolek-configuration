#!/usr/bin/env bash
# macOS: detect_display_env nie ma już guardu uname w functions.d/ —
# wynik "darwin" daje cień z bash/contexts/darwin.sh.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

_SCREEN="$PROJECT_ROOT/bash/functions.d/130_function_screen.sh"
_DARWIN="$PROJECT_ROOT/bash/contexts/darwin.sh"

testDetectDisplayEnvReturnsDarwinViaContext() {
    local out
    out="$(env -u WAYLAND_DISPLAY -u DISPLAY -u XDG_SESSION_TYPE -u XDG_CURRENT_DESKTOP \
        bash --norc --noprofile -c "
        uname() { echo 'Darwin'; }; export -f uname
        hub() { :; }; export -f hub
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        . '$_SCREEN' 2>/dev/null
        . '$_DARWIN' 2>/dev/null
        detect_display_env
    ")"
    assertEquals 'z cieniem darwin.sh: detect_display_env = darwin' 'darwin' "$out"
}

testDetectDisplayEnvWithoutContextIsNotX11() {
    # Sama wersja z functions.d/ na macOS bez $DISPLAY/$WAYLAND_DISPLAY => "" (nie x11)
    local out
    out="$(env -u WAYLAND_DISPLAY -u DISPLAY -u XDG_SESSION_TYPE -u XDG_CURRENT_DESKTOP \
        bash --norc --noprofile -c "
        uname() { echo 'Darwin'; }; export -f uname
        . '$_SCREEN' 2>/dev/null
        detect_display_env
    ")"
    assertEquals 'bez kontekstu i bez DISPLAY => pusty wynik' '' "$out"
}

testLinuxVersionHasNoUnameGuard() {
    local body
    body="$(bash --norc --noprofile -c ". '$_SCREEN' 2>/dev/null; declare -f detect_display_env")"
    assertNotContains 'wersja z functions.d/ nie może sprawdzać uname' "$body" 'uname'
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
