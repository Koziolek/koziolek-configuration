#!/usr/bin/env bash
# Testy jednostkowe: bash/functions.d/160_cron.sh
# `crontab` jest mockiem na pliku (_CT_FILE) — nic nie dotyka prawdziwego crontaba.
# Kluczowa gwarancja: funkcje modyfikujące nigdy nie wołają `crontab -u` (cudze zadania tylko do odczytu).

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export MESSAGES_LANG=pl
export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/160_cron.sh"

setUp() {
    _TMP="$(mktemp -d)"
    _CT_FILE="$_TMP/crontab"      # „crontab” bieżącego użytkownika
    _CT_CALLS="$_TMP/calls"       # argumenty wszystkich wywołań crontab
    _LOG="$_TMP/log"              # zalogowane komunikaty: "poziom klucz args"
    : >"$_CT_CALLS"
    : >"$_LOG"
    export CRON_LOG_DIR="$_TMP/logs"
    export CRON_DAEMON_CHECK=0
    export CRON_SPOOL_DIRS="" CRON_SYSTEM_FILES="" CRON_SYSTEM_DIRS="" CRON_PERIODIC_DIRS=""
    unset CRON_USE_SUDO CRON_ASSUME_YES VISUAL EDITOR

    crontab() {
        echo "$*" >>"$_CT_CALLS"
        case "${1:-}" in
        -l) [ -f "$_CT_FILE" ] || return 1; cat "$_CT_FILE" ;;
        -r) rm -f "$_CT_FILE" ;;
        -u) return 99 ;;
        *) cp "$1" "$_CT_FILE" ;;
        esac
    }
    log_info() { echo "info $*" >>"$_LOG"; }
    log_warn() { echo "warn $*" >>"$_LOG"; }
    log_error() { echo "error $*" >>"$_LOG"; }
    log_man() { echo "man $*" >>"$_LOG"; }
}

tearDown() {
    rm -rf "$_TMP"
}

_has_log() { grep -qF -- "$1" "$_LOG"; }

# --- cron_schedule ---------------------------------------------------------

testScheduleReadyPassesThrough() {
    assertEquals "*/5 * * * *" "$(cron_schedule '*/5 * * * *')"
    assertEquals "@daily" "$(cron_schedule '@daily')"
    assertEquals "0 3 * * mon-fri" "$(cron_schedule '0 3 * * mon-fri')"
}

testScheduleRejectsOutOfRange() {
    cron_schedule '60 * * * *' >/dev/null; assertEquals 1 $?
    cron_schedule '* 24 * * *' >/dev/null; assertEquals 1 $?
    cron_schedule '* * 0 * *' >/dev/null; assertEquals 1 $?
    cron_schedule '* * * 13 *' >/dev/null; assertEquals 1 $?
    cron_schedule '* * * * 8' >/dev/null; assertEquals 1 $?
    cron_schedule '*/0 * * * *' >/dev/null; assertEquals 1 $?
    cron_schedule '5-2 * * * *' >/dev/null; assertEquals 1 $?
    cron_schedule 'bzdura' >/dev/null; assertEquals 1 $?
}

testSchedulePolish() {
    assertEquals "*/5 * * * *" "$(cron_schedule 'co 5 min')"
    assertEquals "* * * * *" "$(cron_schedule 'co minutę')"
    assertEquals "0 * * * *" "$(cron_schedule 'co godzinę')"
    assertEquals "0 */2 * * *" "$(cron_schedule 'co 2 godziny')"
    assertEquals "0 3 * * *" "$(cron_schedule 'codziennie o 03:00')"
    assertEquals "30 8 * * *" "$(cron_schedule 'codziennie o 8:30')"
    assertEquals "0 0 * * *" "$(cron_schedule 'codziennie')"
    assertEquals "0 8 * * 1" "$(cron_schedule 'w poniedziałek o 08:00')"
    assertEquals "15 22 * * 5" "$(cron_schedule 'co piątek o 22:15')"
    assertEquals "0 6 1 * *" "$(cron_schedule 'co miesiąc o 6:00')"
    assertEquals "@reboot" "$(cron_schedule 'przy starcie')"
}

testScheduleEnglish() {
    assertEquals "*/10 * * * *" "$(cron_schedule 'every 10 minutes')"
    assertEquals "0 * * * *" "$(cron_schedule 'hourly')"
    assertEquals "0 3 * * *" "$(cron_schedule 'daily at 03:00')"
    assertEquals "0 8 * * 1" "$(cron_schedule 'on monday at 08:00')"
    assertEquals "@reboot" "$(cron_schedule 'at boot')"
}

