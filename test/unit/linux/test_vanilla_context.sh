#!/usr/bin/env bash
# Kontekst vanilla: nadpisania zmiennych (DOCKER_CLI/DOCKER_COMPOSE/DOCKER_HOST).
# Ładowany po bash_exports.sh — musi przebić neutralny probe.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

_VANILLA="$PROJECT_ROOT/bash/contexts/vanilla.sh"

# $1 = zmienna do wypisania; $2 = mocki narzędzi (kod bash)
_get_vanilla_var() {
    bash --norc --noprofile -c "
        export HOME='$(mktemp -d)'
        $2
        { . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh'; } 2>/dev/null
        { . '$PROJECT_ROOT/bash/bash_exports.sh'; } >/dev/null 2>&1
        { . '$_VANILLA'; } >/dev/null 2>&1
        printf '%s' \"\${$1:-}\"
    "
}

testDockerCliIsPodman() {
    local out
    out="$(_get_vanilla_var DOCKER_CLI 'docker() { return 0; }; export -f docker')"
    assertEquals 'vanilla: DOCKER_CLI=podman nawet gdy docker widoczny' 'podman' "$out"
}

testDockerComposeIsPodmanComposeWhenPresent() {
    local out
    out="$(_get_vanilla_var DOCKER_COMPOSE 'podman-compose() { :; }; export -f podman-compose')"
    assertEquals 'vanilla: DOCKER_COMPOSE=podman-compose' 'podman-compose' "$out"
}

testFunctionsUseDockerCliIndirection() {
    local body
    body="$(bash --norc --noprofile -c "
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        . '$PROJECT_ROOT/bash/functions.d/040_function_docker.sh' 2>/dev/null
        declare -f check_container_status
    ")"
    assertContains 'check_container_status musi używać ${DOCKER_CLI:-docker}' \
        "$body" 'DOCKER_CLI:-docker'
    assertNotContains 'brak gołego `docker inspect`' "$body" 'docker inspect'
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
