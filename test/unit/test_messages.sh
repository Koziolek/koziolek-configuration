#!/usr/bin/env bash
# Testy jednostkowe: komunikaty z tablic MSG_* (bash/functions.d/005_function_messages.sh)
# i funkcje log_<poziom> korzystające z nich (bash/functions.d/010_function_log.sh)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/005_function_messages.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"

_ORIG_LOG_MESSAGE="$(declare -f log_message)"

setUp() {
    _FIXTURE="$(mktemp -d)"
    export MESSAGES_DIR="$_FIXTURE"
    unset MESSAGES_LANG LC_ALL LC_MESSAGES MESSAGES_LOADED
    export LANG=C

    cat > "$_FIXTURE/messages.pl.sh" <<'PL'
MSG_INFO[k.info]="polskie info %s"
MSG_INFO[k.only_pl]="tylko po polsku"
MSG_WARN[k.warn]="polskie ostrzeżenie %s/%s"
MSG_ERROR[k.error]="polski błąd"
MSG_DEBUG[k.debug]="polski debug"
MSG_MAN[k.man]="polska pomoc"
MSG_WARN[k.only_warn]="klucz tylko w WARN"
PL
    cat > "$_FIXTURE/messages.en.sh" <<'EN'
MSG_INFO[k.info]="english info %s"
MSG_WARN[k.warn]="english warning %s/%s"
MSG_ERROR[k.error]="english error"
EN
    # log_message: przechwytuje argumenty (gotowy komunikat), bez formatowania
    log_message() { _LM_ARGS=("$@"); _LM_COUNT=$#; }
}

tearDown() {
    rm -rf "$_FIXTURE"
    eval "$_ORIG_LOG_MESSAGE"
}

# --- wybór języka ---

testLangDefaultsToPolishForCAndEmpty() {
    LANG=C;     assertEquals pl "$(messages_lang)"
    LANG=POSIX; assertEquals pl "$(messages_lang)"
    LANG='';    assertEquals pl "$(messages_lang)"
}

testLangFromLocaleStripsRegionAndCharset() {
    LANG=en_GB.UTF-8; assertEquals en "$(messages_lang)"
    LANG=pl_PL.UTF-8; assertEquals pl "$(messages_lang)"
    LANG=de;          assertEquals de "$(messages_lang)"
}

testLangPrecedence() {
    LANG=de_DE.UTF-8 LC_MESSAGES=fr_FR.UTF-8 LC_ALL=en_US.UTF-8
    assertEquals 'LC_ALL > LC_MESSAGES > LANG' en "$(messages_lang)"
    unset LC_ALL
    assertEquals 'LC_MESSAGES > LANG' fr "$(messages_lang)"
    unset LC_MESSAGES
    assertEquals 'LANG' de "$(messages_lang)"
    MESSAGES_LANG=pl LC_ALL=en_US.UTF-8
    assertEquals 'MESSAGES_LANG wygrywa ze wszystkim' pl "$(messages_lang)"
}

# --- ładowanie ---

testLoadingIsLazy() {
    assertNull 'przed pierwszym użyciem nic nie załadowane' "${MESSAGES_LOADED:-}"
    log_info k.info x
    assertEquals 'po pierwszym log_info załadowane' 1 "$MESSAGES_LOADED"
}

testUnknownLanguageFallsBackToPolish() {
    MESSAGES_LANG=de
    log_info k.info x
    assertEquals 'polskie info x' "${_LM_ARGS[1]}"
}

testKeyMissingInSelectedLanguageFallsBackToPolish() {
    MESSAGES_LANG=en
    log_info k.only_pl
    assertEquals 'tylko po polsku' "${_LM_ARGS[1]}"
}

# --- log_<poziom>: tylko własna tablica, gotowy komunikat do log_message ---

testEachLevelUsesOwnArrayInPolish() {
    log_debug k.debug;       assertEquals debug "${_LM_ARGS[0]}"; assertEquals 'polski debug'  "${_LM_ARGS[1]}"
    log_info  k.info A;      assertEquals info  "${_LM_ARGS[0]}"; assertEquals 'polskie info A' "${_LM_ARGS[1]}"
    log_warn  k.warn A B;    assertEquals warn  "${_LM_ARGS[0]}"; assertEquals 'polskie ostrzeżenie A/B' "${_LM_ARGS[1]}"
    log_error k.error 2>/dev/null >/dev/null
    assertEquals error "${_LM_ARGS[0]}"; assertEquals 'polski błąd' "${_LM_ARGS[1]}"
    log_man   k.man;         assertEquals man   "${_LM_ARGS[0]}"; assertEquals 'polska pomoc' "${_LM_ARGS[1]}"
}

testEnglishOverlay() {
    MESSAGES_LANG=en
    log_info k.info A;    assertEquals 'english info A' "${_LM_ARGS[1]}"
    log_warn k.warn A B;  assertEquals 'english warning A/B' "${_LM_ARGS[1]}"
}

testLogMessageReceivesExactlyLevelAndFinishedMessage() {
    log_info k.info A
    assertEquals 'log_message dostaje poziom i jeden gotowy komunikat' 2 "$_LM_COUNT"
}

testKeyFromOtherLevelArrayIsNotResolved() {
    # k.only_warn istnieje tylko w MSG_WARN — log_info ma go potraktować jak dosłowny tekst
    log_info k.only_warn
    assertEquals 'k.only_warn' "${_LM_ARGS[1]}"
    log_warn k.only_warn
    assertEquals 'klucz tylko w WARN' "${_LM_ARGS[1]}"
}

# --- zgodność wstecz i odporność ---

testLiteralTextPassesThroughUnchanged() {
    log_info "zwykły tekst" "druga część"
    assertEquals 'zwykły tekst' "${_LM_ARGS[1]}"
    assertEquals 'druga część'  "${_LM_ARGS[2]}"
    assertEquals 3 "$_LM_COUNT"
}

testNoArgumentsStillGoesToLogMessage() {
    log_info
    assertEquals 'log_message wołany bez komunikatu (NOTHING TO LOG po jego stronie)' 1 "$_LM_COUNT"
}

testPlaceholderValuesWithSpecialCharsAreData() {
    log_info k.info '100% $(echo x) `id` %s'
    assertEquals 'polskie info 100% $(echo x) `id` %s' "${_LM_ARGS[1]}"
}

# --- integracja z prawdziwym log_message i repozytoryjnymi plikami ---

testRealMessageFilesDefineAllLevelArrays() {
    unset MESSAGES_DIR
    messages_load
    assertEquals 'Brak zmian' "${MSG_INFO[git.no_changes]}"
    assertNotNull 'MSG_WARN ma klucze' "${!MSG_WARN[*]}"
    assertNotNull 'MSG_ERROR ma klucze' "${!MSG_ERROR[*]}"
    assertNotNull 'MSG_MAN ma klucze' "${!MSG_MAN[*]}"
}

testEveryPolishKeyHasEnglishTranslation() {
    unset MESSAGES_DIR
    local lvl key missing=''
    for lvl in DEBUG INFO WARN ERROR MAN; do
        for key in $(grep -oE "^MSG_${lvl}\[[^]]+\]" "$PROJECT_ROOT/bash/messages/messages.pl.sh"); do
            grep -qF "$key" "$PROJECT_ROOT/bash/messages/messages.en.sh" || missing+="$key "
        done
    done
    assertEquals 'klucze bez tłumaczenia en' '' "$missing"
}

testRealLogInfoPrintsLocalizedText() {
    unset MESSAGES_DIR
    eval "$_ORIG_LOG_MESSAGE"
    assertContains 'INFO: Brak zmian' "$(MESSAGES_LANG=pl log_info git.no_changes)" 'INFO: Brak zmian'
    assertContains 'INFO: No changes' "$(MESSAGES_LANG=en messages_load; log_info git.no_changes)" 'INFO: No changes'
}

# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
