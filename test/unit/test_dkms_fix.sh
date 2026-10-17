#!/usr/bin/env bash
# Testy jednostkowe: fix dkms (packages/commons/fixes.d/010_dkms.sh) uruchamiany przez runner
# oraz przez apply_fixes (packages/commons/fixes_apply.sh) — tak wołają go {ubuntu,vanilla}/update.sh.
#
# Fix leci w osobnym procesie bash, więc polecenia systemowe są mockami w $_BIN (PATH ograniczony
# do mocków i kilku narzędzi z symlinków) — dzięki temu obecność/brak `dkms` jest deterministyczna.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$PROJECT_ROOT/packages/commons/fixes_runner.sh"
APPLY="$PROJECT_ROOT/packages/commons/fixes_apply.sh"

setUp() {
    _TMP="$(mktemp -d)"
    _BIN="$_TMP/bin"
    _LOG="$_TMP/calls.log"
    mkdir -p "$_BIN"
    : > "$_LOG"
    local t p
    for t in bash awk grep tr head basename dirname mktemp sort cut rm cat id timeout; do
        p="$(builtin command -v "$t" 2>/dev/null)" && [ -n "$p" ] && ln -s "$p" "$_BIN/$t"
    done
    export DKMS_LOG="$_LOG" DKMS_QUERY_OUT='' DKMS_CONFIGURE_RC=0
    # po udanym configure pakiet przestaje być uszkodzony (mock dpkg-query czyta plik stanu)
    export DKMS_STATE="$_TMP/state"
    _mock dpkg-query 'cat "$DKMS_STATE" 2>/dev/null'
    _mock dpkg 'case "$1" in
        -L) echo "/usr/src/v4l2loopback-0.12.7"; echo "/usr/src/v4l2loopback-0.12.7/Makefile"; echo "/usr/share/doc/x" ;;
        --configure) echo "DPKG --configure $2" >> "$DKMS_LOG"
            [ "$DKMS_CONFIGURE_RC" = 0 ] && : > "$DKMS_STATE"; exit "$DKMS_CONFIGURE_RC" ;;
        esac'
    _mock dkms 'echo "DKMS $*" >> "$DKMS_LOG"'
    export FIXES_SUDO='' FIXES_CONTEXT=debian
}

tearDown() {
    rm -rf "$_TMP"
}

_mock() { printf '#!%s\n%s\n' "$_BIN/bash" "$2" > "$_BIN/$1"; chmod +x "$_BIN/$1"; }
_state() { printf '%s' "$1" > "$DKMS_STATE"; }
# PATH ograniczony do mocków tylko dla procesu pod testem (sam shunit2 potrzebuje pełnego PATH).
_run() { PATH="$_BIN" "$_BIN/bash" -c '. "$1"; shift; run_fixes "$@"' _ "$RUNNER" "$@" 2>&1; }
_wrap() { PATH="$_BIN" "$_BIN/bash" -c 'ok() { echo "OK $*"; }; warn() { echo "WARN $*"; }; info() { echo "INFO $*"; }; SUDO="${2-}"; . "$1"; apply_fixes "${3:-pre-apt}"' _ "$APPLY" "$@" 2>&1; }
_calls() { cat "$_LOG"; }

testHealthyPackagesAreOk() {
    _state $'ii  v4l2loopback-dkms\nii  openrazer-driver-dkms\n'
    local out rc=0
    out="$(_run all --only dkms --check --format tsv)" || rc=$?
    assertEquals "kod --check" 0 "$rc"
    assertContains "stan ok" "$out" "dkms	ok"
    assertEquals "brak wywołań" "" "$(_calls)"
}

testNoDkmsIsNotApplicable() {
    rm "$_BIN/dkms"
    _state $'iF  v4l2loopback-dkms\n'
    local out rc=0
    out="$(_run all --only dkms --check --format tsv)" || rc=$?
    assertEquals "kod --check" 0 "$rc"
    assertContains "stan na" "$out" "dkms	na"
}

