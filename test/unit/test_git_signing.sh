#!/usr/bin/env bash
# Testy jednostkowe: bash/functions.d/155_function_git_signing.sh
# (GPG-karta + SSH-sk — połączone, bo obie sekcje robią to samo: podpis
# commitów git, tylko innym sprzętem). gpg/gpgconf/ssh-keygen/gh są
# mockowane (skrypty w PATH) — kontener testowy nie ma ani karty OpenPGP,
# ani urządzenia FIDO. Dwa osobne harnessy uruchamiania (_run_gpg dla sekcji
# karty, _run_ssh dla sekcji SSH-sk) — różne sygnatury (karta jako pierwszy
# argument vs brak), oba sourcują ten sam, połączony plik funkcji. git jest
# prawdziwy, z HOME w katalogu tymczasowym — sprawdzamy realny ~/.gitconfig.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Asercje na polskie teksty komunikatów — niezależnie od LANG maszyny (np. en_US na macOS);
# eksport dziedziczą też powłoki harnessów (bash -c).
export MESSAGES_LANG=pl

SIG_FPR='AAAA1111BBBB2222CCCC3333DDDD4444EEEE5555'
PRIMARY_FPR='9999888877776666555544443333222211110000'
PUB_BLOB='sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIMOCK'

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

    cat > "$_BIN/ssh-keygen" <<MOCK
#!/usr/bin/env bash
echo "\$*" >> "\$MOCK_STATE/calls"
args=("\$@")
case " \$* " in
  *" -t ed25519-sk "*)
    [ "\${MOCK_FAIL:-}" = create ] && exit 1
    for ((i=0; i<\${#args[@]}; i++)); do [ "\${args[i]}" = -f ] && f="\${args[i+1]}"; done
    echo "stub" > "\$f"; echo "$PUB_BLOB git-signing" > "\$f.pub" ;;
  *" -K "*)
    [ "\${MOCK_FAIL:-}" = load ] && exit 1
    for n in \${MOCK_RK:-}; do echo "stub \$n" > "\$n"; echo "$PUB_BLOB \$n" > "\$n.pub"; done ;;
  *" -Y sign "*)
    [ "\${MOCK_FAIL:-}" = sign ] && exit 1
    touch "\${args[\${#args[@]}-1]}.sig" ;;
  *" -Y verify "*)
    cat >/dev/null
    [ "\${MOCK_FAIL:-}" = verify ] && exit 1 ;;
esac
exit 0
MOCK
    chmod +x "$_BIN/ssh-keygen"
    printf '#!/bin/sh\necho "gh $*" >> "$MOCK_STATE/calls"\n' > "$_BIN/gh"
    chmod +x "$_BIN/gh"
}
oneTimeTearDown() { rm -rf "$_BIN" "$_FIX"; }

_STATE=''
_HOME=''
setUp() {
    _STATE="$(mktemp -d)"
    _HOME="$(mktemp -d)"
    (cd "$_HOME" && HOME="$_HOME" git config --global user.email 'koziolek@example.test')
}
tearDown() { rm -rf "$_STATE" "$_HOME"; }

# Subshell + cd do $_HOME: `git config --global` mimo --global wciąż próbuje
# rozpoznać repo w CWD — w kontenerze CWD to zamontowany worktree z .git
# wskazującym na ścieżkę hosta (poza kontenerem), co wywala "not a git
# repository" i przerywa zapis configu. Poza jakimkolwiek repo tego nie ma.
_gitcfg() { (cd "$_HOME" && HOME="$_HOME" git config --global --get "$1"); }
_KEY() { echo "$_HOME/.ssh/id_ed25519_sk_git"; }

