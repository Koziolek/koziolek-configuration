#!/usr/bin/env bash
# Testy jednostkowe: fix stale-sources (packages/vanilla/fixes.d/005_stale_sources.sh) przez runner
# oraz przez apply_fixes (packages/commons/fixes_apply.sh) — zgoda na FIX_RISK=high jest tam, nie w fixie.
#
# Fix leci w osobnym procesie, więc polecenia są mockami w $_BIN (PATH ograniczony do mocków
# i symlinków do kilku narzędzi). Pliki /etc podmienione na katalogi w $_TMP.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$PROJECT_ROOT/packages/commons/fixes_runner.sh"
APPLY="$PROJECT_ROOT/packages/commons/fixes_apply.sh"

setUp() {
    _TMP="$(mktemp -d)"
    _BIN="$_TMP/bin"
    _LOG="$_TMP/calls.log"
    mkdir -p "$_BIN" "$_TMP/sources" "$_TMP/keyrings"
    : > "$_LOG"
    local t p
    for t in bash awk grep tr head basename dirname mktemp sort cut rm cat id timeout; do
        p="$(builtin command -v "$t" 2>/dev/null)" && [ -n "$p" ] && ln -s "$p" "$_BIN/$t"
    done
    printf '#!%s\necho "APT $*" >> "$STALE_LOG"\n' "$_BIN/bash" > "$_BIN/apt-get"
    chmod +x "$_BIN/apt-get"
    export STALE_LOG="$_LOG" FIX_APT_SOURCES_DIR="$_TMP/sources" FIX_APT_KEYRINGS_DIR="$_TMP/keyrings"
    export FIXES_SUDO='' FIXES_CONTEXT=vanilla
    export FIXES_DIRS="$PROJECT_ROOT/packages/vanilla/fixes.d"
    _mock_docker
}

tearDown() { rm -rf "$_TMP"; }

_mock_docker() { printf '#!%s\n' "$_BIN/bash" > "$_BIN/docker"; chmod +x "$_BIN/docker"; }
_stale() { : > "$_TMP/sources/docker.list"; : > "$_TMP/keyrings/docker.gpg"; }
_run() { PATH="$_BIN" "$_BIN/bash" -c '. "$1"; shift; run_fixes "$@"' _ "$RUNNER" "$@" 2>&1; }
# apply_fixes z odpowiedzią $1 na pytanie o zgodę; helpery ok/warn/info jak w update.sh
_wrap() {
    printf '%s' "$1" | PATH="$_BIN" "$_BIN/bash" -c '
        ok() { echo "OK $*"; }; warn() { echo "WARN $*"; }; info() { echo "INFO $*"; }
        SUDO=""; . "$1"; apply_fixes pre-apt' _ "$APPLY" 2>&1
}

testNoDockerListIsOk() {
    local out
    out="$(_run all --only stale-sources --check --format tsv)"
    assertContains "ok" "$out" "stale-sources	ok"
}

testDockerInstalledMeansOkEvenWithList() {
    _stale
    local out
    out="$(_run all --only stale-sources --check --format tsv)"
    assertContains "ok" "$out" "stale-sources	ok"
    assertTrue "plik zostaje" "[ -f '$_TMP/sources/docker.list' ]"
}

testListWithoutDockerIsDetectedAndCheckTouchesNothing() {
    _stale; rm "$_BIN/docker"
    local out rc=0
    out="$(_run all --only stale-sources --check --format tsv)" || rc=$?
    assertEquals "kod --check" 10 "$rc"
    assertContains "detected" "$out" "stale-sources	detected"
    assertTrue "docker.list nietknięty" "[ -f '$_TMP/sources/docker.list' ]"
    assertTrue "keyring nietknięty" "[ -f '$_TMP/keyrings/docker.gpg' ]"
}

testApplyWithoutAllowHighIsSkipped() {
    _stale; rm "$_BIN/docker"
    local out
    out="$(_run all --only stale-sources --format tsv)"
    assertContains "skipped" "$out" "stale-sources	skipped"
    assertContains "powód" "$out" "--allow-high"
    assertTrue "docker.list nietknięty" "[ -f '$_TMP/sources/docker.list' ]"
}

testApplyWithAllowHighRemovesListAndKeyring() {
    _stale; rm "$_BIN/docker"
    local out
    out="$(_run all --only stale-sources --allow-high --format tsv)"
    assertContains "fixed" "$out" "stale-sources	fixed"
    assertFalse "docker.list usunięty" "[ -e '$_TMP/sources/docker.list' ]"
    assertFalse "keyring usunięty" "[ -e '$_TMP/keyrings/docker.gpg' ]"
    assertContains "apt-get update po usunięciu" "$(cat "$_LOG")" "APT -qq update"
}

testOtherContextIsNotApplicable() {
    _stale; rm "$_BIN/docker"
    local out
    out="$(FIXES_CONTEXT=ubuntu _run all --only stale-sources --check --format tsv)"
    assertNotContains "nie dotyczy ubuntu" "$out" "stale-sources"
}

testApplyFixesNothingToDo() {
    local out
    out="$(_wrap n)"
    assertContains "komunikat" "$out" "OK [stale-sources] w porządku"
}

testApplyFixesRemovesAfterConsent() {
    _stale; rm "$_BIN/docker"
    local out
    out="$(_wrap y)"
    assertContains "ok po usunięciu" "$out" "OK [stale-sources] naprawiono"
    assertFalse "docker.list usunięty" "[ -e '$_TMP/sources/docker.list' ]"
}

testApplyFixesKeepsFilesWithoutConsent() {
    _stale; rm "$_BIN/docker"
    local out
    out="$(_wrap n)"
    assertContains "pominięto" "$out" "INFO [stale-sources] pominięto (brak zgody)"
    assertTrue "docker.list zostaje" "[ -f '$_TMP/sources/docker.list' ]"
}

testApplyFixesDefaultsToNoWithoutInput() {
    _stale; rm "$_BIN/docker"
    local out
    out="$(_wrap '')"
    assertTrue "docker.list zostaje przy EOF" "[ -f '$_TMP/sources/docker.list' ]"
    assertContains "pominięto" "$out" "INFO [stale-sources] pominięto"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
