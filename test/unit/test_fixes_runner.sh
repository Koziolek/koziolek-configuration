#!/usr/bin/env bash
# Testy jednostkowe: run_fixes (packages/commons/fixes_runner.sh) na syntetycznych fixach w mktemp.
# Runner odpalany w osobnym `bash -c` pod `set -Eeuo pipefail` + trap ERR — tak jak z update_*.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$PROJECT_ROOT/packages/commons/fixes_runner.sh"

setUp() {
    _TMP="$(mktemp -d)"
    _REG="$_TMP/reg"
    mkdir -p "$_REG"
    _OUT='' _ERR='' _RC=''
}
tearDown() { rm -rf "$_TMP"; }

# _mkfix <nr_nazwa> <id> <fazy> <ryzyko> <root> <detect> [apply] [verify]
_mkfix() {
    local file="$_REG/$1.sh" id="$2" phase="$3" risk="$4" root="$5" detect="$6" apply="${7:-return 0}" verify="${8:-}"
    {
        printf 'FIX_ID=%q\nFIX_DESC="opis %s"\nFIX_PHASE=%q\nFIX_CONTEXTS=%q\nFIX_NEEDS_ROOT=%s\nFIX_RISK=%s\n' \
            "$id" "$id" "$phase" "${T_CONTEXTS:-all}" "$root" "$risk"
        printf 'fix_detect() {\n%s\n}\nfix_apply() {\n%s\n}\n' "$detect" "$apply"
        [ -n "$verify" ] && printf 'fix_verify() {\n%s\n}\n' "$verify"
    } > "$file"
}

# _run <args run_fixes…> — wynik: $_OUT (stdout raportu), $_ERR (stderr), $_RC (kod run_fixes)
_run() {
    local raw
    raw="$(FIXES_DIRS="$_REG" bash -c '. "$1"; shift; set -Eeuo pipefail; trap "echo ERRTRAP >&2" ERR
        rc=0; run_fixes "$@" || rc=$?; echo "RC=$rc"' _ "$RUNNER" "$@" 2>"$_TMP/stderr")"
    _RC="${raw##*RC=}"
    _OUT="${raw%RC=*}"
    _ERR="$(cat "$_TMP/stderr")"
}

testEmptyRegistryIsOkAndReportsHeaderOnly() {
    _run all --check --format tsv
    assertEquals "kod" "0" "$_RC"
    assertContains "nagłówek raportu" "$_OUT" "#fixes-report v1"
}

testUnknownPhaseOrOptionIsUsageError() {
    _run nope
    assertEquals "kod" "2" "$_RC"
    _run all --bogus
    assertEquals "kod" "2" "$_RC"
    _run all --format yaml
    assertEquals "kod" "2" "$_RC"
}

testCheckDetectedNeverCallsApply() {
    _mkfix 010_a a pre-apt low 0 'return 0' 'touch "'"$_TMP"'/apply.called"'
    _run pre-apt --check --format tsv
    assertEquals "kod 10 = wykryto" "10" "$_RC"
    assertContains "stan detected" "$_OUT" "$(printf 'a\tdetected\tpre-apt\tlow')"
    assertFalse "fix_apply nie wołany w --check" "[ -e '$_TMP/apply.called' ]"
}

testHealthyAndNotApplicable() {
    _mkfix 010_h h pre-apt low 0 'return 1'
    _mkfix 020_n n pre-apt low 0 'return 2'
    _run pre-apt --check --format tsv
    assertEquals "kod" "0" "$_RC"
    assertContains "ok" "$_OUT" "$(printf 'h\tok\t')"
    assertContains "na" "$_OUT" "$(printf 'n\tna\t')"
}

testUnknownExitCodeIsUnknownNotDetected() {
    _mkfix 010_u u pre-apt low 0 'exit 7'
    _run pre-apt --check --format tsv
    assertEquals "kod 12" "12" "$_RC"
    assertContains "unknown" "$_OUT" "$(printf 'u\tunknown\t')"
    assertNotContains "nie detected" "$_OUT" "detected"
}

testTimeoutIsUnknown() {
    command -v timeout >/dev/null 2>&1 || startSkipping
    _mkfix 010_t t pre-apt low 0 'sleep 30'
    FIXES_TIMEOUT=1 _run pre-apt --check --format tsv
    assertContains "timeout = unknown" "$_OUT" "$(printf 't\tunknown\t')"
    assertEquals "kod 12" "12" "$_RC"
}

