#!/usr/bin/env bash
# Testy jednostkowe: fixes_check / fixes_check_dirs (packages/fixes_check.sh) — wejście dla crona do rejestru napraw
# (#144). Syntetyczne fixy w mktemp; pilnujemy trybu tylko-do-odczytu (fix_apply nigdy), kodów wyjścia 0/10/12/2,
# uruchomienia wprost i bez $CONFIG_CONTEXT (cron).

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$PROJECT_ROOT/packages/fixes_check.sh"

setUp() {
    _TMP="$(mktemp -d)"
    _REG="$_TMP/reg"
    _MARK="$_TMP/applied"
    mkdir -p "$_REG"
    : > "$_MARK"
    export FIXES_DIRS="$_REG" FIXES_SUDO='' MARK="$_MARK"
    unset FIXES_CONTEXT CONFIG_CONTEXT CONFIG_CONTEXT_FORCE
}

tearDown() { rm -rf "$_TMP"; }

# _mkfix <plik> <id> <fazy> <ryzyko> <kod-detect>
_mkfix() {
    printf 'FIX_ID=%s\nFIX_DESC="opis %s"\nFIX_PHASE=%q\nFIX_CONTEXTS=all\nFIX_NEEDS_ROOT=0\nFIX_RISK=%s\nfix_detect() { return %s; }\nfix_apply() { echo "%s" >> "$MARK"; }\n' \
        "$2" "$2" "$3" "$4" "$5" "$2" > "$_REG/$1.sh"
}
# Jak z crona: sourcowanie, potem funkcja; wynik = wyjście, kod w ostatniej linii.
_check() {
    bash -c '. "$1"; shift; fixes_check "$@"; echo "rc=$?"' _ "$CHECK" "$@" 2>/dev/null </dev/null
}

testSourcingRunsNothing() {
    _mkfix 010_a a pre-apt low 0
    local out
    out="$(bash -c '. "$1"; echo sourced' _ "$CHECK" 2>&1 </dev/null)"
    assertEquals "sourcowanie nic nie wypisuje ani nie uruchamia" "sourced" "$out"
    assertEquals "brak apply" "" "$(cat "$_MARK")"
}

testHealthyExitsZero() {
    _mkfix 010_a a pre-apt low 1
    local out
    out="$(_check)"
    assertContains "wiersz ok" "$out" $'a\tok\t'
    assertContains "kod 0" "$out" "rc=0"
}

testDetectedExitsTenAndNeverApplies() {
    _mkfix 010_a a pre-apt low 0
    _mkfix 020_b b pre-apt high 0
    local out
    out="$(_check)"
    assertContains "a wykryty" "$out" $'a\tdetected\t'
    assertContains "b wykryty (high też tylko raportowany)" "$out" $'b\tdetected\t'
    assertContains "kod 10" "$out" "rc=10"
    assertEquals "fix_apply nigdy nie leci" "" "$(cat "$_MARK")"
}

testUnknownExitsTwelve() {
    _mkfix 010_a a pre-apt low 7
    local out
    out="$(_check)"
    assertContains "unknown" "$out" $'a\tunknown\t'
    assertContains "kod 12" "$out" "rc=12"
}

testPhaseFilter() {
    _mkfix 010_a a pre-apt low 0
    _mkfix 020_b b post-apt low 1
    local out
    out="$(_check post-apt)"
    assertNotContains "pre-apt pominięty" "$out" $'a\t'
    assertContains "post-apt obecny" "$out" $'b\tok\t'
    assertContains "kod 0" "$out" "rc=0"
}

testOnlyFilter() {
    _mkfix 010_a a pre-apt low 0
    _mkfix 020_b b pre-apt low 1
    local out
    out="$(_check --only b)"
    assertNotContains "a pominięty" "$out" $'a\t'
    assertContains "kod 0" "$out" "rc=0"
}

testJsonFormat() {
    _mkfix 010_a a pre-apt low 1
    local out
    out="$(_check all --format json)"
    assertContains "json" "$out" '"fix_id"'
}

testBadArgumentReturnsTwo() {
    local out
    out="$(_check --bogus)"
    assertContains "kod 2" "$out" "rc=2"
}

testRunsDirectly() {
    _mkfix 010_a a pre-apt low 0
    local out rc
    out="$(bash "$CHECK" pre-apt 2>/dev/null </dev/null)"; rc=$?
    assertEquals "kod 10 wprost" 10 "$rc"
    assertContains "raport" "$out" $'a\tdetected\t'
}

testWorksWithoutConfigContextLikeCron() {
    _mkfix 010_a a pre-apt low 1
    local out rc
    out="$(env -i PATH="$PATH" HOME="$_TMP" FIXES_DIRS="$_REG" MARK="$_MARK" bash "$CHECK" 2>/dev/null </dev/null)"; rc=$?
    assertEquals "kod 0 bez CONFIG_CONTEXT" 0 "$rc"
    assertContains "raport" "$out" $'a\tok\t'
}

testDirsIncludeSystemRegistry() {
    local dirs
    dirs="$(unset FIXES_DIRS; CONFIG_CONTEXT_FORCE=vanilla bash -c '. "$1"; fixes_check_dirs' _ "$CHECK")"
    assertContains "commons" "$dirs" "packages/commons/fixes.d"
    assertContains "vanilla" "$dirs" "packages/vanilla/fixes.d"
}

testDirsWithoutSystemRegistryAreCommonsOnly() {
    local dirs
    dirs="$(unset FIXES_DIRS; CONFIG_CONTEXT_FORCE=ubuntu bash -c '. "$1"; fixes_check_dirs' _ "$CHECK")"
    assertContains "commons" "$dirs" "packages/commons/fixes.d"
    assertNotContains "bez vanilla" "$dirs" "vanilla"
}

testRealRegistryCheckNeverFailsHard() {
    local out rc
    out="$(unset FIXES_DIRS; env -i PATH="$PATH" HOME="$_TMP" bash "$CHECK" 2>/dev/null </dev/null)"; rc=$?
    case "$rc" in 0|10|11|12) rc=ok ;; esac
    assertEquals "kod z zestawu 0/10/11/12" ok "$rc"
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
