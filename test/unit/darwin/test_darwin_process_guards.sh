#!/usr/bin/env bash
# macOS-specific: funkcje process na Darwin muszą zwracać błąd z komunikatem.
# Guard nie jest już w functions.d/ — bash/contexts/darwin.sh cieniuje funkcje.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
export WORKSPACE_TOOLS="${WORKSPACE_TOOLS:-/tmp/fake_ws_$$}"

# functions.d/ (wersja Linux) + contexts/darwin.sh (cieniowanie) — tak jak przy
# realnym starcie powłoki na macOS.
_run_with_darwin_uname() {
    bash --norc --noprofile -c "
        uname() { echo 'Darwin'; }; export -f uname
        hub() { :; }; export -f hub   # nie instaluj huba przez brew podczas testów
        SUDO=''; RESET_SUDO=0
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/functions.d/020_function_process.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/functions.d/030_function_java.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/functions.d/096_apt_gpg.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/contexts/darwin.sh' 2>/dev/null
        $1
        exit \$?
    " 2>&1
}

testReswapFailsOnDarwin() {
    _run_with_darwin_uname 'reswap' >/dev/null
    assertNotEquals 'reswap musi zwrócić błąd na Darwin' 0 $?
}

testWhoUseSwapFailsOnDarwin() {
    _run_with_darwin_uname 'who_use_swap' >/dev/null
    assertNotEquals 'who_use_swap musi zwrócić błąd na Darwin' 0 $?
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

testListeningSocketPairsUsesLsofOnDarwin() {
    local body
    body="$(_run_with_darwin_uname 'declare -f _listening_socket_pairs')"
    assertContains '_listening_socket_pairs na Darwin musi używać lsof' "$body" 'lsof'
}

testAsyncProfilerOnFailsOnDarwin() {
    _run_with_darwin_uname 'turn_async_profiler_on' >/dev/null
    assertNotEquals 'turn_async_profiler_on musi zwrócić błąd na Darwin' 0 $?
}

testAsyncProfilerOnPrintsWarningOnDarwin() {
    local out
    out="$(_run_with_darwin_uname 'turn_async_profiler_on' 2>&1)"
    assertContains 'turn_async_profiler_on musi wypisać ostrzeżenie na Darwin' "$out" 'macOS'
}

testRefreshAptGpgKeysFailsOnDarwin() {
    _run_with_darwin_uname 'refresh_apt_gpg_keys' >/dev/null
    assertNotEquals 'refresh_apt_gpg_keys musi zwrócić błąd na Darwin' 0 $?
}

testRefreshAptGpgKeysPrintsWarningOnDarwin() {
    local out
    out="$(_run_with_darwin_uname 'refresh_apt_gpg_keys' 2>&1)"
    assertContains 'refresh_apt_gpg_keys musi wypisać ostrzeżenie na Darwin' "$out" 'macOS'
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
