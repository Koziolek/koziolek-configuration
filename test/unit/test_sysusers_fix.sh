#!/usr/bin/env bash
# Testy jednostkowe: fix sysusers (packages/vanilla/fixes.d/010_sysusers.sh) przez runner
# oraz przez apply_fixes (packages/commons/fixes_apply.sh) — tak wołają go vanilla/{install,update}.sh.
#
# Fix leci w osobnym procesie, więc polecenia są mockami w $_BIN (PATH ograniczony do mocków
# i symlinków do kilku narzędzi). sysusers.d podmienione na katalog w $_TMP.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$PROJECT_ROOT/packages/commons/fixes_runner.sh"
APPLY="$PROJECT_ROOT/packages/commons/fixes_apply.sh"

setUp() {
    _TMP="$(mktemp -d)"
    _BIN="$_TMP/bin"
    _LOG="$_TMP/calls.log"
    mkdir -p "$_BIN" "$_TMP/sysusers.d"
    : > "$_LOG"
    local t p
    for t in bash awk grep tr head basename dirname mktemp sort cut rm cat id timeout xargs; do
        p="$(builtin command -v "$t" 2>/dev/null)" && [ -n "$p" ] && ln -s "$p" "$_BIN/$t"
    done
    export SYSUSERS_LOG="$_LOG" SYSUSERS_VER_FILE="$_TMP/ver" SYSUSERS_DOWNLOAD_RC=0 SYSUSERS_DPKG_RC=0
    export FIX_SYSUSERS_DIR="$_TMP/sysusers.d" FIXES_SUDO='' FIXES_CONTEXT=vanilla
    export FIXES_DIRS="$PROJECT_ROOT/packages/vanilla/fixes.d"
    _ver 252
    _mock systemd-sysusers 'echo "systemd $(cat "$SYSUSERS_VER_FILE") ($(cat "$SYSUSERS_VER_FILE").1-1)"; echo "+PAM +AUDIT"'
    _mock dpkg 'case "$1" in
        -S) echo "systemd-standalone-sysusers: $2" ;;
        -i) echo "DPKG -i $2" >> "$SYSUSERS_LOG"
            [ "$SYSUSERS_DPKG_RC" = 0 ] && echo 257 > "$SYSUSERS_VER_FILE"; exit "$SYSUSERS_DPKG_RC" ;;
        esac'
    _mock apt-get 'echo "APT $*" >> "$SYSUSERS_LOG"
        [ "$1" = download ] && [ "$SYSUSERS_DOWNLOAD_RC" = 0 ] && : > "${2}_257.deb"
        [ "$1" = download ] && exit "$SYSUSERS_DOWNLOAD_RC"; exit 0'
}

tearDown() { rm -rf "$_TMP"; }

_mock() { printf '#!%s\n%s\n' "$_BIN/bash" "$2" > "$_BIN/$1"; chmod +x "$_BIN/$1"; }
_ver() { echo "$1" > "$SYSUSERS_VER_FILE"; }
_conf() { printf '%s\n' "$2" > "$_TMP/sysusers.d/$1"; }
_calls() { cat "$_LOG"; }
_run() { PATH="$_BIN" "$_BIN/bash" -c '. "$1"; shift; run_fixes "$@"' _ "$RUNNER" "$@" 2>&1; }
_wrap() { PATH="$_BIN" "$_BIN/bash" -c 'ok() { echo "OK $*"; }; warn() { echo "WARN $*"; }; info() { echo "INFO $*"; }; SUDO=""; . "$1"; apply_fixes post-update' _ "$APPLY" 2>&1; }

testNoSysusersBinaryIsNotApplicable() {
    rm "$_BIN/systemd-sysusers"
    local out
    out="$(_run all --only sysusers --check --format tsv)"
    assertContains "na" "$out" "sysusers	na"
}

testOldSysusersWithoutBangIsOk() {
    _conf basic.conf 'u root 0 "Super User"'
    local out rc=0
    out="$(_run all --only sysusers --check --format tsv)" || rc=$?
    assertEquals "kod --check" 0 "$rc"
    assertContains "ok" "$out" "sysusers	ok"
}

testNewSysusersWithBangIsOk() {
    _ver 257
    _conf pcscd.conf 'u! pcscd - "PC/SC"'
    local out
    out="$(_run all --only sysusers --check --format tsv)"
    assertContains "ok" "$out" "sysusers	ok"
}