# _run_gpg <karta: fixture|none> <fn-wywołanie...>
_run_gpg() {
    local card="$1"; shift
    [ "$card" = none ] || card="$_FIX/$card"
    HOME="$_HOME" MOCK_STATE="$_STATE" MOCK_CARD="$card" PATH="$_BIN:$PATH" \
        XDG_CONFIG_HOME="$_HOME/.config" \
        bash --norc --noprofile -c "
            cd '$_HOME' || exit 1
            export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
            export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
            unset GPG_PUBKEY_URL GPG_KEYSERVER GNUPGHOME
            . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh'
            . '$PROJECT_ROOT/bash/functions.d/155_function_git_signing.sh'
            $*
        "
}

# _run_ssh <fn-wywołanie...>
_run_ssh() {
    # _ssh_sk_email robi `git config --get user.email` bez --global (celowo —
    # respektuje user.email per-repo), więc cd do izolowanego HOME jest
    # konieczne, inaczej złapałby lokalny .git/config TEGO repo.
    HOME="$_HOME" MOCK_STATE="$_STATE" PATH="$_BIN:$PATH" \
        bash --norc --noprofile -c "
            cd '$_HOME' || exit 1
            export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
            export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
            unset SSH_KEYGEN SSH_SK_KEY_FILE SSH_SK_APPLICATION XDG_CONFIG_HOME
            . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh'
            . '$PROJECT_ROOT/bash/functions.d/155_function_git_signing.sh'
            $*
        "
}

# =============================================================================
# GPG-karta
# =============================================================================

# --- parsowanie ---------------------------------------------------------------

testSigningFprIsFirstFprFieldUppercased() {
    local out
    out=$(_run_gpg card_ok '_gpg_card_signing_fpr "$(cat '"$_FIX/card_ok"')"')
    assertEquals "$SIG_FPR" "$out"
}

testSigningFprEmptyForEmptySlot() {
    local out
    out=$(_run_gpg card_empty '_gpg_card_signing_fpr "$(cat '"$_FIX/card_empty"')"')
    assertEquals '' "$out"
}

testCardUrlUnescapesColon() {
    local out
    out=$(_run_gpg card_ok '_gpg_card_field url "$(cat '"$_FIX/card_ok"')"')
    assertEquals 'https://example.test/key.asc' "$out"
}

# --- zależności / brak karty ---------------------------------------------------

