#!/usr/bin/env bash
# macOS-specific: resize_to_full musi być no-op (return 0) gdy uname zwraca Darwin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/000_functions_startup.sh"

testResizeToFullReturns0WhenDarwin() {
    local rc
    # Mock uname — działa w subshell z wyeksportowaną funkcją
    bash --norc --noprofile -c "
        uname() { echo 'Darwin'; }
        export -f uname
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/functions.d/000_functions_startup.sh' 2>/dev/null
        resize_to_full 2>/dev/null
        exit \$?
    "
    rc=$?
    assertEquals 'resize_to_full musi zwrócić 0 gdy uname=Darwin' 0 $rc
}

testResizeToFullProducesNoOutputWhenDarwin() {
    local out
    out="$(bash --norc --noprofile -c "
        uname() { echo 'Darwin'; }
        export -f uname
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/functions.d/000_functions_startup.sh' 2>/dev/null
        resize_to_full
    " 2>&1)"
    assertEquals 'resize_to_full musi być cicha na Darwin' '' "$out"
}

testResizeToFullHasDarwinGuard() {
    local body
    body="$(declare -f resize_to_full)"
    assertContains 'resize_to_full musi mieć guard Darwin' "$body" 'Darwin'
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
