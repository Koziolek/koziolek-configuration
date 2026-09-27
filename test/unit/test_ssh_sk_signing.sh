#!/usr/bin/env bash
# Testy jednostkowe: bash/functions.d/156_function_ssh_sk_signing.sh (podpis SSH
# kluczem FIDO2 ed25519-sk, resident). ssh-keygen i gh są mockowane — kontener
# testowy nie ma urządzenia FIDO. Mock ssh-keygen:
#   -t ed25519-sk ... -f F  → tworzy F i F.pub,
#   -K                      → tworzy w cwd pliki z $MOCK_RK (lista nazw rk),
#   -Y sign / -Y verify     → sukces, chyba że $MOCK_FAIL=sign|verify.
# Każde wywołanie loguje argumenty do $MOCK_STATE/calls. git jest prawdziwy,
# z HOME w katalogu tymczasowym.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PUB_BLOB='sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIMOCK'

_BIN=''
oneTimeSetUp() {
    _BIN="$(mktemp -d)"
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
oneTimeTearDown() { rm -rf "$_BIN"; }

_STATE=''
_HOME=''
setUp() {
    _STATE="$(mktemp -d)"
    _HOME="$(mktemp -d)"
    (cd "$_HOME" && HOME="$_HOME" git config --global user.email 'koziolek@example.test')
}
tearDown() { rm -rf "$_STATE" "$_HOME"; }

_run() {
    # cd do izolowanego HOME: _ssh_sk_email robi `git config --get user.email`
    # bez --global (celowo — respektuje user.email per-repo), więc bez tego cd
    # złapałby lokalny .git/config TEGO repo zamiast izolowanego globalnego.
    HOME="$_HOME" MOCK_STATE="$_STATE" PATH="$_BIN:$PATH" \
        bash --norc --noprofile -c "
            cd '$_HOME' || exit 1
            export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
            export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
            unset SSH_KEYGEN SSH_SK_KEY_FILE SSH_SK_APPLICATION XDG_CONFIG_HOME
            . '$PROJECT_ROOT/bash/functions.d/010_function_log.sh'
            . '$PROJECT_ROOT/bash/functions.d/156_function_ssh_sk_signing.sh'
            $*
        "
}

# Subshell + cd do $_HOME: jak w _run — `git config --global` mimo --global
# wciąż próbuje rozpoznać repo w CWD, a w kontenerze CWD (zamontowany worktree)
# ma .git wskazujący na ścieżkę hosta niedostępną w kontenerze.
_gitcfg() { (cd "$_HOME" && HOME="$_HOME" git config --global --get "$1"); }
_KEY() { echo "$_HOME/.ssh/id_ed25519_sk_git"; }

# --- ssh_sk_key_create ------------------------------------------------------------

testCreateUsesResidentVerifyRequiredAndApplication() {
    _run ssh_sk_key_create >/dev/null 2>&1
    assertEquals 0 $?
    local call; call=$(grep -- '-t ed25519-sk' "$_STATE/calls")
    assertContains "$call" '-O resident'
    assertContains "$call" '-O application=ssh:git-signing'
    assertContains "$call" '-O verify-required'
    assertContains "$call" 'git-signing koziolek@example.test'
    assertTrue 'stub zapisany' "[ -s '$(_KEY)' ]"
}

testCreateWithoutVerifyWhenDisabled() {
    SSH_SK_VERIFY=0 _run ssh_sk_key_create >/dev/null 2>&1
    assertEquals 0 $?
    assertFalse "grep -qF 'verify-required' '$_STATE/calls'"
}

testCreateRefusesToOverwriteExistingStub() {
    mkdir -p "$_HOME/.ssh"; echo old > "$(_KEY)"
    local out rc=0
    out=$(_run ssh_sk_key_create 2>&1) || rc=$?
    assertNotEquals 0 "$rc"
    assertContains "$out" 'już istnieje'
    assertEquals old "$(cat "$(_KEY)")"
}

# --- ssh_sk_key_load --------------------------------------------------------------

testLoadPicksKeyByApplicationAmongOthers() {
    MOCK_RK='id_ed25519_sk_rk id_ed25519_sk_rk_git-signing id_ed25519_sk_rk_login' \
        _run ssh_sk_key_load >/dev/null 2>&1
    assertEquals 0 $?
    assertEquals 'stub id_ed25519_sk_rk_git-signing' "$(cat "$(_KEY)")"
    assertTrue '.pub obok stuba' "[ -s '$(_KEY).pub' ]"
    assertEquals 600 "$(stat -c %a "$(_KEY)")"
}

testLoadAcceptsUserSuffixedFileName() {
    MOCK_RK='id_ed25519_sk_rk_git-signing_koziolek' _run ssh_sk_key_load >/dev/null 2>&1
    assertEquals 0 $?
    assertEquals 'stub id_ed25519_sk_rk_git-signing_koziolek' "$(cat "$(_KEY)")"
}

testLoadFailsWhenDeviceHasNoSigningKey() {
    local out rc=0
    out=$(MOCK_RK='id_ed25519_sk_rk_login' _run ssh_sk_key_load 2>&1) || rc=$?
    assertNotEquals 0 "$rc"
    assertContains "$out" 'ssh_sk_key_create'
    assertFalse "[ -e '$(_KEY)' ]"
}

testLoadSkipsDeviceWhenStubExists() {
    mkdir -p "$_HOME/.ssh"; echo s > "$(_KEY)"; echo "$PUB_BLOB" > "$(_KEY).pub"
    _run ssh_sk_key_load >/dev/null 2>&1
    assertEquals 0 $?
    assertFalse 'nie powinien pytać urządzenia' "grep -qF -- '-K' '$_STATE/calls'"
}

testLoadDefaultApplicationUsesUnsuffixedName() {
    MOCK_RK='id_ed25519_sk_rk_login id_ed25519_sk_rk' \
        SSH_SK_APPLICATION='ssh:' _run 'SSH_SK_APPLICATION=ssh: ssh_sk_key_load' >/dev/null 2>&1
    assertEquals 0 $?
    assertEquals 'stub id_ed25519_sk_rk' "$(cat "$(_KEY)")"
}

testLoadDefaultApplicationIgnoresOtherApplications() {
    local rc=0
    MOCK_RK='id_ed25519_sk_rk_login' _run 'SSH_SK_APPLICATION=ssh: ssh_sk_key_load' >/dev/null 2>&1 || rc=$?
    assertNotEquals 0 "$rc"
    assertFalse "[ -e '$(_KEY)' ]"
}

# --- ssh_sk_use_existing ------------------------------------------------------------

testUseExistingConfiguresGitWithGivenSkKey() {
    mkdir -p "$_HOME/.ssh"
    echo stub > "$_HOME/.ssh/id_ed25519_sk"
    echo "$PUB_BLOB login" > "$_HOME/.ssh/id_ed25519_sk.pub"
    local out
    out=$(_run "ssh_sk_use_existing '$_HOME/.ssh/id_ed25519_sk.pub'" 2>&1)
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
    out=$(_run "ssh_sk_use_existing '$_HOME/.ssh/id_ed25519'" 2>&1) || rc=$?
    assertNotEquals 0 "$rc"
    assertContains "$out" 'na dysku'
    assertNull "$(_gitcfg commit.gpgsign)"
}

# --- ssh_sk_git_setup -------------------------------------------------------------

testSetupConfiguresGitForSshSigning() {
    MOCK_RK='id_ed25519_sk_rk_git-signing' _run ssh_sk_git_setup >/dev/null 2>&1
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

testSetupIsIdempotentForAllowedSigners() {
    MOCK_RK='id_ed25519_sk_rk_git-signing' _run ssh_sk_git_setup >/dev/null 2>&1
    _run ssh_sk_git_setup >/dev/null 2>&1
    assertEquals 0 $?
    assertEquals 1 "$(wc -l < "$_HOME/.config/git/allowed_signers")"
}

testSetupFailsWithoutKeyAndLeavesGitUntouched() {
    local rc=0
    MOCK_FAIL=load _run ssh_sk_git_setup >/dev/null 2>&1 || rc=$?
    assertNotEquals 0 "$rc"
    assertNull "$(_gitcfg commit.gpgsign)"
    assertNull "$(_gitcfg gpg.format)"
}

testSetupFailsWithoutEmail() {
    (cd "$_HOME" && HOME="$_HOME" git config --global --unset user.email)
    local out rc=0
    out=$(_run ssh_sk_git_setup 2>&1) || rc=$?
    assertNotEquals 0 "$rc"
    assertContains "$out" 'brak e-maila'
}

testDisableRemovesSshSigningConfig() {
    MOCK_RK='id_ed25519_sk_rk_git-signing' _run ssh_sk_git_setup >/dev/null 2>&1
    _run ssh_sk_git_disable >/dev/null 2>&1
    assertNull "$(_gitcfg commit.gpgsign)"
    assertNull "$(_gitcfg gpg.format)"
    assertNull "$(_gitcfg user.signingkey)"
    assertEquals 'koziolek@example.test' "$(_gitcfg user.email)"
}

# --- ssh_sk_test / github --------------------------------------------------------

testSignTestSignsAndVerifiesWithGitNamespace() {
    MOCK_RK='id_ed25519_sk_rk_git-signing' _run ssh_sk_git_setup >/dev/null 2>&1
    _run ssh_sk_test >/dev/null 2>&1
    assertEquals 0 $?
    assertTrue "grep -qE -- '-Y sign -n git -f $(_KEY) ' '$_STATE/calls'"
    assertTrue "grep -qF -- '-Y verify -n git -f $_HOME/.config/git/allowed_signers -I koziolek@example.test' '$_STATE/calls'"
}

testSignTestReportsVerifyFailure() {
    MOCK_RK='id_ed25519_sk_rk_git-signing' _run ssh_sk_git_setup >/dev/null 2>&1
    local out rc=0
    out=$(MOCK_FAIL=verify _run ssh_sk_test 2>&1) || rc=$?
    assertNotEquals 0 "$rc"
    assertContains "$out" 'weryfikacja'
}

testGithubUploadAddsSigningKey() {
    MOCK_RK='id_ed25519_sk_rk_git-signing' _run ssh_sk_git_setup >/dev/null 2>&1
    _run ssh_sk_github_upload >/dev/null 2>&1
    assertEquals 0 $?
    assertTrue "grep -qF 'gh ssh-key add $(_KEY).pub --type signing' '$_STATE/calls'"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
