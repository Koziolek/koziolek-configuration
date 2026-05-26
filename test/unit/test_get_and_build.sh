#!/usr/bin/env bash
# Testy jednostkowe: get_and_build (bash/functions.d/100_get_and_build.sh)
# Używa --skip-pull i --dry-run żeby uniknąć faktycznego git pull i budowania.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/100_get_and_build.sh"

_WORK_DIR=''
_GIT_LOG=''

oneTimeSetUp() {
    _GIT_LOG="$(mktemp)"
}

oneTimeTearDown() {
    rm -f "$_GIT_LOG"
}

setUp() {
    _WORK_DIR="$(mktemp -d)"
    : > "$_GIT_LOG"
    git() { echo "GIT $*" >> "$_GIT_LOG"; return 0; }
}

tearDown() {
    rm -rf "$_WORK_DIR"
    unset -f git 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Detekcja systemów budowania (--skip-pull --dry-run)
# ---------------------------------------------------------------------------

testDetectsMaven() {
    touch "$_WORK_DIR/pom.xml"
    local output
    output="$(get_and_build -s -d "$_WORK_DIR" 2>&1)"
    assertContains 'maven musi być wykryty przez pom.xml' "$output" 'maven'
}

testDetectsGradle() {
    touch "$_WORK_DIR/build.gradle"
    local output
    output="$(get_and_build -s -d "$_WORK_DIR" 2>&1)"
    assertContains 'gradle musi być wykryty przez build.gradle' "$output" 'gradle'
}

testDetectsMix() {
    touch "$_WORK_DIR/mix.exs"
    local output
    output="$(get_and_build -s -d "$_WORK_DIR" 2>&1)"
    assertContains 'mix musi być wykryty przez mix.exs' "$output" 'mix'
}

testDetectsNpm() {
    touch "$_WORK_DIR/package.json"
    local output
    output="$(get_and_build -s -d "$_WORK_DIR" 2>&1)"
    assertContains 'npm musi być wykryty przez package.json' "$output" 'npm'
}

testDetectsCargo() {
    touch "$_WORK_DIR/Cargo.toml"
    local output
    output="$(get_and_build -s -d "$_WORK_DIR" 2>&1)"
    assertContains 'cargo musi być wykryty przez Cargo.toml' "$output" 'cargo'
}

testMavenWinsOverGradle() {
    # 10-maven.sh ładowany przed 20-gradle.sh — pierwsze dopasowanie wygrywa
    touch "$_WORK_DIR/pom.xml" "$_WORK_DIR/build.gradle"
    local output
    output="$(get_and_build -s -d "$_WORK_DIR" 2>&1)"
    assertContains 'maven musi wygrać z gradle (niższy numer pluginu)' "$output" 'maven'
    local gradle_detected=false
    echo "$output" | grep -q 'Wykryto.*gradle' && gradle_detected=true || true
    assertFalse 'gradle nie powinien być wykryty gdy jest też pom.xml' "$gradle_detected"
}

# ---------------------------------------------------------------------------
# Flagi
# ---------------------------------------------------------------------------

testDryRunDoesNotBuild() {
    touch "$_WORK_DIR/pom.xml"
    local output rc
    output="$(get_and_build -s -d "$_WORK_DIR" 2>&1)"
    rc=$?
    assertEquals 'dry-run musi zwrócić 0' 0 "$rc"
    assertContains 'output musi zawierać informację o dry-run' "$output" 'dry-run'
    local mvn_ran=false
    echo "$output" | grep -qi 'clean verify' && mvn_ran=true || true
    assertFalse 'komenda mvn nie powinna zostać uruchomiona' "$mvn_ran"
}

testSkipPullSkipsGit() {
    touch "$_WORK_DIR/pom.xml"
    get_and_build -s -d "$_WORK_DIR" >/dev/null 2>&1
    assertFalse 'git nie powinien być wołany gdy użyto -s' '[ -s "$_GIT_LOG" ]'
}

testListShowsAllPlugins() {
    local output
    output="$(get_and_build -l 2>&1)"
    assertContains 'lista pluginów musi zawierać maven'  "$output" 'maven'
    assertContains 'lista pluginów musi zawierać gradle' "$output" 'gradle'
    assertContains 'lista pluginów musi zawierać mix'    "$output" 'mix'
    assertContains 'lista pluginów musi zawierać npm'    "$output" 'npm'
    assertContains 'lista pluginów musi zawierać cargo'  "$output" 'cargo'
}

testUnknownBuildSystemReturnsError() {
    # Pusty katalog — żaden plugin nie pasuje
    local rc=0
    get_and_build -s "$_WORK_DIR" >/dev/null 2>&1 || rc=$?
    assertNotEquals 'brak pliku build musi zwrócić kod błędu' 0 "$rc"
}

testCustomPluginDirIsUsed() {
    local custom_dir
    custom_dir="$(mktemp -d)"
    cat > "$custom_dir/10-sbt.sh" <<'EOF'
PLUGIN_NAME="sbt"
PLUGIN_DETECT="build.sbt"
PLUGIN_CMD="sbt clean test"
EOF
    touch "$_WORK_DIR/build.sbt"
    local output
    output="$(get_and_build -s -d "$_WORK_DIR" -p "$custom_dir" 2>&1)"
    assertContains 'niestandardowy katalog pluginów musi być użyty' "$output" 'sbt'
    rm -rf "$custom_dir"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
