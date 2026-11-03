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
    unset -f sleep
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

testWrapperSplitsMultiWordComposeCommand() {
    cat >"$_TEST_DIR/bin/mycompose" <<'MOCK'
#!/usr/bin/env bash
echo "MC $*" >> "$CALLS"
for a in "$@"; do [ "$a" = config ] && echo postgres; done
exit 0
MOCK
    chmod +x "$_TEST_DIR/bin/mycompose"
    DOCKER_COMPOSE="mycompose --ansi never" restart_service postgres >/dev/null 2>&1
    assertContains "$(cat "$CALLS")" "MC --ansi never -f"
    assertContains "$(cat "$CALLS")" "up -d postgres"
}

testEmptyComposeVariableFallsBackToDockerCompose() {
    DOCKER_COMPOSE='' restart_service postgres >/dev/null 2>&1
    assertContains "$(cat "$CALLS")" "up -d postgres"
}

testWrapperDoesNotGlobExpandComposeVariable() {
    cat >"$_TEST_DIR/bin/echoer" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$CALLS"
MOCK
    chmod +x "$_TEST_DIR/bin/echoer"
    touch "$_TEST_DIR/bin/globbed"
    (cd "$_TEST_DIR/bin" && DOCKER_COMPOSE='echoer *' _services_compose x)
    assertContains "$(cat "$CALLS")" "* x"
}

testNoShellcheckSC2086DirectiveInServicesFunctions() {
    assertFalse "dyrektywa SC2086 wróciła" \
        "grep -q 'shellcheck disable=SC2086' '$PROJECT_ROOT/services/services_functions.sh'"
}

# --- pętla oczekiwania (#187): liczba sprawdzeń = RETRIES, snów = RETRIES-1 ---
# Mock `sleep` zlicza wywołania; STOP_AFTER_PS=N: serwis znika dopiero po N-tym `ps`.
_install_counting_sleep() {
    export SLEEPS="$_TEST_DIR/sleeps"
    : >"$SLEEPS"
    sleep() { echo "$1" >>"$SLEEPS"; }
}

_count_sleeps() { wc -l <"$SLEEPS" | tr -d ' '; }
_count_ps() { grep -c '^ps ' "$CALLS"; }

_install_slow_stop_docker() {
    # stop nie usuwa stanu; ps „widzi" serwis przez STOP_AFTER_PS wywołań, potem znika
    cat >"$_TEST_DIR/bin/docker" <<'MOCK'
#!/usr/bin/env bash
args=("$@")
[ "${args[0]}" = compose ] && args=("${args[@]:1}")
[ "${args[0]}" = -f ] && args=("${args[@]:2}")
echo "${args[*]}" >> "$CALLS"
case "${args[0]}" in
config) for s in $KNOWN_SERVICES; do echo "$s"; done ;;
ps)
    svc="${args[${#args[@]} - 1]}"
    if [ -e "$STATE/$svc" ]; then
        n=$(( $(cat "$STATE/$svc.ps" 2>/dev/null || echo 0) + 1 ))
        echo "$n" >"$STATE/$svc.ps"
        if [ -e "$STATE/$svc.stopped" ] && [ "$n" -gt "$STOP_AFTER_PS" ]; then
            rm -f "$STATE/$svc"
        else
            echo "cid-$svc"
        fi
    fi ;;
stop) touch "$STATE/${args[1]}.stopped"; : >"$STATE/${args[1]}.ps" ;;
up) touch "$STATE/${args[2]}"; rm -f "$STATE/${args[2]}.stopped" ;;
esac
exit 0
MOCK
}

testWaitStoppedImmediatelyNoSleep() {
    _install_counting_sleep
    touch "$STATE/postgres"
    restart_service postgres >/dev/null 2>&1
    assertEquals 0 $?
    assertEquals 0 "$(_count_sleeps)"
}

testWaitStoppedAfterTwoPollsOneSleep() {
    _install_counting_sleep
    _install_slow_stop_docker
    export STOP_AFTER_PS=1
    touch "$STATE/postgres"
    restart_service postgres >/dev/null 2>&1
    assertEquals 0 $?
    assertEquals 1 "$(_count_sleeps)"
}

testWaitStuckSleepsRetriesMinusOneAndTimesOut() {
    _install_counting_sleep
    export STOP_STUCK=1
    touch "$STATE/postgres"
    local out
    out="$(restart_service postgres 2>&1)"
    assertEquals 1 $?
    assertContains "$out" "nie zatrzymał się po 3 próbach"
    assertEquals 2 "$(_count_sleeps)"
}

testWaitStuckPollsExactlyRetriesTimes() {
    _install_counting_sleep
    export STOP_STUCK=1
    touch "$STATE/postgres"
    : >"$CALLS"
    restart_service postgres >/dev/null 2>&1
    # 1 ps na decyzję „czy działa" + RETRIES (=3) w pętli, bez dodatkowego po pętli
    assertEquals 4 "$(_count_ps)"
}

testWaitRetriesOneNoSleepAndError() {
    _install_counting_sleep
    export STOP_STUCK=1 RESTART_SERVICE_WAIT_RETRIES=1
    touch "$STATE/postgres"
    restart_service postgres >/dev/null 2>&1
    assertEquals 1 $?
    assertEquals 0 "$(_count_sleeps)"
}

testWaitInvalidRetriesWarnsAndUsesDefault() {
    _install_counting_sleep
    export STOP_STUCK=1 RESTART_SERVICE_WAIT_RETRIES=abc
    touch "$STATE/postgres"
    local out
    out="$(restart_service postgres 2>&1)"
    assertContains "$out" "Nieprawidłowe RESTART_SERVICE_WAIT_RETRIES (abc) - używam 60"
    assertContains "$out" "nie zatrzymał się po 60 próbach"
}

testWaitZeroRetriesIsInvalid() {
    _install_counting_sleep
    export RESTART_SERVICE_WAIT_RETRIES=0
    touch "$STATE/postgres"
    local out
    out="$(restart_service postgres 2>&1)"
    assertEquals 0 $?
    assertContains "$out" "Nieprawidłowe RESTART_SERVICE_WAIT_RETRIES (0)"
}

testWaitInvalidIntervalWarnsAndUsesDefault() {
    _install_counting_sleep
    export RESTART_SERVICE_WAIT_INTERVAL=-5
    touch "$STATE/postgres"
    local out
    out="$(restart_service postgres 2>&1)"
    assertContains "$out" "Nieprawidłowe RESTART_SERVICE_WAIT_INTERVAL (-5) - używam 1"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