testScheduleRejectsBadTime() {
    cron_schedule 'codziennie o 25:00' >/dev/null; assertEquals 1 $?
    cron_schedule 'codziennie o 10:61' >/dev/null; assertEquals 1 $?
    cron_schedule 'co 0 min' >/dev/null; assertEquals 1 $?
    cron_schedule 'co 60 min' >/dev/null; assertEquals 1 $?
}

# --- cron_add --------------------------------------------------------------

testAddCreatesMarkedBlockWithLogRedirect() {
    cron_add "co 5 min" "/usr/local/bin/backup.sh --full"
    assertEquals 0 $?
    assertEquals "# koziolek-cron:BEGIN" "$(sed -n 1p "$_CT_FILE")"
    assertTrue "SHELL w bloku" "grep -q '^SHELL=/bin/bash$' '$_CT_FILE'"
    assertTrue "PATH w bloku" "grep -q '^PATH=' '$_CT_FILE'"
    assertTrue "wpis z logiem" "grep -qF '*/5 * * * * /usr/local/bin/backup.sh --full >> $CRON_LOG_DIR/backup.sh.log 2>&1' '$_CT_FILE'"
    assertEquals "# koziolek-cron:END" "$(tail -n1 "$_CT_FILE")"
    assertTrue "katalog logów utworzony" "[ -d '$CRON_LOG_DIR' ]"
    assertTrue "komunikat" "_has_log 'info cron.added'"
}

testAddIsIdempotent() {
    cron_add "@daily" "backup.sh"
    cron_add "@daily" "backup.sh"
    assertEquals 1 "$(grep -c '^@daily backup.sh' "$_CT_FILE")"
    assertEquals 1 "$(grep -c 'koziolek-cron:BEGIN' "$_CT_FILE")"
    assertTrue "info już istnieje" "_has_log 'info cron.already_exists'"
}

testAddSecondEntryGoesIntoExistingBlock() {
    cron_add "@daily" "one.sh"
    cron_add "@hourly" "two.sh"
    assertEquals 1 "$(grep -c 'koziolek-cron:BEGIN' "$_CT_FILE")"
    assertEquals 1 "$(grep -c 'koziolek-cron:END' "$_CT_FILE")"
    local end_line two_line
    end_line="$(grep -n 'koziolek-cron:END' "$_CT_FILE" | cut -d: -f1)"
    two_line="$(grep -n '^@hourly two.sh' "$_CT_FILE" | cut -d: -f1)"
    assertTrue "drugi wpis przed END" "[ '$two_line' -lt '$end_line' ]"
}

testAddKeepsForeignCrontabUntouched() {
    printf '%s\n' '# moje' 'MAILTO=me@example.com' '0 1 * * * stare.sh' >"$_CT_FILE"
    cron_add "@daily" "nowe.sh"
    assertEquals "# moje" "$(sed -n 1p "$_CT_FILE")"
    assertEquals "MAILTO=me@example.com" "$(sed -n 2p "$_CT_FILE")"
    assertEquals "0 1 * * * stare.sh" "$(sed -n 3p "$_CT_FILE")"
    assertTrue "nowy wpis dopisany" "grep -q '^@daily nowe.sh' '$_CT_FILE'"
}

testAddNoLogOmitsRedirect() {
    cron_add --no-log "@daily" "cleanup.sh"
    assertEquals "@daily cleanup.sh" "$(grep '^@daily' "$_CT_FILE")"
}

testAddCustomName() {
    cron_add -n nocny "@daily" "/opt/x/run.sh"
    assertTrue "log pod własną nazwą" "grep -qF '$CRON_LOG_DIR/nocny.log' '$_CT_FILE'"
}

testAddRejectsBadName() {
    cron_add -n 'zła nazwa/../x' "@daily" "x.sh"
    assertEquals 1 $?
    assertTrue "komunikat" "_has_log 'error cron.bad_name'"
    assertFalse "crontab nietknięty" "[ -f '$_CT_FILE' ]"
}

testAddRejectsBadSchedule() {
    cron_add "kiedyś tam" "x.sh"
    assertEquals 1 $?
    assertTrue "komunikat" "_has_log 'error cron.bad_schedule'"
    assertFalse "crontab nietknięty" "[ -f '$_CT_FILE' ]"
}

testAddEscapesPercent() {
    cron_add --no-log "@daily" "date +%F"
    assertEquals '@daily date +\%F' "$(grep '^@daily' "$_CT_FILE")"
}

testAddUsageWhenTooFewArgs() {
    cron_add "@daily"
    assertEquals 1 $?
    assertTrue "usage" "_has_log 'man cron.add_usage'"
}

