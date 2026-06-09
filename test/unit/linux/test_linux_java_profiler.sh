#!/usr/bin/env bash
# Linux-specific: async profiler wymaga /proc/sys/kernel — tylko Linux

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
export SUDO=''
export RESET_SUDO=0

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/020_function_process.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/030_function_java.sh"

testAsyncProfilerOnDefinedOnLinux() {
    declare -f turn_async_profiler_on >/dev/null 2>&1
    assertTrue 'turn_async_profiler_on musi być zdefiniowana' $?
}

testAsyncProfilerOffDefinedOnLinux() {
    declare -f turn_async_profiler_off >/dev/null 2>&1
    assertTrue 'turn_async_profiler_off musi być zdefiniowana' $?
}

testAsyncProfilerOnWritesToProc() {
    local body
    body="$(declare -f turn_async_profiler_on)"
    assertContains 'turn_async_profiler_on musi pisać do /proc/sys/kernel' \
        "$body" '/proc/sys/kernel'
}

testAsyncProfilerOnHasDarwinGuard() {
    local body
    body="$(declare -f turn_async_profiler_on)"
    assertContains 'turn_async_profiler_on musi mieć guard Darwin' \
        "$body" 'Darwin'
}

testAsyncProfilerOffHasDarwinGuard() {
    local body
    body="$(declare -f turn_async_profiler_off)"
    assertContains 'turn_async_profiler_off musi mieć guard Darwin' \
        "$body" 'Darwin'
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
