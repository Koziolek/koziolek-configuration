#!/usr/bin/env bash
# macOS-specific: funkcje process na Darwin muszą zwracać błąd z komunikatem

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
export WORKSPACE_TOOLS="${WORKSPACE_TOOLS:-/tmp/fake_ws_$$}"

_run_with_darwin_uname() {
    bash --norc --noprofile -c "
        uname() { echo 'Darwin'; }
        export -f uname
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/functions.d/020_function_process.sh' 2>/dev/null
        $1
        exit \$?
    " 2>&1
}

testReswapFailsOnDarwin() {
    local rc
    _run_with_darwin_uname 'reswap' >/dev/null
    rc=$?
    assertNotEquals 'reswap musi zwrócić błąd na Darwin' 0 $rc
}

testWhoUseSwapFailsOnDarwin() {
    local rc
    _run_with_darwin_uname 'who_use_swap' >/dev/null
    rc=$?
    assertNotEquals 'who_use_swap musi zwrócić błąd na Darwin' 0 $rc
}

testReswapPrintsWarningOnDarwin() {
    local out
    out="$(_run_with_darwin_uname 'reswap' 2>&1)"
    assertContains 'reswap musi wypisać ostrzeżenie na Darwin' "$out" 'macOS'
}

testWhoUseSwapPrintsWarningOnDarwin() {
    local out
    out="$(_run_with_darwin_uname 'who_use_swap' 2>&1)"
    assertContains 'who_use_swap musi wypisać ostrzeżenie na Darwin' "$out" 'macOS'
}

testWhoUsePortUsesLsofOnDarwin() {
    local body
    body="$(bash --norc --noprofile -c "
        uname() { echo 'Darwin'; }
        export -f uname
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/functions.d/020_function_process.sh' 2>/dev/null
        declare -f who_use_port
    " 2>/dev/null)"
    assertContains 'who_use_port na Darwin musi używać lsof' "$body" 'lsof'
}

testAsyncProfilerOnFailsOnDarwin() {
    local rc
    bash --norc --noprofile -c "
        uname() { echo 'Darwin'; }
        export -f uname
        SUDO=''
        RESET_SUDO=0
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/functions.d/020_function_process.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/functions.d/030_function_java.sh' 2>/dev/null
        turn_async_profiler_on
    " >/dev/null 2>&1
    rc=$?
    assertNotEquals 'turn_async_profiler_on musi zwrócić błąd na Darwin' 0 $rc
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