testCrashingFixesDoNotAbortOthersUnderStrictShell() {
    _mkfix 010_bad bad pre-apt low 0 'false; exit 1'
    _mkfix 020_kill kill pre-apt low 0 'kill -9 $$'
    _mkfix 030_good good pre-apt low 0 'return 1'
    _run pre-apt --check --format tsv
    assertContains "ostatni fix się wykonał" "$_OUT" "$(printf 'good\tok\t')"
    assertNotContains "trap ERR wołającego nie odpalił" "$_ERR" "ERRTRAP"
}

testPlainApplyCallSurvivesFailingFixUnderSetE() {
    _mkfix 010_f f pre-apt low 0 'return 0' 'return 1'
    local out
    out="$(FIXES_DIRS="$_REG" bash -c '. "$1"; set -Eeuo pipefail; run_fixes pre-apt >/dev/null 2>&1; echo SURVIVED' _ "$RUNNER")"
    assertEquals "skrypt pod set -e przeżył" "SURVIVED" "$out"
}

testApplyFixesAndVerifies() {
    _mkfix 010_ok okfix pre-apt low 0 '[ ! -e "'"$_TMP"'/done" ]' 'touch "'"$_TMP"'/done"' '[ -e "'"$_TMP"'/done" ]'
    _run pre-apt --format tsv --strict
    assertContains "fixed" "$_OUT" "$(printf 'okfix\tfixed\t')"
    assertEquals "kod" "0" "$_RC"
    _run pre-apt --format tsv --strict
    assertContains "drugi raz zdrowo (idempotentnie)" "$_OUT" "$(printf 'okfix\tok\t')"
}

testApplyFailureAndStrictExitCodes() {
    _mkfix 010_x x pre-apt low 0 'return 0' 'return 3'
    _run pre-apt --format tsv
    assertContains "failed" "$_OUT" "$(printf 'x\tfailed\t')"
    assertEquals "bez --strict zawsze 0" "0" "$_RC"
    _run pre-apt --format tsv --strict
    assertEquals "--strict: 11" "11" "$_RC"
}

testFailedUsesFixDetailOverGenericMessage() {
    _mkfix 010_d d pre-apt low 0 'return 0' 'fix_detail "klucz bez dopasowanego źródła"; return 1'
    _run pre-apt --format tsv
    assertContains "szczegół fixa" "$_OUT" "klucz bez dopasowanego źródła"
    assertNotContains "bez ogólnego komunikatu" "$_OUT" "fix_apply zakończył się błędem"
}

testFailedWithoutDetailKeepsGenericMessage() {
    _mkfix 010_g g pre-apt low 0 'return 0' 'return 1'
    _run pre-apt --format tsv
    assertContains "ogólny komunikat" "$_OUT" "fix_apply zakończył się błędem"
}

testVerifyFailureMakesFailed() {
    _mkfix 010_v v pre-apt low 0 'return 0' 'return 0' 'return 1'
    _run pre-apt --format tsv
    assertContains "failed po nieudanym verify" "$_OUT" "$(printf 'v\tfailed\t')"
}

testHighRiskNeedsExplicitFlag() {
    _mkfix 010_r r pre-apt high 0 'return 0' 'touch "'"$_TMP"'/r.applied"'
    _run pre-apt --format tsv
    assertContains "skipped" "$_OUT" "$(printf 'r\tskipped\t')"
    assertFalse "apply nie poszedł" "[ -e '$_TMP/r.applied' ]"
    _run pre-apt --format tsv --allow-high
    assertContains "fixed z flagą" "$_OUT" "$(printf 'r\tfixed\t')"
}

testNeedsRootSkippedWithoutRoot() {
    _mkfix 010_root root pre-apt low 1 'return 0' 'touch "'"$_TMP"'/root.applied"'
    FIXES_SUDO=none _run pre-apt --format tsv
    assertContains "skipped" "$_OUT" "$(printf 'root\tskipped\t')"
    assertFalse "apply nie poszedł" "[ -e '$_TMP/root.applied' ]"
    FIXES_SUDO='' _run pre-apt --format tsv
    assertContains "fixed gdy root" "$_OUT" "$(printf 'root\tfixed\t')"
}

