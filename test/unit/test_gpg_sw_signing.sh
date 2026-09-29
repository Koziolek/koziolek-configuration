#!/usr/bin/env bash
# Testy jednostkowe: bash/functions.d/158_function_gpg_sw_signing.sh
# gpg i curl są mockowane (skrypty w PATH). Sourcuje też 157 — gpg_maven_setup/
# disable reużywają jego helperów manipulacji ~/.m2/settings.xml.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/157_function_jar_signing.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/158_function_gpg_sw_signing.sh"

_BIN=''
oneTimeSetUp() {
    _BIN="$(mktemp -d)"

    # gpg: --quick-generate-key (MOCK_FAIL=generate → błąd), --list-secret-keys
    # (--with-colons → jedna linia fpr:...:MOCK_FPR:), --send-keys
    # (MOCK_FAIL=export_ubuntu → błąd), --export (wypisuje fejkowe bajty klucza).
    cat > "$_BIN/gpg" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_STATE/calls"
case " $* " in
  *" --quick-generate-key "*)
    [ "${MOCK_FAIL:-}" = generate ] && exit 1
    exit 0 ;;
  *" --list-secret-keys "*"--with-colons"*)
    printf 'fpr:::::::::%s:\n' "${MOCK_FPR:-DEADBEEF1234567890DEADBEEF1234567890ABCD}"
    exit 0 ;;
  *" --list-secret-keys "*)
    echo "sec   ed25519/${MOCK_FPR:-DEADBEEF} 2026-01-01 [SC]"
    exit 0 ;;
  *" --send-keys "*)
    [ "${MOCK_FAIL:-}" = export_ubuntu ] && exit 1
    exit 0 ;;
  *" --export "*)
    echo "PGPKEYDATA"
    exit 0 ;;
esac
exit 0
MOCK
    chmod +x "$_BIN/gpg"

    cat > "$_BIN/curl" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_STATE/calls"
cat >/dev/null
[ "${MOCK_FAIL:-}" = export_openpgp ] && exit 1
echo '{"status":"ok"}'
exit 0
MOCK
    chmod +x "$_BIN/curl"
}
oneTimeTearDown() { rm -rf "$_BIN"; }

_STATE=''
_WORK=''
setUp() {
    _STATE="$(mktemp -d)"
    _WORK="$(mktemp -d)"
    export MOCK_STATE="$_STATE"
    unset MOCK_FPR MOCK_FAIL GPG_SW_NAME GPG_SW_EMAIL GPG_SW_KEY_ALGO \
        GPG_SW_KEY_USAGE GPG_SW_KEY_EXPIRE GPG_SW_EXPORT_TARGET GPG_SW_MAVEN_CONFIRM
    export XDG_CONFIG_HOME="$_WORK/config"
    export PATH="$_BIN:$PATH"
}
tearDown() {
    rm -rf "$_STATE" "$_WORK"
    unset MOCK_FPR MOCK_FAIL GPG_SW_NAME GPG_SW_EMAIL GPG_SW_KEY_ALGO \
        GPG_SW_KEY_USAGE GPG_SW_KEY_EXPIRE GPG_SW_EXPORT_TARGET GPG_SW_MAVEN_CONFIRM \
        XDG_CONFIG_HOME MAVEN_SETTINGS MOCK_STATE
}

# ---------------------------------------------------------------------------
# gpg_sw_generate
# ---------------------------------------------------------------------------

testGenerateFailsWithoutNameOrEmail() {
    gpg_sw_generate >/dev/null 2>&1
    assertEquals 1 $?
}

testGenerateFailsWhenKeygenFails() {
    MOCK_FAIL=generate gpg_sw_generate "Jan Kowalski" "jan@example.com" >/dev/null 2>&1
    assertEquals 1 $?
}

testGeneratePrintsFingerprintAndWritesCfg() {
    local out
    out=$(MOCK_FPR="ABCDEF0123456789ABCDEF0123456789ABCDEF01" gpg_sw_generate "Jan Kowalski" "jan@example.com")
    assertEquals "ABCDEF0123456789ABCDEF0123456789ABCDEF01" "$out"
    assertTrue "cfg powinien istnieć" "[ -f '$(_gpg_sw_cfg_path)' ]"
    assertContains "$(cat "$(_gpg_sw_cfg_path)")" "KEYID=ABCDEF0123456789ABCDEF0123456789ABCDEF01"
}

