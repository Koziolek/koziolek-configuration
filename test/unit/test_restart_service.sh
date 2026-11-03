#!/usr/bin/env bash
# Testy jednostkowe: restart_service (services/services_functions.sh)
# Mock docker: stan serwisów w plikach $STATE/<serwis> (obecny = działa).

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
    export STATE="$_TEST_DIR/state"
    export CALLS="$_TEST_DIR/calls.log"
    mkdir -p "$STATE" "$_TEST_DIR/bin"
    : >"$CALLS"
    export SERVICES_CONFIGURATION_DIR="$_TEST_DIR/services"
    mkdir -p "$SERVICES_CONFIGURATION_DIR/docker"
    : >"$SERVICES_CONFIGURATION_DIR/docker/docker-compose.yaml"
    export KNOWN_SERVICES="nginx-proxy postgres nexus newone"
    unset DOCKER_COMPOSE STOP_STUCK
    export RESTART_SERVICE_WAIT_INTERVAL=0
    export RESTART_SERVICE_WAIT_RETRIES=3

    cat >"$_TEST_DIR/bin/docker" <<'MOCK'
#!/usr/bin/env bash
args=("$@")
[ "${args[0]}" = compose ] && args=("${args[@]:1}")
[ "${args[0]}" = -f ] && args=("${args[@]:2}")
echo "${args[*]}" >> "$CALLS"
case "${args[0]}" in
config) for s in $KNOWN_SERVICES; do echo "$s"; done ;;
ps) svc="${args[${#args[@]} - 1]}"; [ -e "$STATE/$svc" ] && echo "cid-$svc" ;;
stop) [ -n "$STOP_STUCK" ] || rm -f "$STATE/${args[1]}" ;;
up) touch "$STATE/${args[2]}" ;;
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

testNotRunningStartsWithWarning() {
    local out
    out="$(restart_service nginx-proxy 2>&1)"
    assertEquals 0 $?
    assertContains "$out" "nginx-proxy nie działał"
    assertNotContains "$(cat "$CALLS")" "stop nginx-proxy"
    assertContains "$(cat "$CALLS")" "up -d nginx-proxy"
    assertTrue "[ -e '$STATE/nginx-proxy' ]"
}

testRunningIsStoppedThenStarted() {
    touch "$STATE/postgres"
    local out
    out="$(restart_service postgres 2>&1)"
    assertEquals 0 $?
    assertNotContains "$out" "nie działał"
    assertContains "$out" "Zatrzymuję serwis postgres"
    assertContains "$out" "Serwis postgres uruchomiony"
    local calls
    calls="$(grep -E '^(stop|up)' "$CALLS" | tr '\n' ';')"
    assertEquals "stop postgres;up -d postgres;" "$calls"
}

testStopTimeoutFailsWithoutStart() {
    touch "$STATE/postgres"
    export STOP_STUCK=1
    local out
    out="$(restart_service postgres 2>&1)"
    assertEquals 1 $?
    assertContains "$out" "nie zatrzymał się po 3 próbach"
    assertNotContains "$(cat "$CALLS")" "up -d"
}

testMultipleServicesMixedState() {
    touch "$STATE/nexus"
    local out
    out="$(restart_service nexus postgres 2>&1)"
    assertEquals 0 $?
    assertContains "$out" "postgres nie działał"
    assertNotContains "$out" "nexus nie działał"
    assertContains "$(cat "$CALLS")" "up -d nexus"
    assertContains "$(cat "$CALLS")" "up -d postgres"
}

testUnknownServiceFailsOthersContinue() {
    local out
    out="$(restart_service bogus postgres 2>&1)"
    assertEquals 1 $?
    assertContains "$out" "Nieznany serwis: bogus"
    assertNotContains "$(cat "$CALLS")" "bogus"
    assertContains "$(cat "$CALLS")" "up -d postgres"
}

testNewServiceFromComposeWorksWithoutChanges() {
    restart_service newone >/dev/null 2>&1
    assertEquals 0 $?
    assertTrue "[ -e '$STATE/newone' ]"
}

testNoArgsIsUsageError() {
    local out
    out="$(restart_service 2>&1)"
    assertEquals 1 $?
    assertContains "$out" "Użycie: restart_service"
}

testMissingComposeFile() {
    rm "$SERVICES_CONFIGURATION_DIR/docker/docker-compose.yaml"
    local out
    out="$(restart_service postgres 2>&1)"
    assertEquals 1 $?
    assertContains "$out" "Brak pliku docker-compose"
}

testCustomComposeCommandIsUsed() {
    cat >"$_TEST_DIR/bin/podman-compose" <<'MOCK'
#!/usr/bin/env bash
echo "PC $*" >> "$CALLS"
[ "$3" = config ] && echo postgres
exit 0
MOCK
    chmod +x "$_TEST_DIR/bin/podman-compose"
    DOCKER_COMPOSE=podman-compose restart_service postgres >/dev/null 2>&1
    assertContains "$(cat "$CALLS")" "PC -f"
    assertContains "$(cat "$CALLS")" "up -d postgres"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