testSudoIsDeniedInDetectAndCheck() {
    _mkfix 010_s s pre-apt low 1 '$SUDO true >/dev/null 2>&1; echo $? > "'"$_TMP"'/detect.sudo.rc"; return 0' \
        '$SUDO true >/dev/null 2>&1; echo $? > "'"$_TMP"'/apply.sudo.rc"'
    FIXES_SUDO='' _run pre-apt --format tsv
    assertEquals "detect: sudo zabronione (fix_denied=126)" "126" "$(cat "$_TMP/detect.sudo.rc")"
    assertEquals "apply: root dozwolony" "0" "$(cat "$_TMP/apply.sudo.rc")"
}

testCallersSudoIsUntouched() {
    _mkfix 010_s s pre-apt low 1 'return 0'
    local out
    out="$(FIXES_DIRS="$_REG" FIXES_SUDO='' bash -c '. "$1"; SUDO="mój-sudo"; run_fixes pre-apt >/dev/null 2>&1; echo "$SUDO"' _ "$RUNNER")"
    assertEquals "SUDO wołającego bez zmian" "mój-sudo" "$out"
}

testStdinIsClosedSoReadDoesNotHang() {
    _mkfix 010_i i pre-apt low 0 'return 0' 'read -r answer; [ -z "$answer" ]'
    _run pre-apt --format tsv
    assertContains "fixed (read dostał EOF)" "$_OUT" "$(printf 'i\tfixed\t')"
}

testPhaseOnlyAndContextFilters() {
    _mkfix 010_p p post-apt low 0 'return 1'
    _mkfix 020_q q "pre-apt post-apt" low 0 'return 1'
    _run pre-apt --check --format tsv
    assertNotContains "p nie w pre-apt" "$_OUT" "$(printf 'p\tok')"
    assertContains "q w pre-apt" "$_OUT" "$(printf 'q\tok')"
    _run all --check --format tsv
    assertContains "all: p" "$_OUT" "$(printf 'p\tok')"
    _run all --check --format tsv --only q
    assertNotContains "--only: bez p" "$_OUT" "$(printf 'p\tok')"
    assertContains "--only: q" "$_OUT" "$(printf 'q\tok')"

    T_CONTEXTS=redhat _mkfix 030_c c pre-apt low 0 'return 1'
    FIXES_CONTEXT=ubuntu _run pre-apt --check --format tsv
    assertNotContains "redhat poza ubuntu" "$_OUT" "$(printf 'c\tok')"
    T_CONTEXTS=debian _mkfix 030_c c pre-apt low 0 'return 1'
    FIXES_CONTEXT=vanilla _run pre-apt --check --format tsv
    assertContains "debian obejmuje vanilla (łańcuch)" "$_OUT" "$(printf 'c\tok')"
}

testInvalidMetadataIsUnknown() {
    printf 'FIX_ID=broken\nfix_detect() { return 1; }\n' > "$_REG/010_broken.sh"
    _run all --check --format tsv
    assertContains "unknown" "$_OUT" "$(printf 'broken\tunknown\t')"
    assertContains "powód" "$_OUT" "niepoprawny plik fixa"
    assertEquals "kod 12" "12" "$_RC"
}

testDetailAndJsonEscaping() {
    _mkfix 010_d d pre-apt low 0 'fix_detail "a \"b\" \\c"; return 0'
    _run pre-apt --check --format json
    assertContains "JSON Lines ze stanem" "$_OUT" '"fix_id":"d","state":"detected"'
    assertContains "escape cudzysłowu i backslasha" "$_OUT" '"detail":"a \"b\" \\c"'
}

testTextFormatAndFixLog() {
    _mkfix 010_l l pre-apt low 0 'fix_log "liczba=%d" 3; return 0'
    _run pre-apt --check
    assertContains "tekst" "$_OUT" "[detected] l — opis l"
    assertContains "fix_log na stderr z prefiksem" "$_ERR" "[l] liczba=3"
}

testDeadReposAreAggregated() {
    _mkfix 010_g g pre-apt low 0 'fix_note_dead_repo "http://x/b"; fix_note_dead_repo "http://x/a"; fix_note_dead_repo "http://x/a"; return 1'
    _run pre-apt --check --format tsv
    assertContains "martwe repo" "$_OUT" "$(printf '#dead_repo\thttp://x/a')"
    assertContains "martwe repo b" "$_OUT" "$(printf '#dead_repo\thttp://x/b')"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
