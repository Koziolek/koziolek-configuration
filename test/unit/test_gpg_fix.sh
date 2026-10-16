#!/usr/bin/env bash
# Testy jednostkowe: fix apt-gpg (packages/commons/fixes.d/020_apt_gpg.sh) przez runner
# oraz wrapper refresh_apt_gpg_keys (packages/commons/gpg_fix.sh).
#
# Fix leci w osobnym procesie, więc polecenia są mockami w $_BIN (PATH ograniczony do mocków
# i symlinków do kilku narzędzi). /etc/apt podmieniony na katalogi w $_TMP.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$PROJECT_ROOT/packages/commons/fixes_runner.sh"
WRAPPER="$PROJECT_ROOT/packages/commons/gpg_fix.sh"

_NOPUB='W: GPG error: https://repo.example.com/apt stable InRelease: The following signatures couldn'"'"'t be verified because the public key is not available: NO_PUBKEY ABCDEF0123456789'
_DEAD='E: The repository '"'"'https://dead.example.com/apt orchid Release'"'"' does not have a Release file.'

setUp() {
    _TMP="$(mktemp -d)"
    _BIN="$_TMP/bin"
    _LOG="$_TMP/calls.log"
    mkdir -p "$_BIN" "$_TMP/keyrings" "$_TMP/sources.d"
    : > "$_LOG"
    local t p
    for t in bash awk grep sed sort tr head basename dirname mktemp cut rm cat id timeout find tee chmod mkdir touch; do
        p="$(builtin command -v "$t" 2>/dev/null)" && [ -n "$p" ] && ln -s "$p" "$_BIN/$t"
    done
    export GPG_LOG="$_LOG" APT_OUT_FILE="$_TMP/apt-out" GPG_RECV_RC=0
    export FIX_APT_UPDATE_LOG="$_TMP/apt.log" FIX_APT_KEYRINGS_DIR="$_TMP/keyrings"
    export FIX_APT_SOURCES_LIST="$_TMP/sources.list" FIX_APT_SOURCES_DIR="$_TMP/sources.d"
    export FIXES_SUDO='' FIXES_CONTEXT=debian XDG_CACHE_HOME="$_TMP/cache"
    export FIXES_DIRS="$PROJECT_ROOT/packages/commons/fixes.d"
    : > "$APT_OUT_FILE"
    # apt-get update wypisuje zawartość $APT_OUT_FILE
    _mock apt-get 'echo "APT $*" >> "$GPG_LOG"; [ "$1" = update ] && cat "$APT_OUT_FILE"; exit 0'
    # gpg: --show-keys <plik> => [expired] gdy plik zawiera EXPIRED; --recv-keys => sukces leczy apt
    _mock gpg 'echo "GPG $*" >> "$GPG_LOG"
        case "$*" in
            *--show-keys*) for f in "$@"; do :; done; if grep -q EXPIRED "$f" 2>/dev/null; then echo "pub:e:4096:1:AAAA:1:1::-:::sc::::::23::0:"; else echo "pub:-:4096:1:AAAA:1:::-:::scESC::::::23::0:"; fi; exit 0 ;;
            *--recv-keys*) [ "$GPG_RECV_RC" = 0 ] && : > "$APT_OUT_FILE"; exit "$GPG_RECV_RC" ;;
            *--fingerprint*) echo "Key fingerprint = AAAA BBBB"; exit 0 ;;
            *--export*) echo "KEYDATA"; exit 0 ;;
        esac'
    printf 'deb https://repo.example.com/apt stable main\n' > "$_TMP/sources.d/example.list"
}

tearDown() { rm -rf "$_TMP"; }

_mock() { printf '#!%s\n%s\n' "$_BIN/bash" "$2" > "$_BIN/$1"; chmod +x "$_BIN/$1"; }
_log() { printf '%s\n' "$@" > "$FIX_APT_UPDATE_LOG"; }
_calls() { cat "$_LOG"; }
_run() { PATH="$_BIN" "$_BIN/bash" -c '. "$1"; shift; run_fixes "$@"' _ "$RUNNER" "$@" 2>&1; }
# wrapper: ok/warn/info jak w update.sh; po wywołaniu wypisuje REPOS_DEAD
_wrap() {
    PATH="$_BIN" "$_BIN/bash" -c '
        ok() { echo "OK $*"; }; warn() { echo "WARN $*"; }; info() { echo "INFO $*"; }
        SUDO=""; declare -a REPOS_DEAD=(); . "$1"; . "$2"; refresh_apt_gpg_keys; echo "rc=$?"
        for r in "${REPOS_DEAD[@]}"; do echo "DEAD $r"; done' _ "$RUNNER" "$WRAPPER" 2>&1
}

testNoLogAndNoExpiredKeysIsUnknownNotOk() {
    local out rc=0
    out="$(_run all --only apt-gpg --check --format tsv)" || rc=$?
    assertEquals "kod --check" 12 "$rc"
    assertContains "unknown" "$out" "apt-gpg	unknown"
}

testCleanLogIsOk() {
    _log 'Pobrano 0 B' 'Czytanie list pakietów...'
    local out rc=0
    out="$(_run all --only apt-gpg --check --format tsv)" || rc=$?
    assertEquals "kod --check" 0 "$rc"
    assertContains "ok" "$out" "apt-gpg	ok"
}

testNoPubkeyInLogIsDetectedAndCheckTouchesNothing() {
    _log "$_NOPUB"
    local out rc=0
    out="$(_run all --only apt-gpg --check --format tsv)" || rc=$?
    assertEquals "kod --check" 10 "$rc"
    assertContains "detected" "$out" "apt-gpg	detected"
    assertContains "id klucza w szczególe" "$out" "NO_PUBKEY: ABCDEF0123456789"
    assertEquals "check nie woła apt-get ani gpg" "" "$(_calls)"
    assertNotContains "źródło bez zmian" "$(cat "$_TMP/sources.d/example.list")" "signed-by"
}

