#!/usr/bin/env bash
# Testy jednostkowe: hub_mass_merge (git/hub_functions.sh) i alias `hmm` (#210).
# `gh` jest atrapą w PATH (bez sieci); logi przechwytywane jako "klucz argumenty".

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export MESSAGES_LANG=pl
export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/git/hub_functions.sh"

_LOG=''
log_info() { _LOG+="INFO $*"$'\n'; }
log_error() { _LOG+="ERROR $*"$'\n'; }
log_warn() { _LOG+="WARN $*"$'\n'; }
log_man() { _LOG+="MAN $*"$'\n'; }

setUp() {
    _T="$(mktemp -d)"
    _ORIG_PATH="$PATH"
    mkdir -p "$_T/bin"
    export GH_LOG="$_T/gh.log"
    : >"$GH_LOG"
    # gh pr list ... -> numery z GH_PR_NUMBERS (po jednym w linii); gh pr merge N -s -> rc z GH_FAIL_FOR
    cat >"$_T/bin/gh" <<'S'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
if [[ "$1 $2" == "pr list" ]]; then
    [[ "${GH_LIST_RC:-0}" != 0 ]] && exit "$GH_LIST_RC"
    printf '%s' "${GH_PR_NUMBERS:-}"
    exit 0
fi
if [[ "$1 $2" == "pr checks" ]]; then
    echo "checks of $3"
    for f in ${GH_CHECKS_FAIL_FOR:-}; do [[ "$3" == "$f" ]] && exit 1; done
    for f in ${GH_CHECKS_PENDING_FOR:-}; do [[ "$3" == "$f" ]] && exit 8; done
    exit 0
fi
if [[ "$1 $2" == "pr merge" ]]; then
    for f in ${GH_FAIL_FOR:-}; do [[ "$3" == "$f" ]] && exit 1; done
    exit 0
fi
S
    chmod +x "$_T/bin/gh"
    PATH="$_T/bin:$PATH"
    unset GH_PR_NUMBERS GH_FAIL_FOR GH_LIST_RC GH_CHECKS_FAIL_FOR GH_CHECKS_PENDING_FOR HUB_MASS_MERGE_LIMIT
    _LOG=''
}

tearDown() {
    PATH="$_ORIG_PATH"
    rm -rf "$_T"
}

_merges() { grep '^pr merge' "$GH_LOG"; }

testMergesEveryOpenPrWithSquashInAscendingOrder() {
    export GH_PR_NUMBERS=$'205\n203\n204\n'
    hub_mass_merge
    assertEquals "rc" 0 $?
    assertEquals "kolejność rosnąca i flagi" $'pr merge 203 -s\npr merge 204 -s\npr merge 205 -s' "$(_merges)"
    assertContains "podsumowanie" "$_LOG" "INFO hub.mass_merge_summary 3 0"
}

testOrderIsNumericNotLexicographic() {
    export GH_PR_NUMBERS=$'100\n9\n20\n'
    hub_mass_merge
    assertEquals "9, 20, 100" $'pr merge 9 -s\npr merge 20 -s\npr merge 100 -s' "$(_merges)"
}

testNumbersPassedWithoutHash() {
    export GH_PR_NUMBERS=$'#12\n7\n'
    hub_mass_merge
    assertEquals "tylko czyste liczby" "pr merge 7 -s" "$(_merges)"
}

testListUsesJsonOpenStateAndLimit() {
    hub_mass_merge
    list="$(grep '^pr list' "$GH_LOG")"
    assertContains "stan open" "$list" "--state open"
    assertContains "domyślny limit" "$list" "--limit 100"
    assertContains "json" "$list" "--json number"
}

testLimitFromEnv() {
    HUB_MASS_MERGE_LIMIT=250 hub_mass_merge
    assertContains "limit z env" "$(grep '^pr list' "$GH_LOG")" "--limit 250"
}

testFailureOfOnePrDoesNotStopOthersAndReturns1() {
    export GH_PR_NUMBERS=$'3\n2\n1\n'
    GH_FAIL_FOR=2 hub_mass_merge
    assertEquals "rc" 1 $?
    assertEquals "wszystkie próby" 3 "$(_merges | wc -l)"
    assertContains "błąd PR 2" "$_LOG" "ERROR hub.mass_merge_failed 2"
    assertContains "podsumowanie" "$_LOG" "INFO hub.mass_merge_summary 2 1"
    assertContains "lista nieudanych" "$_LOG" "ERROR hub.mass_merge_failed_list 2"
}

testNoOpenPrsReturns0WithoutMerging() {
    export GH_PR_NUMBERS=''
    hub_mass_merge
    assertEquals "rc" 0 $?
    assertEquals "brak merge" "" "$(_merges)"
    assertContains "informacja" "$_LOG" "INFO hub.mass_merge_none"
}

testDryRunListsAndDoesNotMerge() {
    export GH_PR_NUMBERS=$'5\n4\n'
    hub_mass_merge --dry-run
    assertEquals "rc" 0 $?
    assertEquals "brak merge" "" "$(_merges)"
    assertContains "lista rosnąco" "$_LOG" "INFO hub.mass_merge_dry_run 4 5"
}

