#!/usr/bin/env bash
# Linux-specific: funkcje procesów zależne od Linux syscalls (/proc, ss, swapoff)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
export WORKSPACE_TOOLS="${WORKSPACE_TOOLS:-/tmp/fake_ws_$$}"

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/020_function_process.sh"

testReswapDefinedOnLinux() {
    declare -f reswap >/dev/null 2>&1
    assertTrue 'reswap musi być zdefiniowana na Linux' $?
}

testWhoUseSwapDefinedOnLinux() {
    declare -f who_use_swap >/dev/null 2>&1
    assertTrue 'who_use_swap musi być zdefiniowana na Linux' $?
}

testWhoUsePortUsesSSOnLinux() {
    local body
    body="$(declare -f who_use_port)"
    assertContains 'who_use_port na Linux musi używać ss -tulpn' \
        "$body" 'ss -tulpn'
}

testWhoUsePortHasBothSSAndLsofBranches() {
    # Funkcja ma if/else: ss dla Linux, lsof dla Darwin — oba muszą być w ciele
    local body
    body="$(declare -f who_use_port)"
    assertContains 'who_use_port musi mieć gałąź ss (Linux)' "$body" 'ss -tulpn'
    assertContains 'who_use_port musi mieć gałąź lsof (Darwin)' "$body" 'lsof'
}

testExterminatusWithNoMatchReturns0() {
    # pgrep zwraca brak wyników → xargs nie dostaje nic → exit 0
    exterminatus "nonexistent_process_$$_xyz_test" 2>/dev/null
    assertEquals 'exterminatus bez pasujących procesów musi zwrócić 0' 0 $?
}

testExterminatusBodyHasNoXargsR() {
    # xargs -r to rozszerzenie GNU nieobecne na macOS — sprawdzamy że nie ma go w kodzie
    local body
    body="$(declare -f exterminatus)"
    assertNotContains 'exterminatus nie może używać xargs -r (GNU-only)' \
        "$body" 'xargs -r'
}

testReswapBodyContainsSwapoff() {
    local body
    body="$(declare -f reswap)"
    assertContains 'reswap musi wywoływać swapoff' "$body" 'swapoff'
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
