#!/usr/bin/env bash
# Testy jednostkowe: bash/functions.d/155_function_gpg_card.sh (GPG na karcie OpenPGP).
# gpg jest mockowany (skrypt w PATH) — kontener testowy nie ma karty. Mock czyta
# fixture statusu karty z $MOCK_CARD ("none" = brak karty) i symuluje keyring
# plikiem-markerem $MOCK_STATE/have_pub (tworzonym przez --fetch-keys/--recv-keys
# gdy źródło jest "dobre"). Każde wywołanie loguje argumenty do $MOCK_STATE/calls.
# git jest prawdziwy, z HOME w katalogu tymczasowym — sprawdzamy realny ~/.gitconfig.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

SIG_FPR='AAAA1111BBBB2222CCCC3333DDDD4444EEEE5555'
PRIMARY_FPR='9999888877776666555544443333222211110000'

_BIN=''
_FIX=''
oneTimeSetUp() {
    _BIN="$(mktemp -d)"
    _FIX="$(mktemp -d)"

    # Fixture zbliżona do realnego `gpg --card-status --with-colons` (gpg 2.4, YubiKey 5).
    # URL z ':' uciekniętym jako \x3a — tak robi gpg w trybie colons.
    cat > "$_FIX/card_ok" <<EOF
Reader:1050:0407:X:0:
version:0304:
vendor:0006:Yubico:
serial:12345678:
name:Koziolek::
lang::
salutation::
url:https\\x3a//example.test/key.asc:
login::
forcepin:1:::
keyattr:1:22:ed25519:
keyattr:2:18:cv25519:
keyattr:3:22:ed25519:
maxpinlen:127:127:127:
pinretry:3:0:3:
sigcount:42:::
cafpr::::
fpr:${SIG_FPR,,}:FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000:1111000011110000111100001111000011110000:
fprtime:1700000000:1700000000:1700000000:
EOF
    # Karta bez URL i z pustym slotem podpisu
    sed -e 's/^url:.*/url::/' "$_FIX/card_ok" > "$_FIX/card_nourl"
    sed -e 's/^fpr:.*/fpr::::/' "$_FIX/card_ok" > "$_FIX/card_empty"

    cat > "$_BIN/gpg" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_STATE/calls"
case "$*" in
  "--card-status --with-colons")
    [ "$MOCK_CARD" = none ] && { echo "gpg: selecting card failed: No such device" >&2; exit 2; }
    cat "$MOCK_CARD" ;;
  "--card-status")
    [ "$MOCK_CARD" = none ] && exit 2
    echo "Reader ...: Yubico YubiKey" ;;
  "--list-keys "*|"--with-colons --list-keys "*)
    [ -e "$MOCK_STATE/have_pub" ] || exit 2
    echo "pub:u:255:22:9999888877776666:1700000000:::u:::scESC:"
    echo "fpr:::::::::9999888877776666555544443333222211110000:" ;;
  "--fetch-keys "*)
    [ "${2}" = "${MOCK_GOOD_SRC:-}" ] && touch "$MOCK_STATE/have_pub"
    exit 0 ;;
  "--keyserver "*" --recv-keys "*)
    [ "${MOCK_GOOD_SRC:-}" = keyserver ] && touch "$MOCK_STATE/have_pub"
    exit 0 ;;
  "--import-ownertrust")
    cat > "$MOCK_STATE/ownertrust" ;;
  "--local-user "*" --clearsign")
    cat >/dev/null; echo "-----BEGIN PGP SIGNED MESSAGE-----" ;;
esac
exit 0
MOCK
    chmod +x "$_BIN/gpg"
    printf '#!/bin/sh\necho "gpgconf $*" >> "$MOCK_STATE/calls"\n' > "$_BIN/gpgconf"
    chmod +x "$_BIN/gpgconf"
}
oneTimeTearDown() { rm -rf "$_BIN" "$_FIX"; }

_STATE=''
_HOME=''
setUp() {
    _STATE="$(mktemp -d)"
    _HOME="$(mktemp -d)"
}
tearDown() { rm -rf "$_STATE" "$_HOME"; }

