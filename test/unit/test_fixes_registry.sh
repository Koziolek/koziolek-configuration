#!/usr/bin/env bash
# Testy jednostkowe: lint rejestru napraw (fixes_lint z packages/commons/fixes_runner.sh).

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$PROJECT_ROOT/packages/commons/fixes_runner.sh"

setUp() { _TMP="$(mktemp -d)"; }
tearDown() { rm -rf "$_TMP"; }

_lint() { bash -c '. "$1"; shift; fixes_lint "$@"' _ "$RUNNER" "$@" 2>&1; }

_valid_fix() {
    cat > "$1" <<FIX
FIX_ID=${2:-ok-fix}
FIX_DESC="opis"
FIX_PHASE="pre-apt"
FIX_CONTEXTS=all
FIX_NEEDS_ROOT=0
FIX_RISK=low
fix_detect() {
    return 1
}
fix_apply() {
    return 0
}
FIX
}

testRealRegistriesPassLint() {
    local dirs=() d
    for d in "$PROJECT_ROOT"/packages/*/fixes.d; do [ -d "$d" ] && dirs+=("$d"); done
    assertTrue "rejestr commons w lincie" "[ -d '$PROJECT_ROOT/packages/commons/fixes.d' ]"
    local out rc=0
    out="$(_lint "${dirs[@]}")" || rc=$?
    assertEquals "lint rejestrów repo: $out" "0" "$rc"
}

testRegistryDocumentsContract() {
    assertTrue "README kontraktu" "[ -f '$PROJECT_ROOT/packages/commons/fixes.d/README.md' ]"
}

testValidFixPasses() {
    _valid_fix "$_TMP/010_a.sh"
    local rc=0
    _lint "$_TMP" >/dev/null || rc=$?
    assertEquals "poprawny fix" "0" "$rc"
}

testDuplicateIdIsReported() {
    _valid_fix "$_TMP/010_a.sh" same
    _valid_fix "$_TMP/020_b.sh" same
    local out rc=0
    out="$(_lint "$_TMP")" || rc=$?
    assertEquals "kod" "1" "$rc"
    assertContains "duplikat" "$out" "zduplikowane FIX_ID"
}

testMissingFunctionsAndBadMetadataAreReported() {
    printf 'FIX_ID=nodetect\nFIX_DESC=x\nFIX_PHASE=pre-apt\nFIX_CONTEXTS=all\nFIX_NEEDS_ROOT=0\nFIX_RISK=low\nfix_apply() { :; }\n' > "$_TMP/010_a.sh"
    _valid_fix "$_TMP/020_b.sh" badphase; sed -i 's/pre-apt/sometime/' "$_TMP/020_b.sh"
    _valid_fix "$_TMP/030_c.sh" BadId
    local out rc=0
    out="$(_lint "$_TMP")" || rc=$?
    assertEquals "kod" "1" "$rc"
    assertContains "brak fix_detect" "$out" "brak funkcji fix_detect"
    assertContains "zła faza" "$out" "nieznana faza"
    assertContains "zły id" "$out" "FIX_ID"
}

testDetectThatWritesOrUsesNetworkOrRootIsReported() {
    local word
    for word in '$SUDO true' 'sudo true' 'curl -s x' 'apt-get update' 'rm -f /tmp/x'; do
        _valid_fix "$_TMP/010_a.sh"
        sed -i "s|^    return 1\$|    $word; return 1|" "$_TMP/010_a.sh"
        local out rc=0
        out="$(_lint "$_TMP")" || rc=$?
        assertEquals "'$word' w fix_detect" "1" "$rc"
        assertContains "komunikat dla '$word'" "$out" "fix_detect wygląda na"
    done
}

testCommentsInDetectAreIgnored() {
    _valid_fix "$_TMP/010_a.sh"
    sed -i 's|^    return 1$|    # nie wołaj sudo ani curl tutaj\n    return 1|' "$_TMP/010_a.sh"
    local rc=0
    _lint "$_TMP" >/dev/null || rc=$?
    assertEquals "komentarz nie jest naruszeniem" "0" "$rc"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
