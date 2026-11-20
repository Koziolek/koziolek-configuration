#!/usr/bin/env bash
# Testy jednostkowe: rebuild_container (services/services_functions.sh)
# Mock docker: `build` zawodzi dla serwisów z $BUILD_FAIL; wywołania zapisane w $CALLS.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export MESSAGES_LANG=pl
export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/005_function_messages.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/services/services_functions.sh"

_TEST_DIR=''
_ORIG_PATH=''

setUp() {
    _TEST_DIR="$(mktemp -d)"
    _ORIG_PATH="$PATH"
    export CALLS="$_TEST_DIR/calls.log"
    mkdir -p "$_TEST_DIR/bin"
    : >"$CALLS"
    export SERVICES_CONFIGURATION_DIR="$_TEST_DIR/services"
    mkdir -p "$SERVICES_CONFIGURATION_DIR/docker"
    : >"$SERVICES_CONFIGURATION_DIR/docker/docker-compose.yaml"
    export KNOWN_SERVICES="jenkins forgejo nginx-proxy"
    unset DOCKER_COMPOSE BUILD_FAIL UP_FAIL REBUILD_CONTAINER_TAIL_LINES

    cat >"$_TEST_DIR/bin/docker" <<'MOCK'
#!/usr/bin/env bash
args=("$@")
[ "${args[0]}" = compose ] && args=("${args[@]:1}")
[ "${args[0]}" = -f ] && args=("${args[@]:2}")
echo "${args[*]}" >> "$CALLS"
case "${args[0]}" in
config) for s in $KNOWN_SERVICES; do echo "$s"; done ;;
build)
    echo "Step 1/1 : budowanie ${args[1]}"
    for s in $BUILD_FAIL; do
        if [ "$s" = "${args[1]}" ]; then
            echo "E: Unable to locate package nieistniejacy" >&2
            exit 3
        fi
    done ;;
up) [ -n "$UP_FAIL" ] && exit 1 ;;
esac
exit 0
MOCK
    chmod +x "$_TEST_DIR/bin/docker"
    export PATH="$_TEST_DIR/bin:$PATH"
}

tearDown() {
    export PATH="$_ORIG_PATH"
    rm -rf "$_TEST_DIR"
}

testBuildSuccessRunsBuildThenUp() {
    local out
    out="$(rebuild_container jenkins 2>&1)"
    assertEquals 0 $?
    assertEquals "build, potem up -d" "build jenkins
up -d jenkins" "$(grep -v '^config' "$CALLS")"
    assertContains "$out" "Serwis jenkins przebudowany i uruchomiony"
}

testBuildFailureDoesNotRunUpAndReportsWhatFailed() {
    local out
    export BUILD_FAIL="jenkins"
    out="$(rebuild_container jenkins 2>&1)"
    assertEquals 1 $?
    assertNotContains "up nie może lecieć po nieudanym buildzie" "$(cat "$CALLS")" "up -d"
    assertContains "$out" "Build serwisu jenkins nie powiódł się (kod 3)"
    assertContains "ostatnie linie wyjścia buildu" "$out" "E: Unable to locate package nieistniejacy"
}

testFailureTailIsLimited() {
    local out
    export BUILD_FAIL="jenkins" REBUILD_CONTAINER_TAIL_LINES=1
    out="$(rebuild_container jenkins 2>&1 | sed -n '/Ostatnie linie/,$p')"
    assertContains "$out" "E: Unable to locate package"
    assertNotContains "tylko ostatnia linia" "$out" "Step 1/1"
}

testFailedServiceDoesNotStopOthers() {
    local out
    export BUILD_FAIL="jenkins"
    out="$(rebuild_container jenkins forgejo 2>&1)"
    assertEquals 1 $?
    assertContains "$(cat "$CALLS")" "up -d forgejo"
    assertNotContains "$(cat "$CALLS")" "up -d jenkins"
}

testUnknownServiceFailsWithoutBuilding() {
    local out
    out="$(rebuild_container bogus 2>&1)"
    assertEquals 1 $?
    assertContains "$out" "Nieznany serwis: bogus"
    assertNotContains "$(cat "$CALLS")" "build"
}

testUpFailureReturnsError() {
    local out
    export UP_FAIL=1
    out="$(rebuild_container jenkins 2>&1)"
    assertEquals 1 $?
    assertContains "$out" "Nie udało się uruchomić serwisu jenkins"
}

testNoArgsPrintsUsage() {
    local out
    out="$(rebuild_container 2>&1)"
    assertEquals 1 $?
    assertContains "$out" "Użycie: rebuild_container <serwis>..."
}

testMissingComposeFile() {
    local out
    rm -f "$SERVICES_CONFIGURATION_DIR/docker/docker-compose.yaml"
    out="$(rebuild_container jenkins 2>&1)"
    assertEquals 1 $?
    assertContains "$out" "Brak pliku docker-compose"
}

testRebuildContainerIsExported() {
    assertTrue "export -f" "bash -c 'declare -F rebuild_container >/dev/null' 2>/dev/null || declare -F rebuild_container >/dev/null"
    assertContains "$(declare -f rebuild_container)" "PIPESTATUS"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