testOldSysusersWithBangIsDetectedAndCheckTouchesNothing() {
    _conf pcscd.conf 'u! pcscd - "PC/SC Smart Card Daemon"'
    _conf basic.conf 'u root 0 "Super User"'
    local out rc=0
    out="$(_run all --only sysusers --check --format tsv)" || rc=$?
    assertEquals "kod --check" 10 "$rc"
    assertContains "detected" "$out" "sysusers	detected"
    assertContains "plik z modyfikatorem w szczególe" "$out" "pcscd.conf"
    assertNotContains "plik bez modyfikatora pominięty" "$out" "basic.conf"
    assertEquals "check nie woła apt-get/dpkg -i" "" "$(_calls)"
}

testUnparsableVersionIsUnknownNotDetected() {
    _mock systemd-sysusers 'echo "coś zupełnie innego"'
    _conf pcscd.conf 'u! pcscd - "PC/SC"'
    local out rc=0
    out="$(_run all --only sysusers --check --format tsv)" || rc=$?
    assertEquals "kod --check" 12 "$rc"
    assertContains "unknown" "$out" "sysusers	unknown"
}

testApplyDownloadsAndInstallsOwnerPackage() {
    _conf pcscd.conf 'u! pcscd - "PC/SC"'
    local out
    out="$(_run post-update --only sysusers --format tsv)"
    assertContains "fixed" "$out" "sysusers	fixed"
    assertContains "pobranie pakietu właściciela" "$(_calls)" "APT download systemd-standalone-sysusers"
    assertContains "dpkg -i pliku" "$(_calls)" "DPKG -i systemd-standalone-sysusers_257.deb"
    assertEquals "kolejność: download przed dpkg -i" "APT download systemd-standalone-sysusers" "$(grep -E '^(APT|DPKG)' "$_LOG" | head -1)"
}

testApplyIsIdempotentAfterFix() {
    _conf pcscd.conf 'u! pcscd - "PC/SC"'
    _run post-update --only sysusers >/dev/null
    : > "$_LOG"
    local out
    out="$(_run post-update --only sysusers --format tsv)"
    assertContains "ok po naprawie" "$out" "sysusers	ok"
    assertEquals "drugi przebieg bez wywołań" "" "$(_calls)"
}

testDownloadFailureIsFailedButApplyReturnsZero() {
    _conf pcscd.conf 'u! pcscd - "PC/SC"'
    export SYSUSERS_DOWNLOAD_RC=1
    local out rc=0
    out="$(_run post-update --only sysusers --format tsv)" || rc=$?
    assertEquals "apply zawsze 0" 0 "$rc"
    assertContains "failed" "$out" "sysusers	failed"
    assertNotContains "bez dpkg -i po nieudanym pobraniu" "$(_calls)" "DPKG"
}

testDpkgFailureIsFailed() {
    _conf pcscd.conf 'u! pcscd - "PC/SC"'
    export SYSUSERS_DPKG_RC=1
    local out
    out="$(_run post-update --only sysusers --format tsv)"
    assertContains "failed" "$out" "sysusers	failed"
}

testOtherContextIsNotApplicable() {
    _conf pcscd.conf 'u! pcscd - "PC/SC"'
    local out
    out="$(FIXES_CONTEXT=ubuntu _run all --only sysusers --check --format tsv)"
    assertNotContains "nie dotyczy ubuntu" "$out" "sysusers"
}

testApplyFixesRepairsAndReturnsZero() {
    _conf pcscd.conf 'u! pcscd - "PC/SC"'
    local out rc=0
    out="$(_wrap)" || rc=$?
    assertEquals "apply_fixes zawsze 0" 0 "$rc"
    assertContains "raport" "$out" "OK [sysusers] naprawiono"
    assertContains "dpkg -i" "$(_calls)" "DPKG -i"
}

testApplyFixesNeverFailsWhenRepairFails() {
    _conf pcscd.conf 'u! pcscd - "PC/SC"'
    export SYSUSERS_DOWNLOAD_RC=1
    local out rc=0
    out="$(_wrap)" || rc=$?
    assertEquals "apply_fixes zawsze 0" 0 "$rc"
    assertContains "raport błędu" "$out" "WARN [sysusers] naprawa nieudana"
}

testApplyFixesIsNoopOnHealthySystem() {
    local out
    out="$(_wrap)"
    assertContains "ok" "$out" "OK [sysusers] w porządku"
    assertEquals "brak wywołań" "" "$(_calls)"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