testShortDryRunFlag() {
    export GH_PR_NUMBERS=$'9\n'
    hub_mass_merge -n
    assertEquals "brak merge" "" "$(_merges)"
}

testHelpPrintsUsageAndCallsNothing() {
    hub_mass_merge -h
    assertEquals "rc" 0 $?
    assertContains "usage" "$_LOG" "MAN hub.mass_merge_usage"
    assertEquals "gh nie wołane" "" "$(cat "$GH_LOG")"
}

testUnknownOptionReturns2() {
    hub_mass_merge --nope
    assertEquals "rc" 2 $?
    assertContains "błąd" "$_LOG" "ERROR hub.mass_merge_unknown_option --nope"
    assertEquals "gh nie wołane" "" "$(cat "$GH_LOG")"
}

testListFailureReturns1WithoutMerging() {
    GH_LIST_RC=1 hub_mass_merge
    assertEquals "rc" 1 $?
    assertContains "błąd" "$_LOG" "ERROR hub.mass_merge_list_failed"
    assertEquals "brak merge" "" "$(_merges)"
}

testMissingGhReturns1() {
    # shellcheck disable=SC2123  # celowo: PATH bez gh
    PATH="$_T/empty" # katalog nie istnieje: brak gh (i innych poleceń; funkcja używa tylko builtinów)
    hub_mass_merge
    rc=$?
    PATH="$_T/bin:$_ORIG_PATH"
    assertEquals "rc" 1 "$rc"
    assertContains "błąd" "$_LOG" "ERROR hub.gh_missing"
}

testAliasHmmPointsToFunction() {
    grep -qE '^[[:space:]]*hmm[[:space:]]*=[[:space:]]*fun hub_mass_merge[[:space:]]*$' "$PROJECT_ROOT/git/aliases"
    assertEquals "alias hmm" 0 $?
}

testDispatcherAllowsFunctionViaGitFun() {
    # `git fun hub_mass_merge` przechodzi dispatcher (hub_*) - help nie woła gh
    out="$(SUPPRESS_SOURCING=1 GIT_CONFIGURATION_DIR="$PROJECT_ROOT/git" bash "$PROJECT_ROOT/git/git_functions.sh" hub_mass_merge --help 2>&1)"
    assertNotContains "nie odrzucone" "$out" "unknown_function"
}

_checks() { grep '^pr checks' "$GH_LOG"; }

testPrStatusChecksEveryOpenPrAscending() {
    export GH_PR_NUMBERS=$'12\n3\n7\n'
    out="$(hub_pr_status)"
    assertEquals "rc" 0 $?
    assertEquals "kolejność rosnąca" $'pr checks 3\npr checks 7\npr checks 12' "$(_checks)"
    assertContains "wynik gh na stdout" "$out" "checks of 7"
}

testPrStatusSummaryCountsPassedPendingAndFailed() {
    export GH_PR_NUMBERS=$'1\n2\n3\n4\n'
    export GH_CHECKS_FAIL_FOR="3" GH_CHECKS_PENDING_FOR="2"
    hub_pr_status >/dev/null
    assertEquals "rc 1 przy błędnym checku" 1 $?
    assertContains "podsumowanie" "$_LOG" "INFO hub.pr_status_summary 2 1 1"
    assertContains "lista błędnych" "$_LOG" "ERROR hub.pr_status_failed_list 3"
}

testPrStatusPendingIsNotAFailure() {
    export GH_PR_NUMBERS=$'5\n'
    export GH_CHECKS_PENDING_FOR="5"
    hub_pr_status >/dev/null
    assertEquals "rc" 0 $?
    assertContains "podsumowanie" "$_LOG" "INFO hub.pr_status_summary 0 1 0"
}

testPrStatusNoOpenPrs() {
    export GH_PR_NUMBERS=''
    hub_pr_status
    assertEquals "rc" 0 $?
    assertContains "info" "$_LOG" "INFO hub.pr_status_none"
    assertEquals "brak checks" "" "$(_checks)"
}

testPrStatusListFailureReturns1() {
    GH_LIST_RC=1 hub_pr_status
    assertEquals "rc" 1 $?
    assertContains "błąd" "$_LOG" "ERROR hub.mass_merge_list_failed"
}

testPrStatusHelpAndUnknownOption() {
    hub_pr_status -h
    assertEquals "help rc" 0 $?
    assertContains "usage" "$_LOG" "MAN hub.pr_status_usage"
    hub_pr_status --nope
    assertEquals "rc" 2 $?
    assertContains "błąd" "$_LOG" "ERROR hub.pr_status_unknown_option --nope"
    assertEquals "gh nie wołane" "" "$(cat "$GH_LOG")"
}

testAliasHstPointsToFunction() {
    grep -qE '^[[:space:]]*hst[[:space:]]*=[[:space:]]*fun hub_pr_status[[:space:]]*$' "$PROJECT_ROOT/git/aliases"
    assertEquals "alias hst" 0 $?
}

testMassMergeAndPrStatusShareTheListHelper() {
    # listowanie PR tylko w _hub_open_prs (kod bez komentarzy)
    assertEquals "jedno wywołanie gh pr list" 1 "$(grep -v '^[[:space:]]*#' "$PROJECT_ROOT/git/hub_functions.sh" | grep -c 'gh pr list')"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