testAddWarnsWithoutDaemon() {
    CRON_DAEMON_CHECK=1
    pgrep() { return 1; }
    cron_add "@daily" "x.sh"
    assertEquals 0 $?
    assertTrue "ostrzeżenie o demonie" "_has_log 'warn cron.no_daemon'"
    unset -f pgrep
}

# --- cron_remove -----------------------------------------------------------

_seed_three() {
    printf '%s\n' '# własny komentarz' '0 1 * * * alfa.sh' '0 2 * * * beta.sh' '0 3 * * * gamma.sh' >"$_CT_FILE"
}

testRemoveByNumber() {
    _seed_three
    cron_remove 2
    assertEquals 0 $?
    assertFalse "beta usunięta" "grep -q beta.sh '$_CT_FILE'"
    assertTrue "alfa zostaje" "grep -q alfa.sh '$_CT_FILE'"
    assertTrue "gamma zostaje" "grep -q gamma.sh '$_CT_FILE'"
    assertTrue "komentarz zostaje" "grep -q 'własny komentarz' '$_CT_FILE'"
}

testRemoveByPattern() {
    _seed_three
    cron_remove gamma
    assertFalse "gamma usunięta" "grep -q gamma.sh '$_CT_FILE'"
    assertTrue "alfa zostaje" "grep -q alfa.sh '$_CT_FILE'"
}

testRemoveAmbiguousPatternRefuses() {
    _seed_three
    cron_remove ' * * * '
    assertEquals 1 $?
    assertTrue "komunikat" "_has_log 'error cron.ambiguous'"
    assertEquals 3 "$(grep -c '\.sh' "$_CT_FILE")"
}

testRemoveUnknown() {
    _seed_three
    cron_remove nieistnieje
    assertEquals 1 $?
    assertTrue "komunikat" "_has_log 'error cron.no_such_entry'"
    cron_remove 99
    assertEquals 1 $?
}

testRemoveLastEntryDropsEmptyBlock() {
    cron_add "@daily" "jedyny.sh"
    cron_remove jedyny
    assertFalse "blok zniknął (crontab usunięty)" "[ -f '$_CT_FILE' ]"
}

testRemoveKeepsForeignLinesWhenBlockEmptied() {
    printf '%s\n' '0 1 * * * stare.sh' >"$_CT_FILE"
    cron_add "@daily" "nowe.sh"
    cron_remove nowe
    assertEquals "0 1 * * * stare.sh" "$(cat "$_CT_FILE")"
}

testRemoveUsage() {
    cron_remove
    assertEquals 1 $?
    assertTrue "usage" "_has_log 'man cron.remove_usage'"
}

# --- cron_edit -------------------------------------------------------------

_make_editor() {  # _make_editor <zawartość docelowa> — edytor-mock nadpisujący plik
    local content="$1"
    _EDITOR="$_TMP/editor.sh"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q > "$1"\n' "$content" >"$_EDITOR"
    chmod +x "$_EDITOR"
    export VISUAL="$_EDITOR"
}

testEditSavesValidContent() {
    printf '%s\n' '0 1 * * * stare.sh' >"$_CT_FILE"
    _make_editor '0 5 * * 1-5 nowe.sh'
    cron_edit
    assertEquals 0 $?
    assertEquals "0 5 * * 1-5 nowe.sh" "$(cat "$_CT_FILE")"
    assertTrue "info" "_has_log 'info cron.saved'"
}

testEditRejectsInvalidSyntaxWithoutSaving() {
    printf '%s\n' '0 1 * * * stare.sh' >"$_CT_FILE"
    _make_editor '99 5 * * * zepsute.sh'
    export CRON_ASSUME_YES=1
    cron_edit
    assertEquals 1 $?
    assertEquals "0 1 * * * stare.sh" "$(cat "$_CT_FILE")"
    assertTrue "numer błędnej linii" "_has_log 'error cron.invalid_line 1 99 5 * * * zepsute.sh'"
    assertTrue "przerwanie" "_has_log 'error cron.edit_aborted'"
}

testEditRejectsGarbageLine() {
    : >"$_CT_FILE"
    printf '%s\n' '# coś' >"$_CT_FILE"
    _make_editor 'to nie jest crontab'
    export CRON_ASSUME_YES=1
    cron_edit
    assertEquals 1 $?
    assertEquals "# coś" "$(cat "$_CT_FILE")"
}

testEditNoChanges() {
    printf '%s\n' '0 1 * * * stare.sh' >"$_CT_FILE"
    export VISUAL=true
    cron_edit
    assertEquals 0 $?
    assertTrue "info o braku zmian" "_has_log 'info cron.no_changes'"
}

