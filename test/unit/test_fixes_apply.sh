#!/usr/bin/env bash
# Testy jednostkowe: apply_fixes / fixes_refresh_apt_log (packages/commons/fixes_apply.sh) na syntetycznych
# fixach w mktemp — logika wspólna dla {ubuntu,vanilla}/update.sh i vanilla/install.sh (zgoda na
# FIX_RISK=high, raport ok/warn, REPOS_DEAD, odporność na set -Eeuo pipefail).

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPLY="$PROJECT_ROOT/packages/commons/fixes_apply.sh"

setUp() {
    _TMP="$(mktemp -d)"
    _REG="$_TMP/reg"
    _MARK="$_TMP/applied"
    mkdir -p "$_REG"
    : > "$_MARK"
    export FIXES_SUDO='' FIXES_DIRS="$_REG" MARK="$_MARK"
    unset FIXES_CONTEXT CONFIG_CONTEXT
}

tearDown() { rm -rf "$_TMP"; }

# _mkfix <plik> <id> <fazy> <ryzyko> <detect-body> [apply-body]
_mkfix() {
    printf 'FIX_ID=%s\nFIX_DESC="opis %s"\nFIX_PHASE=%q\nFIX_CONTEXTS=all\nFIX_NEEDS_ROOT=0\nFIX_RISK=%s\nfix_detect() {\n%s\n}\nfix_apply() {\n%s\n}\n' \
        "$2" "$2" "$3" "$4" "$5" "${6:-echo "$2" >> "$MARK"}" > "$_REG/$1.sh"
}
# Wywołanie jak w update.sh: set -Eeuo pipefail + trap ERR; $1 = stdin (odpowiedź na pytanie), reszta = faza.
_apply() {
    local answer="$1"; shift
    printf '%s' "$answer" | bash -c '
        set -Eeuo pipefail; trap "echo ERRTRAP" ERR
        ok() { echo "OK $*"; }; warn() { echo "WARN $*"; }; info() { echo "INFO $*"; }
        SUDO=""; . "$1"; shift; apply_fixes "$@"; echo "rc=$?"' _ "$APPLY" "$@" 2>&1
}

testNoFixesForPhaseIsSilentAndSucceeds() {
    local out
    out="$(_apply '' pre-apt)"
    assertEquals "cisza i rc=0" "rc=0" "$out"
}

testHealthyAndDetectedAreReported() {
    _mkfix 010_a a pre-apt low 'return 1'
    _mkfix 020_b b pre-apt low 'return 0'
    local out
    out="$(_apply '' pre-apt)"
    assertContains "ok" "$out" "OK [a] w porządku"
    assertContains "naprawa" "$out" "OK [b] naprawiono"
    assertContains "apply wywołane tylko dla wykrytego" "$(cat "$_MARK")" "b"
    assertNotContains "zdrowy fix nie naprawiany" "$(cat "$_MARK")" "a"
    assertNotContains "bez ERR trap pod set -e" "$out" "ERRTRAP"
}

testFailedAndUnknownAreWarnings() {
    _mkfix 010_f f pre-apt low 'return 0' 'return 1'
    _mkfix 020_u u pre-apt low 'return 7'
    local out
    out="$(_apply '' pre-apt)"
    assertContains "failed" "$out" "WARN [f] naprawa nieudana"
    assertContains "unknown" "$out" "WARN [u] nie udało się sprawdzić"
    assertContains "rc=0 mimo błędów" "$out" "rc=0"
    assertNotContains "bez ERR trap" "$out" "ERRTRAP"
}

testOnlyFixesOfRequestedPhaseRun() {
    _mkfix 010_p p pre-apt low 'return 0'
    _mkfix 020_q q post-apt low 'return 0'
    _apply '' post-apt >/dev/null
    assertEquals "tylko post-apt" "q" "$(cat "$_MARK")"
}

testHighRiskNeedsConsentAndDeclineSkipsOnlyThatFix() {
    _mkfix 010_h h pre-apt high 'return 0'
    _mkfix 020_l l pre-apt low 'return 0'
    local out
    out="$(_apply n pre-apt)"
    assertContains "prośba o zgodę" "$out" "[h] wymaga zgody (ryzyko high)"
    assertContains "odmowa" "$out" "INFO [h] pominięto (brak zgody)"
    assertContains "low naprawiony mimo odmowy" "$out" "OK [l] naprawiono"
    assertEquals "high nietknięty" "l" "$(cat "$_MARK")"
}

testHighRiskConsentAppliesIt() {
    _mkfix 010_h h pre-apt high 'return 0'
    local out
    out="$(_apply y pre-apt)"
    assertContains "naprawiono po zgodzie" "$out" "OK [h] naprawiono"
    assertEquals "high zastosowany" "h" "$(cat "$_MARK")"
}

testHighRiskDefaultsToNoOnEof() {
    _mkfix 010_h h pre-apt high 'return 0'
    local out
    out="$(_apply '' pre-apt)"
    assertContains "domyślnie nie" "$out" "INFO [h] pominięto (brak zgody)"
    assertEquals "high nietknięty" "" "$(cat "$_MARK")"
}

testConsentIsAskedPerFix() {
    _mkfix 010_h1 h1 pre-apt high 'return 0'
    _mkfix 020_h2 h2 pre-apt high 'return 0'
    local out
    out="$(_apply yn pre-apt)"
    assertEquals "tylko pierwszy zatwierdzony" "h1" "$(cat "$_MARK")"
    assertContains "drugi pominięty" "$out" "INFO [h2] pominięto (brak zgody)"
}

testDeadReposGoToReposDeadWhenDeclared() {
    _mkfix 010_d d pre-apt low 'fix_note_dead_repo https://dead.example.com/apt; return 1'
    local out
    out="$(printf '' | bash -c '
        set -Eeuo pipefail
        ok() { :; }; warn() { :; }; info() { :; }
        SUDO=""; declare -a REPOS_DEAD=(); . "$1"; apply_fixes pre-apt; printf "DEAD=%s\n" "${REPOS_DEAD[*]}"' _ "$APPLY" 2>&1)"
    assertContains "REPOS_DEAD" "$out" "DEAD=https://dead.example.com/apt"
}

testMissingReposDeadArrayIsFine() {
    _mkfix 010_d d pre-apt low 'fix_note_dead_repo https://dead.example.com/apt; return 1'
    local out
    out="$(_apply '' pre-apt)"
    assertContains "bez tablicy też rc=0" "$out" "rc=0"
    assertNotContains "bez ERR trap" "$out" "ERRTRAP"
}

testRefreshAptLogWritesLogAndExportsPath() {
    local bin="$_TMP/bin" out
    mkdir -p "$bin"
    printf '#!%s\necho "Pobrano 0 B"\n' "$(command -v bash)" > "$bin/apt-get"
    chmod +x "$bin/apt-get"
    out="$(FIX_APT_UPDATE_LOG="$_TMP/sub/apt.log" PATH="$bin:$PATH" bash -c 'SUDO=""; . "$1"; fixes_refresh_apt_log; echo "LOG=$FIX_APT_UPDATE_LOG"' _ "$APPLY")"
    assertContains "ścieżka logu" "$out" "LOG=$_TMP/sub/apt.log"
    assertContains "treść logu" "$(cat "$_TMP/sub/apt.log")" "Pobrano 0 B"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