# _run <karta: fixture|none> <fn-wywołanie...>
_run() {
    local card="$1"; shift
    [ "$card" = none ] || card="$_FIX/$card"
    # cd do izolowanego HOME: `git config --global` mimo --global wciąż próbuje
    # rozpoznać repo w CWD — w kontenerze CWD to zamontowany worktree z .git
    # wskazującym na ścieżkę hosta (poza kontenerem), co wywala "not a git
    # repository" i przerywa zapis configu. Poza jakimkolwiek repo tego nie ma.
    HOME="$_HOME" MOCK_STATE="$_STATE" MOCK_CARD="$card" PATH="$_BIN:$PATH" \
        bash --norc --noprofile -c "
            cd '$_HOME' || exit 1
            export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
            export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
            unset GPG_PUBKEY_URL GPG_KEYSERVER GNUPGHOME
            . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh'
            . '$PROJECT_ROOT/bash/functions.d/155_function_gpg_card.sh'
            $*
        "
}

# Subshell + cd do $_HOME: jak w _run — `git config --global` mimo --global
# wciąż próbuje rozpoznać repo w CWD, a w kontenerze CWD (zamontowany worktree)
# ma .git wskazujący na ścieżkę hosta niedostępną w kontenerze.
_gitcfg() { (cd "$_HOME" && HOME="$_HOME" git config --global --get "$1"); }

# --- parsowanie ---------------------------------------------------------------

testSigningFprIsFirstFprFieldUppercased() {
    local out
    out=$(_run card_ok '_gpg_card_signing_fpr "$(cat '"$_FIX/card_ok"')"')
    assertEquals "$SIG_FPR" "$out"
}

testSigningFprEmptyForEmptySlot() {
    local out
    out=$(_run card_empty '_gpg_card_signing_fpr "$(cat '"$_FIX/card_empty"')"')
    assertEquals '' "$out"
}

testCardUrlUnescapesColon() {
    local out
    out=$(_run card_ok '_gpg_card_field url "$(cat '"$_FIX/card_ok"')"')
    assertEquals 'https://example.test/key.asc' "$out"
}

# --- zależności / brak karty ---------------------------------------------------