testGenerateUsesUidBuiltFromNameAndEmail() {
    gpg_sw_generate "Jan Kowalski" "jan@example.com" >/dev/null 2>&1
    assertContains "$(cat "$_STATE/calls")" "Jan Kowalski <jan@example.com>"
}

# ---------------------------------------------------------------------------
# gpg_sw_list_keys
# ---------------------------------------------------------------------------

testListKeysInvokesGpg() {
    gpg_sw_list_keys >/dev/null 2>&1
    assertContains "$(cat "$_STATE/calls")" "--list-secret-keys"
}

# ---------------------------------------------------------------------------
# gpg_sw_export
# ---------------------------------------------------------------------------

testExportFailsWithoutKeyid() {
    gpg_sw_export >/dev/null 2>&1
    assertEquals 1 $?
}

testExportRejectsUnknownTarget() {
    gpg_sw_export DEADBEEF bogus >/dev/null 2>&1
    assertEquals 1 $?
}

testExportUbuntuCallsSendKeys() {
    gpg_sw_export DEADBEEF ubuntu >/dev/null 2>&1
    assertContains "$(cat "$_STATE/calls")" "keyserver.ubuntu.com"
    assertNotContains "$(cat "$_STATE/calls")" "keys.openpgp.org"
}

testExportOpenpgpCallsCurlUpload() {
    gpg_sw_export DEADBEEF openpgp >/dev/null 2>&1
    assertContains "$(cat "$_STATE/calls")" "keys.openpgp.org"
}

testExportBothCallsBothTargets() {
    gpg_sw_export DEADBEEF both >/dev/null 2>&1
    local calls
    calls="$(cat "$_STATE/calls")"
    assertContains "$calls" "keyserver.ubuntu.com"
    assertContains "$calls" "keys.openpgp.org"
}

testExportDefaultsToBothWhenTargetOmitted() {
    gpg_sw_export DEADBEEF >/dev/null 2>&1
    local calls
    calls="$(cat "$_STATE/calls")"
    assertContains "$calls" "keyserver.ubuntu.com"
    assertContains "$calls" "keys.openpgp.org"
}

testExportFailsWhenUbuntuSendFails() {
    MOCK_FAIL=export_ubuntu gpg_sw_export DEADBEEF ubuntu >/dev/null 2>&1
    assertEquals 1 $?
}

testExportFailsWhenOpenpgpUploadFails() {
    MOCK_FAIL=export_openpgp gpg_sw_export DEADBEEF openpgp >/dev/null 2>&1
    assertEquals 1 $?
}

# ---------------------------------------------------------------------------
# gpg_maven_setup / gpg_maven_disable (~/.m2/settings.xml)
# ---------------------------------------------------------------------------

_realistic_settings() {
    cat > "$1" <<'XML'
<settings>
  <!-- prawdziwa konfiguracja Nexusa, nie ruszac -->
  <mirrors>
    <mirror><id>nexus</id><url>https://koziolek.home/nexus/repository/maven-public/</url><mirrorOf>*</mirrorOf></mirror>
  </mirrors>
</settings>
XML
}

testMavenSetupFailsWithoutKeyidOrCfg() {
    local f="$_WORK/settings.xml"
    MAVEN_SETTINGS="$f" gpg_maven_setup >/dev/null 2>&1
    assertEquals 1 $?
}

testMavenSetupUsesExplicitKeyid() {
    local f="$_WORK/settings.xml"
    MAVEN_SETTINGS="$f" gpg_maven_setup DEADBEEF >/dev/null 2>&1
    assertContains "$(cat "$f")" "<gpg.keyname>DEADBEEF</gpg.keyname>"
    assertContains "$(cat "$f")" "gpg-sw-signing"
}

testMavenSetupFallsBackToGeneratedCfg() {
    local f="$_WORK/settings.xml"
    MOCK_FPR="CAFEBABE" gpg_sw_generate "Jan Kowalski" "jan@example.com" >/dev/null 2>&1
    MAVEN_SETTINGS="$f" gpg_maven_setup >/dev/null 2>&1
    assertContains "$(cat "$f")" "<gpg.keyname>CAFEBABE</gpg.keyname>"
}

