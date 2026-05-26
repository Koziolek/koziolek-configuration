#!/usr/bin/env bash
# Testy jednostkowe: bash/functions.d/010_function_log.sh

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Zerowe zmienne kolorów — wyjście przewidywalne, bez sekwencji ANSI
export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"

# ---------------------------------------------------------------------------

testLogInfoOutputFormat() {
    local output
    output=$(log_info "wiadomość testowa")
    assertContains 'log_info musi zawierać tag INFO:' "$output" 'INFO:'
    assertContains 'log_info musi zawierać treść' "$output" 'wiadomość testowa'
}

testLogWarnOutputFormat() {
    local output
    output=$(log_warn "ostrzeżenie testowe")
    assertContains 'log_warn musi zawierać tag WARN:' "$output" 'WARN:'
    assertContains 'log_warn musi zawierać treść' "$output" 'ostrzeżenie testowe'
}

testLogDebugOutputFormat() {
    local output
    output=$(log_debug "debug testowy")
    assertContains 'log_debug musi zawierać tag DEBUG:' "$output" 'DEBUG:'
    assertContains 'log_debug musi zawierać treść' "$output" 'debug testowy'
}

testLogErrorOutputFormat() {
    local output
    # log_error woła też print_stack_trace — całość idzie na stdout
    output=$(log_error "błąd testowy" 2>&1)
    assertContains 'log_error musi zawierać tag ERROR:' "$output" 'ERROR:'
    assertContains 'log_error musi zawierać treść' "$output" 'błąd testowy'
}

testLogErrorIncludesStackTrace() {
    local output
    output=$(log_error "test stosu" 2>&1)
    assertContains 'log_error musi dołączyć Stack trace' "$output" 'Stack trace:'
}

testLogManPrintsMessageWithoutTag() {
    local output
    output=$(log_man "tekst pomocy")
    assertContains 'log_man musi zawierać treść' "$output" 'tekst pomocy'
    # log_man nie dodaje żadnego tagu — sprawdź że nie ma INFO/WARN/ERROR
    assertNotContains 'log_man nie może zawierać INFO:'  "$output" 'INFO:'
    assertNotContains 'log_man nie może zawierać ERROR:' "$output" 'ERROR:'
}

testLogErrorDoesNotExitScript() {
    # log_error nie może przerywać skryptu przez exit/return niezerowym kodem
    log_error "test" >/dev/null 2>&1
    assertTrue 'skrypt działa po wywołaniu log_error' true
}

testLogMessageEmptyLevelProducesNothingToLog() {
    local output
    output=$(log_message "" "jakaś treść" 2>&1)
    assertContains 'puste argumenty muszą produkować NOTHING TO LOG' "$output" 'NOTHING TO LOG'
}

testLogInfoMultipleArgs() {
    local output
    output=$(log_info "część pierwsza" "część druga")
    assertContains 'log_info musi obsługiwać wiele argumentów — część pierwsza' "$output" 'część pierwsza'
    assertContains 'log_info musi obsługiwać wiele argumentów — część druga'   "$output" 'część druga'
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