testCheckDepsFailsWithoutGpg() {
    local out rc=0 bash_bin
    bash_bin="$(command -v bash)"
    out=$(PATH='' "$bash_bin" --norc --noprofile -c "
            . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh'
            . '$PROJECT_ROOT/bash/functions.d/155_function_gpg_card.sh'
            _gpg_card_check_deps
        " 2>&1) || rc=$?
    assertNotEquals 0 "$rc"
    assertContains "$out" 'brakujące zależności'
}

testSetupFailsWithoutCardAndTouchesNothing() {
    local out rc=0
    out=$(_run none gpg_git_setup 2>&1) || rc=$?
    assertNotEquals 'brak karty musi dać błąd' 0 "$rc"
    assertContains "$out" 'nie widzę karty OpenPGP'
    assertNull 'gitconfig nie może dostać signingkey' "$(_gitcfg user.signingkey)"
    assertNull 'gitconfig nie może włączyć gpgsign' "$(_gitcfg commit.gpgsign)"
}

testSetupFailsWithEmptySigningSlot() {
    local out rc=0
    out=$(_run card_empty gpg_git_setup 2>&1) || rc=$?
    assertNotEquals 0 "$rc"
    assertContains "$out" 'slot podpisu na karcie jest pusty'
    assertNull "$(_gitcfg commit.gpgsign)"
}

# --- import klucza publicznego --------------------------------------------------

testImportUsesUrlStoredOnCardFirst() {
    MOCK_GOOD_SRC='https://example.test/key.asc' _run card_ok gpg_card_import_pubkey >/dev/null 2>&1
    assertEquals 0 $?
    assertTrue 'fetch z URL karty' "grep -qF -- '--fetch-keys https://example.test/key.asc' '$_STATE/calls'"
    assertFalse 'nie powinien iść dalej do GitHuba' "grep -qF 'github.com' '$_STATE/calls'"
    assertEquals 'ownertrust ultimate dla klucza głównego' "${PRIMARY_FPR}:6:" "$(cat "$_STATE/ownertrust")"
}

testImportFallsBackToGithubWhenCardHasNoUrl() {
    MOCK_GOOD_SRC='https://github.com/Koziolek.gpg' _run card_nourl gpg_card_import_pubkey >/dev/null 2>&1
    assertEquals 0 $?
    assertTrue "grep -qF -- '--fetch-keys https://github.com/Koziolek.gpg' '$_STATE/calls'"
    assertFalse 'keyserver zbędny' "grep -qF -- '--recv-keys' '$_STATE/calls'"
}

testImportFallsBackToKeyserver() {
    MOCK_GOOD_SRC='keyserver' _run card_nourl gpg_card_import_pubkey >/dev/null 2>&1
    assertEquals 0 $?
    assertTrue "grep -qF -- '--keyserver hkps://keys.openpgp.org --recv-keys $SIG_FPR' '$_STATE/calls'"
}

testImportFailsWhenNoSourceHasKey() {
    local out rc=0
    out=$(MOCK_GOOD_SRC='' _run card_nourl gpg_card_import_pubkey 2>&1) || rc=$?
    assertNotEquals 0 "$rc"
    assertContains "$out" 'GPG_PUBKEY_URL'
}

testImportSkipsFetchWhenKeyAlreadyPresent() {
    touch "$_STATE/have_pub"
    _run card_ok gpg_card_import_pubkey >/dev/null 2>&1
    assertEquals 0 $?
    assertFalse "grep -qF -- '--fetch-keys' '$_STATE/calls'"
}

# --- konfiguracja git -------------------------------------------------------------

testSetupConfiguresGitSigning() {
    touch "$_STATE/have_pub"
    _run card_ok gpg_git_setup >/dev/null 2>&1
    assertEquals 0 $?
    assertEquals "${SIG_FPR}!" "$(_gitcfg user.signingkey)"
    assertEquals 'true' "$(_gitcfg commit.gpgsign)"
    assertEquals 'true' "$(_gitcfg tag.gpgSign)"
    assertEquals 'openpgp' "$(_gitcfg gpg.format)"
    assertEquals "$_BIN/gpg" "$(_gitcfg gpg.program)"
}

testSetupIsIdempotent() {
    touch "$_STATE/have_pub"
    _run card_ok gpg_git_setup >/dev/null 2>&1
    _run card_ok gpg_git_setup >/dev/null 2>&1
    assertEquals 0 $?
    assertEquals 1 "$(cd "$_HOME" && HOME="$_HOME" git config --global --get-all commit.gpgsign | wc -l)"
}

testDisableRemovesSigningConfig() {
    touch "$_STATE/have_pub"
    _run card_ok gpg_git_setup >/dev/null 2>&1
    _run card_ok gpg_git_disable >/dev/null 2>&1
    assertNull "$(_gitcfg commit.gpgsign)"
    assertNull "$(_gitcfg tag.gpgSign)"
    assertNull "$(_gitcfg user.signingkey)"
}

# --- test podpisu / scdaemon ------------------------------------------------------

testCardTestSignsWithExactSubkey() {
    _run card_ok gpg_card_test >/dev/null 2>&1
    assertEquals 0 $?
    assertTrue "grep -qF -- '--local-user ${SIG_FPR}! --clearsign' '$_STATE/calls'"
}

testUsePcscdIsIdempotent() {
    _run none gpg_card_use_pcscd >/dev/null 2>&1
    _run none gpg_card_use_pcscd >/dev/null 2>&1
    assertEquals 1 "$(grep -cxF disable-ccid "$_HOME/.gnupg/scdaemon.conf")"
    assertEquals 1 "$(grep -cxF pcsc-shared "$_HOME/.gnupg/scdaemon.conf")"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