testGpgCheckDepsFailsWithoutGpg() {
    local out rc=0 bash_bin
    bash_bin="$(command -v bash)"
    out=$(PATH='' "$bash_bin" --norc --noprofile -c "
            . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh'
            . '$PROJECT_ROOT/bash/functions.d/155_function_git_signing.sh'
            _gpg_card_check_deps
        " 2>&1) || rc=$?
    assertNotEquals 0 "$rc"
    assertContains "$out" 'brakujące zależności'
}

testCardSetupFailsWithoutCardAndTouchesNothing() {
    local out rc=0
    out=$(_run_gpg none gpg_git_setup 2>&1) || rc=$?
    assertNotEquals 'brak karty musi dać błąd' 0 "$rc"
    assertContains "$out" 'nie widzę karty OpenPGP'
    assertNull 'gitconfig nie może dostać signingkey' "$(_gitcfg user.signingkey)"
    assertNull 'gitconfig nie może włączyć gpgsign' "$(_gitcfg commit.gpgsign)"
}

testCardSetupFailsWithEmptySigningSlot() {
    local out rc=0
    out=$(_run_gpg card_empty gpg_git_setup 2>&1) || rc=$?
    assertNotEquals 0 "$rc"
    assertContains "$out" 'slot podpisu na karcie jest pusty'
    assertNull "$(_gitcfg commit.gpgsign)"
}

# --- import klucza publicznego --------------------------------------------------

testImportUsesUrlStoredOnCardFirst() {
    MOCK_GOOD_SRC='https://example.test/key.asc' _run_gpg card_ok gpg_card_import_pubkey >/dev/null 2>&1
    assertEquals 0 $?
    assertTrue 'fetch z URL karty' "grep -qF -- '--fetch-keys https://example.test/key.asc' '$_STATE/calls'"
    assertFalse 'nie powinien iść dalej do GitHuba' "grep -qF 'github.com' '$_STATE/calls'"
    assertEquals 'ownertrust ultimate dla klucza głównego' "${PRIMARY_FPR}:6:" "$(cat "$_STATE/ownertrust")"
}

testImportFallsBackToGithubWhenCardHasNoUrl() {
    MOCK_GOOD_SRC='https://github.com/Koziolek.gpg' _run_gpg card_nourl gpg_card_import_pubkey >/dev/null 2>&1
    assertEquals 0 $?
    assertTrue "grep -qF -- '--fetch-keys https://github.com/Koziolek.gpg' '$_STATE/calls'"
    assertFalse 'keyserver zbędny' "grep -qF -- '--recv-keys' '$_STATE/calls'"
}

testImportFallsBackToKeyserver() {
    MOCK_GOOD_SRC='keyserver' _run_gpg card_nourl gpg_card_import_pubkey >/dev/null 2>&1
    assertEquals 0 $?
    assertTrue "grep -qF -- '--keyserver hkps://keys.openpgp.org --recv-keys $SIG_FPR' '$_STATE/calls'"
}

testImportFailsWhenNoSourceHasKey() {
    local out rc=0
    out=$(MOCK_GOOD_SRC='' _run_gpg card_nourl gpg_card_import_pubkey 2>&1) || rc=$?
    assertNotEquals 0 "$rc"
    assertContains "$out" 'GPG_PUBKEY_URL'
}

testImportSkipsFetchWhenKeyAlreadyPresent() {
    touch "$_STATE/have_pub"
    _run_gpg card_ok gpg_card_import_pubkey >/dev/null 2>&1
    assertEquals 0 $?
    assertFalse "grep -qF -- '--fetch-keys' '$_STATE/calls'"
}

# --- konfiguracja git -------------------------------------------------------------

testCardSetupConfiguresGitSigning() {
    touch "$_STATE/have_pub"
    _run_gpg card_ok gpg_git_setup >/dev/null 2>&1
    assertEquals 0 $?
    assertEquals "${SIG_FPR}!" "$(_gitcfg user.signingkey)"
    assertEquals 'true' "$(_gitcfg commit.gpgsign)"
    assertEquals 'true' "$(_gitcfg tag.gpgSign)"
    assertEquals 'openpgp' "$(_gitcfg gpg.format)"
    assertEquals "$_BIN/gpg" "$(_gitcfg gpg.program)"
}

testCardSetupIsIdempotent() {
    touch "$_STATE/have_pub"
    _run_gpg card_ok gpg_git_setup >/dev/null 2>&1
    _run_gpg card_ok gpg_git_setup >/dev/null 2>&1
    assertEquals 0 $?
    assertEquals 1 "$(cd "$_HOME" && HOME="$_HOME" git config --global --get-all commit.gpgsign | wc -l)"
}

testCardDisableRemovesSigningConfig() {
    touch "$_STATE/have_pub"
    _run_gpg card_ok gpg_git_setup >/dev/null 2>&1
    _run_gpg card_ok gpg_git_disable >/dev/null 2>&1
    assertNull "$(_gitcfg commit.gpgsign)"
    assertNull "$(_gitcfg tag.gpgSign)"
    assertNull "$(_gitcfg user.signingkey)"
}

# --- test podpisu / scdaemon ------------------------------------------------------

testCardTestSignsWithExactSubkey() {
    _run_gpg card_ok gpg_card_test >/dev/null 2>&1
    assertEquals 0 $?
    assertTrue "grep -qF -- '--local-user ${SIG_FPR}! --clearsign' '$_STATE/calls'"
}

testUsePcscdIsIdempotent() {
    _run_gpg none gpg_card_use_pcscd >/dev/null 2>&1
    _run_gpg none gpg_card_use_pcscd >/dev/null 2>&1
    assertEquals 1 "$(grep -cxF disable-ccid "$_HOME/.gnupg/scdaemon.conf")"
    assertEquals 1 "$(grep -cxF pcsc-shared "$_HOME/.gnupg/scdaemon.conf")"
}

# =============================================================================
# SSH-sk
# =============================================================================

# --- ssh_sk_key_create ------------------------------------------------------------

testCreateUsesResidentVerifyRequiredAndApplication() {
    _run_ssh ssh_sk_key_create >/dev/null 2>&1
    assertEquals 0 $?
    local call; call=$(grep -- '-t ed25519-sk' "$_STATE/calls")
    assertContains "$call" '-O resident'
    assertContains "$call" '-O application=ssh:git-signing'
    assertContains "$call" '-O verify-required'
    assertContains "$call" 'git-signing koziolek@example.test'
    assertTrue 'stub zapisany' "[ -s '$(_KEY)' ]"
}

testCreateWithoutVerifyWhenDisabled() {
    SSH_SK_VERIFY=0 _run_ssh ssh_sk_key_create >/dev/null 2>&1
    assertEquals 0 $?
    assertFalse "grep -qF 'verify-required' '$_STATE/calls'"
}

testCreateRefusesToOverwriteExistingStub() {
    mkdir -p "$_HOME/.ssh"; echo old > "$(_KEY)"
    local out rc=0
    out=$(_run_ssh ssh_sk_key_create 2>&1) || rc=$?
    assertNotEquals 0 "$rc"
    assertContains "$out" 'już istnieje'
    assertEquals old "$(cat "$(_KEY)")"
}

# --- ssh_sk_key_load --------------------------------------------------------------

testLoadPicksKeyByApplicationAmongOthers() {
    MOCK_RK='id_ed25519_sk_rk id_ed25519_sk_rk_git-signing id_ed25519_sk_rk_login' \
        _run_ssh ssh_sk_key_load >/dev/null 2>&1
    assertEquals 0 $?
    assertEquals 'stub id_ed25519_sk_rk_git-signing' "$(cat "$(_KEY)")"
    assertTrue '.pub obok stuba' "[ -s '$(_KEY).pub' ]"
    assertEquals 600 "$(stat -c %a "$(_KEY)")"
}

testLoadAcceptsUserSuffixedFileName() {
    MOCK_RK='id_ed25519_sk_rk_git-signing_koziolek' _run_ssh ssh_sk_key_load >/dev/null 2>&1
    assertEquals 0 $?
    assertEquals 'stub id_ed25519_sk_rk_git-signing_koziolek' "$(cat "$(_KEY)")"
}

testLoadFailsWhenDeviceHasNoSigningKey() {
    local out rc=0
    out=$(MOCK_RK='id_ed25519_sk_rk_login' _run_ssh ssh_sk_key_load 2>&1) || rc=$?
    assertNotEquals 0 "$rc"
    assertContains "$out" 'ssh_sk_key_create'
    assertFalse "[ -e '$(_KEY)' ]"
}

testLoadSkipsDeviceWhenStubExists() {
    mkdir -p "$_HOME/.ssh"; echo s > "$(_KEY)"; echo "$PUB_BLOB" > "$(_KEY).pub"
    _run_ssh ssh_sk_key_load >/dev/null 2>&1
    assertEquals 0 $?
    assertFalse 'nie powinien pytać urządzenia' "grep -qF -- '-K' '$_STATE/calls'"
}

testLoadDefaultApplicationUsesUnsuffixedName() {
    MOCK_RK='id_ed25519_sk_rk_login id_ed25519_sk_rk' \
        SSH_SK_APPLICATION='ssh:' _run_ssh 'SSH_SK_APPLICATION=ssh: ssh_sk_key_load' >/dev/null 2>&1
    assertEquals 0 $?
    assertEquals 'stub id_ed25519_sk_rk' "$(cat "$(_KEY)")"
}

testLoadDefaultApplicationIgnoresOtherApplications() {
    local rc=0
    MOCK_RK='id_ed25519_sk_rk_login' _run_ssh 'SSH_SK_APPLICATION=ssh: ssh_sk_key_load' >/dev/null 2>&1 || rc=$?
    assertNotEquals 0 "$rc"
    assertFalse "[ -e '$(_KEY)' ]"
}

# --- ssh_sk_use_existing ------------------------------------------------------------

testUseExistingConfiguresGitWithGivenSkKey() {
    mkdir -p "$_HOME/.ssh"
    echo stub > "$_HOME/.ssh/id_ed25519_sk"
    echo "$PUB_BLOB login" > "$_HOME/.ssh/id_ed25519_sk.pub"
    local out
    out=$(_run_ssh "ssh_sk_use_existing '$_HOME/.ssh/id_ed25519_sk.pub'" 2>&1)
    assertEquals 0 $?
    assertEquals "$_HOME/.ssh/id_ed25519_sk" "$(_gitcfg user.signingkey)"
    assertEquals 'ssh' "$(_gitcfg gpg.format)"
    assertContains "$out" "export SSH_SK_KEY_FILE=$_HOME/.ssh/id_ed25519_sk"
    assertFalse 'nie pyta urządzenia, stub jest' "grep -qF -- '-K' '$_STATE/calls'"
}

testUseExistingRefusesDiskKey() {
    mkdir -p "$_HOME/.ssh"
    echo priv > "$_HOME/.ssh/id_ed25519"
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMOCK me" > "$_HOME/.ssh/id_ed25519.pub"
    local out rc=0
    out=$(_run_ssh "ssh_sk_use_existing '$_HOME/.ssh/id_ed25519'" 2>&1) || rc=$?
    assertNotEquals 0 "$rc"
    assertContains "$out" 'na dysku'
    assertNull "$(_gitcfg commit.gpgsign)"
}

# --- ssh_sk_git_setup -------------------------------------------------------------

testSshSetupConfiguresGitForSshSigning() {
    MOCK_RK='id_ed25519_sk_rk_git-signing' _run_ssh ssh_sk_git_setup >/dev/null 2>&1
    assertEquals 0 $?
    assertEquals 'ssh' "$(_gitcfg gpg.format)"
    assertEquals "$(_KEY)" "$(_gitcfg user.signingkey)"
    assertEquals 'true' "$(_gitcfg commit.gpgsign)"
    assertEquals 'true' "$(_gitcfg tag.gpgSign)"
    assertEquals "$_BIN/ssh-keygen" "$(_gitcfg gpg.ssh.program)"
    assertEquals "$_HOME/.config/git/allowed_signers" "$(_gitcfg gpg.ssh.allowedSignersFile)"
    assertEquals "koziolek@example.test namespaces=\"git\" $PUB_BLOB" \
        "$(cat "$_HOME/.config/git/allowed_signers")"
}

testSshSetupIsIdempotentForAllowedSigners() {
    MOCK_RK='id_ed25519_sk_rk_git-signing' _run_ssh ssh_sk_git_setup >/dev/null 2>&1
    _run_ssh ssh_sk_git_setup >/dev/null 2>&1
    assertEquals 0 $?
    assertEquals 1 "$(wc -l < "$_HOME/.config/git/allowed_signers")"
}

testSshSetupFailsWithoutKeyAndLeavesGitUntouched() {
    local rc=0
    MOCK_FAIL=load _run_ssh ssh_sk_git_setup >/dev/null 2>&1 || rc=$?
    assertNotEquals 0 "$rc"
    assertNull "$(_gitcfg commit.gpgsign)"
    assertNull "$(_gitcfg gpg.format)"
}

testSshSetupFailsWithoutEmail() {
    (cd "$_HOME" && HOME="$_HOME" git config --global --unset user.email)
    local out rc=0
    out=$(_run_ssh ssh_sk_git_setup 2>&1) || rc=$?
    assertNotEquals 0 "$rc"
    assertContains "$out" 'brak e-maila'
}

testSshDisableRemovesSshSigningConfig() {
    MOCK_RK='id_ed25519_sk_rk_git-signing' _run_ssh ssh_sk_git_setup >/dev/null 2>&1
    _run_ssh ssh_sk_git_disable >/dev/null 2>&1
    assertNull "$(_gitcfg commit.gpgsign)"
    assertNull "$(_gitcfg gpg.format)"
    assertNull "$(_gitcfg user.signingkey)"
    assertEquals 'koziolek@example.test' "$(_gitcfg user.email)"
}

# --- ssh_sk_test / github --------------------------------------------------------

testSignTestSignsAndVerifiesWithGitNamespace() {
    MOCK_RK='id_ed25519_sk_rk_git-signing' _run_ssh ssh_sk_git_setup >/dev/null 2>&1
    _run_ssh ssh_sk_test >/dev/null 2>&1
    assertEquals 0 $?
    assertTrue "grep -qE -- '-Y sign -n git -f $(_KEY) ' '$_STATE/calls'"
    assertTrue "grep -qF -- '-Y verify -n git -f $_HOME/.config/git/allowed_signers -I koziolek@example.test' '$_STATE/calls'"
}

testSignTestReportsVerifyFailure() {
    MOCK_RK='id_ed25519_sk_rk_git-signing' _run_ssh ssh_sk_git_setup >/dev/null 2>&1
    local out rc=0
    out=$(MOCK_FAIL=verify _run_ssh ssh_sk_test 2>&1) || rc=$?
    assertNotEquals 0 "$rc"
    assertContains "$out" 'weryfikacja'
}

testGithubUploadAddsSigningKey() {
    MOCK_RK='id_ed25519_sk_rk_git-signing' _run_ssh ssh_sk_git_setup >/dev/null 2>&1
    _run_ssh ssh_sk_github_upload >/dev/null 2>&1
    assertEquals 0 $?
    assertTrue "grep -qF 'gh ssh-key add $(_KEY).pub --type signing' '$_STATE/calls'"
}

# =============================================================================
# GPG software (commit signing)
# =============================================================================

testSwGitSetupFailsWithoutKeyidOrCfg() {
    local out rc=0
    out=$(_run_gpg none gpg_sw_git_setup 2>&1) || rc=$?
    assertNotEquals 0 "$rc"
    assertNull "$(_gitcfg commit.gpgsign)"
}

testSwGitSetupConfiguresGitSigning() {
    _run_gpg none gpg_sw_git_setup DEADBEEF >/dev/null 2>&1
    assertEquals 0 $?
    assertEquals 'DEADBEEF' "$(_gitcfg user.signingkey)"
    assertEquals 'true' "$(_gitcfg commit.gpgsign)"
    assertEquals 'true' "$(_gitcfg tag.gpgSign)"
    assertEquals 'openpgp' "$(_gitcfg gpg.format)"
    assertEquals "$_BIN/gpg" "$(_gitcfg gpg.program)"
}

testSwGitSetupUsesDefaultFromCfg() {
    mkdir -p "$_HOME/.config/git-configuration-signing"
    printf 'KEYID=CAFEBABE\n' > "$_HOME/.config/git-configuration-signing/gpg-sw.cfg"
    _run_gpg none gpg_sw_git_setup >/dev/null 2>&1
    assertEquals 0 $?
    assertEquals 'CAFEBABE' "$(_gitcfg user.signingkey)"
}

testSwGitDisableRemovesConfig() {
    _run_gpg none gpg_sw_git_setup DEADBEEF >/dev/null 2>&1
    _run_gpg none gpg_sw_git_disable >/dev/null 2>&1
    assertNull "$(_gitcfg commit.gpgsign)"
    assertNull "$(_gitcfg tag.gpgSign)"
    assertNull "$(_gitcfg user.signingkey)"
}

testSwTestFailsWithoutKeyid() {
    local rc=0
    _run_gpg none gpg_sw_test >/dev/null 2>&1 || rc=$?
    assertNotEquals 0 "$rc"
}

testSwTestSignsWithClearsign() {
    _run_gpg none gpg_sw_test DEADBEEF >/dev/null 2>&1
    assertEquals 0 $?
    assertTrue "grep -qF -- '--local-user DEADBEEF --clearsign' '$_STATE/calls'"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
