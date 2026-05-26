#!/usr/bin/env bash
# Testy integracyjne: bash/bash_exports.sh
# Każdy test sourcuje bash_exports.sh w izolowanym subshell z podstawionym $HOME.
# Stdout z bash_exports.sh jest wyciszony — sprawdzamy tylko wartość zmiennej.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"

_FAKE_HOME=''

oneTimeSetUp() {
    _FAKE_HOME="$(mktemp -d)"
}

oneTimeTearDown() {
    rm -rf "$_FAKE_HOME"
}

setUp() {
    # Pre-tworzenie .senv eliminuje efekt uboczny tworzenia go podczas testów
    touch "$_FAKE_HOME/.senv"
    chmod 400 "$_FAKE_HOME/.senv" 2>/dev/null || true
    rm -rf "$_FAKE_HOME/.sdkman"
}

# Sourcuje bash_exports.sh w subshell. Stdout bash_exports.sh jest wyciszony.
# $1 — nazwa zmiennej do wypisania
# $2 — opcjonalny preambuła (kod bash do wykonania przed sourcowaniem)
_get_export() {
    local varname="$1"
    local preamble="${2:-}"
    HOME="$_FAKE_HOME" bash -c "
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        $preamble
        { . '$PROJECT_ROOT/bash/bash_exports.sh'; } >/dev/null 2>&1
        printf '%s' \"\${$varname}\"
    "
}

# Preambuła: mock docker jako funkcja — command -v docker zwróci 0
_WITH_DOCKER='docker() { return 0; }; export -f docker'

# ---------------------------------------------------------------------------

testWorkspaceSetToHomeWorkspace() {
    local result
    result="$(_get_export 'WORKSPACE' "$_WITH_DOCKER")"
    assertEquals 'WORKSPACE musi wskazywać na $HOME/workspace' \
        "$_FAKE_HOME/workspace" "$result"
}

testWorkspaceToolsUnderWorkspace() {
    local result
    result="$(_get_export 'WORKSPACE_TOOLS' "$_WITH_DOCKER")"
    assertEquals 'WORKSPACE_TOOLS musi być podkatalogiem WORKSPACE' \
        "$_FAKE_HOME/workspace/tools" "$result"
}

testDockerComposeSetWhenDockerPresent() {
    local result
    result="$(_get_export 'DOCKER_COMPOSE' "$_WITH_DOCKER")"
    assertEquals 'DOCKER_COMPOSE musi być "docker compose" gdy docker dostępny' \
        'docker compose' "$result"
}

testDockerComposeEmptyWhenDockerAbsent() {
    # Izolujemy PATH do katalogu z samym chmod (docker nie jest dostępny)
    local fake_bin result
    fake_bin="$(mktemp -d)"
    cp /usr/bin/chmod "$fake_bin/"

    result="$(HOME="$_FAKE_HOME" bash -c "
        export PATH='$fake_bin'
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        { . '$PROJECT_ROOT/bash/bash_exports.sh'; } >/dev/null 2>&1
        printf '%s' \"\${DOCKER_COMPOSE}\"
    ")"
    rm -rf "$fake_bin"
    assertEquals 'DOCKER_COMPOSE musi być pusty gdy docker niedostępny' '' "$result"
}

testClaudeSkillConfigExported() {
    local result
    result="$(_get_export 'CLAUDE_SKILL_CONFIG' "$_WITH_DOCKER")"
    assertNotNull 'CLAUDE_SKILL_CONFIG musi być ustawione' "$result"
}

testSdkmanDirPointsToHomeSdkman() {
    local result
    result="$(_get_export 'SDKMAN_DIR' "$_WITH_DOCKER")"
    assertEquals 'SDKMAN_DIR musi wskazywać na $HOME/.sdkman' \
        "$_FAKE_HOME/.sdkman" "$result"
}

testPathIncludesSdkmanCandidateBinsWhenPresent() {
    local fake_java_bin="$_FAKE_HOME/.sdkman/candidates/java/current/bin"
    mkdir -p "$fake_java_bin"
    local result
    result="$(HOME="$_FAKE_HOME" bash -c "
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        $_WITH_DOCKER
        { . '$PROJECT_ROOT/bash/bash_exports.sh'; } >/dev/null 2>&1
        printf '%s' \"\$PATH\"
    ")"
    assertContains 'PATH musi zawierać katalog bin java z SDKMAN' "$result" "$fake_java_bin"
}

testJavaHomeSetWhenSdkmanJavaPresent() {
    local fake_java="$_FAKE_HOME/.sdkman/candidates/java/current"
    mkdir -p "$fake_java/bin"
    local result
    result="$(HOME="$_FAKE_HOME" bash -c "
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        $_WITH_DOCKER
        { . '$PROJECT_ROOT/bash/bash_exports.sh'; } >/dev/null 2>&1
        printf '%s' \"\$JAVA_HOME\"
    ")"
    assertEquals 'JAVA_HOME musi wskazywać na aktualne SDKMAN java' "$fake_java" "$result"
}

testSenvCreatedWhenAbsent() {
    rm -f "$_FAKE_HOME/.senv"
    HOME="$_FAKE_HOME" bash -c "
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        $_WITH_DOCKER
        { . '$PROJECT_ROOT/bash/bash_exports.sh'; } >/dev/null 2>&1
    "
    assertTrue '.senv musi zostać stworzony gdy nie istnieje' \
        '[ -f "$_FAKE_HOME/.senv" ]'
}

testSenvPermissionsAreUserReadOnly() {
    rm -f "$_FAKE_HOME/.senv"
    HOME="$_FAKE_HOME" bash -c "
        export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
        export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
        . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh' 2>/dev/null
        $_WITH_DOCKER
        { . '$PROJECT_ROOT/bash/bash_exports.sh'; } >/dev/null 2>&1
    "
    local perms
    perms="$(stat -c '%a' "$_FAKE_HOME/.senv" 2>/dev/null || echo 'missing')"
    assertEquals '.senv musi mieć uprawnienia 400' '400' "$perms"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