testMavenSetupPreservesExistingMirrorsAndComment() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    MAVEN_SETTINGS="$f" gpg_maven_setup DEADBEEF >/dev/null 2>&1
    assertContains "$(cat "$f")" "nie ruszac"
    assertContains "$(cat "$f")" "koziolek.home/nexus"
    assertContains "$(cat "$f")" "gpg-sw-signing"
}

testMavenSetupIsIdempotent() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    MAVEN_SETTINGS="$f" gpg_maven_setup DEADBEEF >/dev/null 2>&1
    MAVEN_SETTINGS="$f" gpg_maven_setup DEADBEEF >/dev/null 2>&1
    local count
    count=$(grep -c '<id>gpg-sw-signing</id>' "$f")
    assertEquals 1 "$count"
}

testMavenSetupCoexistsWithJarHwSigningProfile() {
    # Zamiast realnie odpalać jar_pkcs11_setup/jar_maven_setup (wymagałoby
    # mocka pkcs11-tool, poza scope tego pliku) — wstawiamy blok jar-hw-signing
    # bezpośrednio przez ten sam reużywany helper co gpg_maven_setup, żeby
    # sprawdzić że oba oznaczone bloki mogą współistnieć bez nadpisywania się.
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    _jar_ensure_settings_skeleton "$f"
    _jar_ensure_container "$f" profiles
    _jar_ensure_container "$f" activeProfiles
    _jar_upsert_marked_block "$f" jar-hw-signing-profile profiles "  <profile><id>jar-hw-signing</id></profile>"
    _jar_upsert_marked_block "$f" jar-hw-signing-active activeProfiles "  <activeProfile>jar-hw-signing</activeProfile>"

    MAVEN_SETTINGS="$f" gpg_maven_setup DEADBEEF >/dev/null 2>&1
    assertContains "$(cat "$f")" "jar-hw-signing"
    assertContains "$(cat "$f")" "gpg-sw-signing"
}

testMavenDisableRemovesProfileKeepsRestOfFile() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    MAVEN_SETTINGS="$f" gpg_maven_setup DEADBEEF >/dev/null 2>&1
    MAVEN_SETTINGS="$f" gpg_maven_disable >/dev/null 2>&1
    assertNotContains "$(cat "$f")" "gpg-sw-signing"
    assertContains "$(cat "$f")" "nie ruszac"
    assertContains "$(cat "$f")" "koziolek.home/nexus"
}

# ---------------------------------------------------------------------------
# gpg_sw_setup (orkiestrator, sterowany zmiennymi zamiast promptów)
# ---------------------------------------------------------------------------

testSetupRunsFullFlowNonInteractively() {
    local f="$_WORK/settings.xml"
    GPG_SW_NAME="Jan Kowalski" GPG_SW_EMAIL="jan@example.com" \
        GPG_SW_EXPORT_TARGET=ubuntu GPG_SW_MAVEN_CONFIRM=T \
        MAVEN_SETTINGS="$f" gpg_sw_setup >/dev/null 2>&1
    local calls
    calls="$(cat "$_STATE/calls")"
    assertContains "$calls" "--quick-generate-key"
    assertContains "$calls" "keyserver.ubuntu.com"
    assertContains "$(cat "$f")" "gpg-sw-signing"
}

testSetupSkipsMavenWhenNotConfirmed() {
    local f="$_WORK/settings.xml"
    GPG_SW_NAME="Jan Kowalski" GPG_SW_EMAIL="jan@example.com" \
        GPG_SW_EXPORT_TARGET=none GPG_SW_MAVEN_CONFIRM=n \
        MAVEN_SETTINGS="$f" gpg_sw_setup >/dev/null 2>&1
    assertFalse "settings.xml nie powinien powstać" "[ -f '$f' ]"
}

testSetupSkipsExportWhenTargetNone() {
    GPG_SW_NAME="Jan Kowalski" GPG_SW_EMAIL="jan@example.com" \
        GPG_SW_EXPORT_TARGET=none GPG_SW_MAVEN_CONFIRM=n \
        MAVEN_SETTINGS="$_WORK/settings.xml" gpg_sw_setup >/dev/null 2>&1
    assertNotContains "$(cat "$_STATE/calls")" "keyserver.ubuntu.com"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