testRemovedPackagesAreNotBroken() {
    _state $'rc  old-dkms\nun  gone-dkms\n'
    local out
    out="$(_run all --only dkms --check --format tsv)"
    assertContains "rc/un to nie uszkodzenie" "$out" "dkms	ok"
}

testCheckDetectsBrokenWithoutTouchingAnything() {
    _state $'ii  openrazer-driver-dkms\niF  v4l2loopback-dkms\n'
    local out rc=0
    out="$(_run all --only dkms --check --format tsv)" || rc=$?
    assertEquals "kod --check" 10 "$rc"
    assertContains "stan detected" "$out" "dkms	detected"
    assertContains "szczegół: pakiet" "$out" "v4l2loopback-dkms"
    assertNotContains "zdrowy pakiet nie w raporcie" "$out" "openrazer"
    assertEquals "check nie woła dkms/dpkg --configure" "" "$(_calls)"
}

testApplyRemovesFromTreeThenConfigures() {
    _state $'ii  openrazer-driver-dkms\niF  v4l2loopback-dkms\n'
    local out
    out="$(_run all --only dkms --format tsv)"
    assertContains "naprawiono" "$out" "dkms	fixed"
    assertContains "dkms remove modułu z /usr/src" "$(_calls)" "DKMS remove v4l2loopback/0.12.7 --all"
    assertContains "dpkg --configure pakietu" "$(_calls)" "DPKG --configure v4l2loopback-dkms"
    assertNotContains "zdrowy pakiet nietknięty" "$(_calls)" "openrazer"
    assertEquals "kolejność" "DKMS remove v4l2loopback/0.12.7 --all" "$(grep -E '^(DKMS|DPKG)' "$_LOG" | head -1)"
}

testConfigureFailureIsFailedButApplyReturnsZero() {
    _state $'iF  v4l2loopback-dkms\n'
    export DKMS_CONFIGURE_RC=1
    local out rc=0
    out="$(_run all --only dkms --format tsv)" || rc=$?
    assertEquals "apply zawsze 0" 0 "$rc"
    assertContains "stan failed" "$out" "dkms	failed"
    assertContains "ostrzeżenie z poleceniem ręcznym" "$out" "sudo dpkg --configure v4l2loopback-dkms"
}

testApplyOnHealthySystemIsNoop() {
    _state $'ii  v4l2loopback-dkms\n'
    _run all --only dkms --format tsv >/dev/null
    assertEquals "idempotentne — brak wywołań" "" "$(_calls)"
}

testApplyFixesRepairsAndReturnsZero() {
    _state $'iF  v4l2loopback-dkms\n'
    local out rc=0
    out="$(_wrap '')" || rc=$?
    assertEquals "apply_fixes zawsze 0" 0 "$rc"
    assertContains "raport naprawy" "$out" "OK [dkms] naprawiono"
    assertContains "dpkg --configure" "$(_calls)" "DPKG --configure v4l2loopback-dkms"
}

testPostAptPhaseAlsoRunsDkms() {
    _state $'iF  v4l2loopback-dkms\n'
    local out
    out="$(_wrap '' post-apt)"
    assertContains "dkms w fazie post-apt" "$out" "OK [dkms] naprawiono"
}

testApplyFixesNeverFailsWhenRepairFails() {
    _state $'iF  v4l2loopback-dkms\n'
    export DKMS_CONFIGURE_RC=1
    local out rc=0
    out="$(_wrap '')" || rc=$?
    assertEquals "apply_fixes zawsze 0" 0 "$rc"
    assertContains "raport błędu" "$out" "WARN [dkms] naprawa nieudana"
}

testApplyFixesUsesCallerSudoPrefix() {
    _mock mysudo 'echo "SUDO $*" >> "$DKMS_LOG"; "$@"'
    _state $'iF  v4l2loopback-dkms\n'
    _wrap "$_BIN/mysudo" >/dev/null
    assertContains "prefiks z \$SUDO wołającego" "$(_calls)" "SUDO dpkg --configure v4l2loopback-dkms"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