testStaleLogIsIgnored() {
    _log "$_NOPUB"
    touch -d '10 days ago' "$FIX_APT_UPDATE_LOG"
    local out
    out="$(_run all --only apt-gpg --check --format tsv)"
    assertContains "unknown z przeterminowanego logu" "$out" "apt-gpg	unknown"
}

testExpiredImportedKeyIsDetectedOffline() {
    echo EXPIRED > "$_TMP/keyrings/imported-DEADBEEF.gpg"
    local out rc=0
    out="$(_run all --only apt-gpg --check --format tsv)" || rc=$?
    assertEquals "kod --check" 10 "$rc"
    assertContains "wygasły klucz" "$out" "wygasłe: imported-DEADBEEF.gpg"
    assertTrue "plik nietknięty" "[ -f '$_TMP/keyrings/imported-DEADBEEF.gpg' ]"
}

testDeadRepoIsReportedButDoesNotChangeState() {
    _log "$_DEAD"
    local out
    out="$(_run all --only apt-gpg --check --format tsv)"
    assertContains "stan ok" "$out" "apt-gpg	ok"
    assertContains "martwe repo" "$out" "#dead_repo	https://dead.example.com/apt"
}

testOtherContextIsNotApplicable() {
    _log "$_NOPUB"
    local out
    out="$(FIXES_CONTEXT=redhat _run all --only apt-gpg --check --format tsv)"
    assertNotContains "nie dotyczy redhat" "$out" "apt-gpg"
}

testApplyFetchesKeyAndPinsItToSourceFile() {
    _log "$_NOPUB"
    local out
    out="$(_run pre-apt --only apt-gpg --format tsv)"
    assertContains "fixed" "$out" "apt-gpg	fixed"
    assertTrue "keyring zapisany" "[ -f '$_TMP/keyrings/imported-ABCDEF0123456789.gpg' ]"
    assertContains "signed-by w źródle" "$(cat "$_TMP/sources.d/example.list")" "signed-by=$_TMP/keyrings/imported-ABCDEF0123456789.gpg"
    assertContains "keyserver" "$(_calls)" "--recv-keys ABCDEF0123456789"
    assertContains "apt-get update po naprawie" "$(_calls)" "APT update"
}

testApplyNeverUsesTrustedGpgD() {
    _log "$_NOPUB"
    _run pre-apt --only apt-gpg >/dev/null
    assertNotContains "bez trusted.gpg.d" "$(_calls)" "trusted.gpg.d"
}

testRecvFailureIsFailedAndWritesNoKeyring() {
    _log "$_NOPUB"
    export GPG_RECV_RC=1
    local out rc=0
    out="$(_run pre-apt --only apt-gpg --format tsv)" || rc=$?
    assertEquals "apply zawsze 0" 0 "$rc"
    assertContains "failed" "$out" "apt-gpg	failed"
    assertFalse "bez keyringu" "[ -e '$_TMP/keyrings/imported-ABCDEF0123456789.gpg' ]"
    assertNotContains "źródło bez zmian" "$(cat "$_TMP/sources.d/example.list")" "signed-by"
}

testKeyWithoutMatchingSourceIsFailed() {
    _log "$_NOPUB"
    printf 'deb https://other.example.org/apt stable main\n' > "$_TMP/sources.d/example.list"
    local out
    out="$(_run pre-apt --only apt-gpg --format tsv)"
    assertContains "failed" "$out" "apt-gpg	failed"
    assertContains "powód" "$out" "nie dowiązano automatycznie"
}

testExpiredKeyIsRemovedAndRefetched() {
    echo EXPIRED > "$_TMP/keyrings/imported-ABCDEF0123456789.gpg"
    printf '%s\n' "$_NOPUB" > "$APT_OUT_FILE"
    _log "$_NOPUB"
    local out
    out="$(_run pre-apt --only apt-gpg --format tsv)"
    assertContains "fixed" "$out" "apt-gpg	fixed"
    assertFalse "nowy klucz nie jest wygasły" "grep -q EXPIRED '$_TMP/keyrings/imported-ABCDEF0123456789.gpg'"
    assertContains "ponowne pobranie" "$(_calls)" "--recv-keys ABCDEF0123456789"
}

testWrapperRepairsAndReports() {
    printf '%s\n' "$_NOPUB" > "$APT_OUT_FILE"
    local out
    out="$(_wrap)"
    assertContains "ok po naprawie" "$out" "OK Klucze GPG naprawione"
    assertContains "kod 0" "$out" "rc=0"
    assertTrue "log apt-get update zapisany" "[ -f '$FIX_APT_UPDATE_LOG' ]"
}

testWrapperHealthySystem() {
    printf 'Pobrano 0 B\n' > "$APT_OUT_FILE"
    local out
    out="$(_wrap)"
    assertContains "ok" "$out" "OK Klucze GPG w porządku"
}

testWrapperCollectsDeadReposIntoArray() {
    printf '%s\n' "$_DEAD" > "$APT_OUT_FILE"
    local out
    out="$(_wrap)"
    assertContains "REPOS_DEAD wypełnione" "$out" "DEAD https://dead.example.com/apt"
}

testWrapperNeverFailsWhenRepairFails() {
    printf '%s\n' "$_NOPUB" > "$APT_OUT_FILE"
    export GPG_RECV_RC=1
    local out
    out="$(_wrap)"
    assertContains "kod 0" "$out" "rc=0"
    assertContains "ostrzeżenie" "$out" "WARN Klucze GPG (failed)"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