testEditAllowsVariablesAndMacros() {
    : >"$_CT_FILE"
    _make_editor '@reboot echo hi'
    cron_edit
    assertEquals 0 $?
    assertEquals "@reboot echo hi" "$(cat "$_CT_FILE")"
}

# --- cron_list -------------------------------------------------------------

testListOwnNumbered() {
    _seed_three
    cron_list -o
    assertTrue "nagłówek" "_has_log 'info cron.list_own_header'"
    assertTrue "numer 1" "grep -q 'man   1  0 1 \* \* \* alfa.sh' '$_LOG'"
    assertTrue "numer 3" "grep -q 'man   3  0 3 \* \* \* gamma.sh' '$_LOG'"
    assertFalse "komentarz bez numeru" "grep -q 'własny komentarz' '$_LOG'"
    assertFalse "-o pomija cudze" "_has_log 'cron.list_others_header'"
}

testListEmptyOwn() {
    cron_list -o
    assertTrue "komunikat o pustym" "_has_log 'info cron.list_own_empty'"
}

testListShowsOtherUsersAndSystem() {
    local me
    me="$(id -un)"
    mkdir -p "$_TMP/spool" "$_TMP/cron.d" "$_TMP/daily"
    printf '%s\n' '0 4 * * * jakub.sh' >"$_TMP/spool/jakub"
    printf '%s\n' '0 9 * * * moje-w-spoolu.sh' >"$_TMP/spool/$me"
    printf '%s\n' '17 * * * * root run-parts /etc/cron.hourly' >"$_TMP/crontab-system"
    printf '%s\n' '*/10 * * * * www-data php job.php' >"$_TMP/cron.d/web"
    : >"$_TMP/daily/logrotate"
    : >"$_TMP/daily/.placeholder"
    CRON_SPOOL_DIRS="$_TMP/spool" CRON_SYSTEM_FILES="$_TMP/crontab-system" \
        CRON_SYSTEM_DIRS="$_TMP/cron.d" CRON_PERIODIC_DIRS="$_TMP/daily" cron_list
    assertTrue "nagłówek cudzych" "_has_log 'info cron.list_others_header'"
    assertTrue "zadanie innego użytkownika" "grep -q 'jakub.sh' '$_LOG'"
    assertFalse "własny spool pominięty (jest wyżej)" "grep -q 'moje-w-spoolu' '$_LOG'"
    assertTrue "plik systemowy" "grep -q 'run-parts' '$_LOG'"
    assertTrue "cron.d" "grep -q 'php job.php' '$_LOG'"
    assertTrue "skrypt okresowy" "grep -q 'logrotate' '$_LOG'"
    assertFalse ".placeholder pominięty" "grep -q 'placeholder' '$_LOG'"
}

testListReportsUnreadableSources() {
    [ "$(id -u)" = 0 ] && startSkipping
    mkdir -p "$_TMP/spool"
    printf '%s\n' '0 4 * * * tajne.sh' >"$_TMP/spool/sekret"
    chmod 000 "$_TMP/spool/sekret"
    CRON_SPOOL_DIRS="$_TMP/spool" cron_list
    assertTrue "licznik nieczytelnych" "_has_log 'info cron.list_unreadable 1'"
    assertFalse "treść niewidoczna" "grep -q 'tajne.sh' '$_LOG'"
    chmod 600 "$_TMP/spool/sekret"
}

testListNoOthers() {
    cron_list
    assertTrue "komunikat" "_has_log 'info cron.list_no_others'"
}

# --- zasada: cudzych zadań nie zmieniamy -----------------------------------

testNeverCallsCrontabWithUserFlag() {
    _seed_three
    cron_list >/dev/null
    cron_add "@daily" "x.sh" >/dev/null
    cron_remove alfa >/dev/null
    export VISUAL=true
    cron_edit >/dev/null
    assertFalse "żadnego crontab -u" "grep -qE '(^| )-u( |$)' '$_CT_CALLS'"
}

testSourceDefinesNoCrontabUserFlag() {
    assertFalse "kod nie zawiera crontab -u" "grep -vE '^[[:space:]]*#' '$PROJECT_ROOT/bash/functions.d/160_cron.sh' | grep -qE 'crontab +(-[a-z]+ +)*-u'"
}

testMissingCrontabBinary() {
    unset -f crontab
    PATH=/nonexistent cron_add "@daily" "x.sh"
    assertEquals 1 $?
    assertTrue "komunikat" "_has_log 'error cron.no_crontab'"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
