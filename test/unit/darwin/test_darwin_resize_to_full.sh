#!/usr/bin/env bash
# macOS-specific: resize_to_full musi być no-op (return 0) gdy uname zwraca Darwin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

hub() { :; }  # nie instaluj huba przez brew podczas testów

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/130_function_screen.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/000_functions_startup.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/contexts/darwin.sh"

_run_resize_darwin() {
    bash --norc --noprofile -c "
        uname() { echo 'Darwin'; }; export -f uname
        hub() { :; }; export -f hub
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/functions.d/130_function_screen.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/functions.d/000_functions_startup.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/contexts/darwin.sh' 2>/dev/null
        resize_to_full ${1:-}
    "
}

testResizeToFullReturns0WhenDarwin() {
    _run_resize_darwin '2>/dev/null'
    assertEquals 'resize_to_full musi zwrócić 0 gdy uname=Darwin' 0 $?
}

testResizeToFullProducesNoOutputWhenDarwin() {
    local out
    out="$(_run_resize_darwin 2>&1)"
    assertEquals 'resize_to_full musi być cicha na Darwin' '' "$out"
}

testResizeToFullDelegatesToDetectDisplayEnv() {
    local body
    body="$(declare -f resize_to_full)"
    assertContains 'resize_to_full musi routować po detect_display_env' \
        "$body" 'detect_display_env'
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
