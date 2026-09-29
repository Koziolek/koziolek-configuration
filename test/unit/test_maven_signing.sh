#!/usr/bin/env bash
# Testy jednostkowe: bash/functions.d/157_function_maven_signing.sh
# (JAR/PKCS11 + GPG software — połączone, bo dzielą helpery manipulacji
# ~/.m2/settings.xml). pkcs11-tool/jarsigner/keytool/jar/gpg/curl są
# mockowane (skrypty w PATH) — kontener testowy nie ma karty PIV ani
# realnego GPG keyringu. Blok testów "maven settings" testuje realne pliki
# (_maven_settings_ensure_*/_maven_settings_upsert_*/_maven_settings_remove_*
# to czysta manipulacja tekstem, bez zależności zewnętrznych) — sprawdza że
# cudza zawartość (komentarze, mirrory) nigdy nie jest ruszana, i że oba
# profile (jar-hw-signing, gpg-sw-signing) współistnieją.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/157_function_maven_signing.sh"

_BIN=''
oneTimeSetUp() {
    _BIN="$(mktemp -d)"

    # pkcs11-tool: -L (sloty), -O (obiekty/certy - MOCK_CERTS = lista aliasów
    # rozdzielona spacją; puste = brak certu na karcie)
    cat > "$_BIN/pkcs11-tool" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_STATE/calls"
case " $* " in
  *" -L "*)
    echo "Slot 0: Yubico YubiKey" ;;
  *" -O --type cert"*)
    for a in ${MOCK_CERTS:-}; do
        printf 'Certificate Object; type = X.509 cert\n  label:      %s\n  ID:         01\n' "$a"
    done ;;
  *" -O "*)
    for a in ${MOCK_CERTS:-}; do
        printf 'Certificate Object; type = X.509 cert\n  label:      %s\n' "$a"
    done ;;
esac
exit 0
MOCK
    chmod +x "$_BIN/pkcs11-tool"

    # jarsigner: podpis nieudany gdy MOCK_FAIL=sign, weryfikacja nieudana gdy
    # MOCK_FAIL=verify (jar musi zawierać "signed" żeby -verify przeszła).
    cat > "$_BIN/jarsigner" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_STATE/calls"
args=("$@")
case " $* " in
  *" -verify "*)
    for a in "${args[@]}"; do
        [ -f "$a" ] && grep -q signed "$a" 2>/dev/null && { echo "jar verified."; [ "${MOCK_FAIL:-}" = verify ] && exit 1; exit 0; }
    done
    echo "jar is unsigned."; exit 1 ;;
  *)
    [ "${MOCK_FAIL:-}" = sign ] && exit 1
    target_jar=""
    for a in "${args[@]}"; do [ -f "$a" ] && target_jar="$a"; done
    [ -n "$target_jar" ] && echo "signed" >> "$target_jar"
    exit 0 ;;
esac
MOCK
    chmod +x "$_BIN/jarsigner"

    printf '#!/bin/sh\necho "keytool $*" >> "$MOCK_STATE/calls"\n' > "$_BIN/keytool"
    chmod +x "$_BIN/keytool"

    printf '#!/bin/sh\ntouch "$(pwd)/${2:-out.jar}"\n' > "$_BIN/jar"
    chmod +x "$_BIN/jar"

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
    unset JAR_PKCS11_MODULE JAR_PKCS11_ALIAS MOCK_CERTS MOCK_FAIL MOCK_FPR \
        GPG_SW_NAME GPG_SW_EMAIL GPG_SW_KEY_ALGO GPG_SW_KEY_USAGE \
        GPG_SW_KEY_EXPIRE GPG_SW_EXPORT_TARGET GPG_SW_MAVEN_CONFIRM
    export JAR_PKCS11_MODULE="$_BIN/opensc-pkcs11.so"
    touch "$JAR_PKCS11_MODULE"
    export XDG_CONFIG_HOME="$_WORK/config"
    export PATH="$_BIN:$PATH"
}
tearDown() {
    rm -rf "$_STATE" "$_WORK"
    unset JAR_PKCS11_MODULE JAR_PKCS11_ALIAS MOCK_CERTS MOCK_FAIL MOCK_FPR \
        GPG_SW_NAME GPG_SW_EMAIL GPG_SW_KEY_ALGO GPG_SW_KEY_USAGE \
        GPG_SW_KEY_EXPIRE GPG_SW_EXPORT_TARGET GPG_SW_MAVEN_CONFIRM \
        XDG_CONFIG_HOME MAVEN_SETTINGS MOCK_STATE
}

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

# ---------------------------------------------------------------------------
# _jar_pkcs11_module_path / _jar_pkcs11_detect_alias
# ---------------------------------------------------------------------------

testModulePathUsesOverrideWhenSet() {
    assertEquals "$JAR_PKCS11_MODULE" "$(_jar_pkcs11_module_path)"
}

testModulePathFailsWhenOverrideMissing() {
    JAR_PKCS11_MODULE="$_WORK/nope.so" _jar_pkcs11_module_path >/dev/null 2>&1
    assertEquals 1 $?
}

testDetectAliasReturnsSingleCert() {
    MOCK_CERTS="SIGN" out=$(MOCK_CERTS="SIGN" _jar_pkcs11_detect_alias "$JAR_PKCS11_MODULE")
    assertEquals "SIGN" "$out"
}

testDetectAliasFailsWithoutCert() {
    MOCK_CERTS="" _jar_pkcs11_detect_alias "$JAR_PKCS11_MODULE" >/dev/null 2>&1
    assertEquals 1 $?
}

testDetectAliasFailsWithMultipleCerts() {
    MOCK_CERTS="SIGN OTHER" _jar_pkcs11_detect_alias "$JAR_PKCS11_MODULE" >/dev/null 2>&1
    assertEquals 1 $?
}

# ---------------------------------------------------------------------------
# jar_pkcs11_setup / jar_sign / jar_verify / jar_pkcs11_test
# ---------------------------------------------------------------------------

testSetupWritesCfgWithDetectedAlias() {
    MOCK_CERTS="SIGN" jar_pkcs11_setup >/dev/null 2>&1
    assertTrue "cfg powinien istnieć" "[ -f '$(_jar_pkcs11_cfg_path)' ]"
    assertTrue "cfg musi wskazywać moduł" "grep -qF \"$JAR_PKCS11_MODULE\" '$(_jar_pkcs11_cfg_path)'"
}

testSetupFailsWithoutCertOnCard() {
    MOCK_CERTS="" jar_pkcs11_setup >/dev/null 2>&1
    assertEquals 1 $?
    assertFalse "cfg nie powinien powstać" "[ -f '$(_jar_pkcs11_cfg_path)' ]"
}

testJarSignFailsWithoutSetup() {
    jar_sign "$_WORK/x.jar" SIGN >/dev/null 2>&1
    assertEquals 1 $?
}

testJarSignInvokesJarsignerWithoutStorepass() {
    MOCK_CERTS="SIGN" jar_pkcs11_setup >/dev/null 2>&1
    touch "$_WORK/x.jar"
    jar_sign "$_WORK/x.jar" SIGN >/dev/null 2>&1
    local calls
    calls="$(cat "$_STATE/calls")"
    assertContains "$calls" "-storetype PKCS11"
    assertContains "$calls" "NONE"
    assertNotContains "$calls" "-storepass"
}

testJarSignAutoDetectsAliasWhenOmitted() {
    export MOCK_CERTS="ONLY"
    jar_pkcs11_setup >/dev/null 2>&1
    touch "$_WORK/x.jar"
    jar_sign "$_WORK/x.jar" >/dev/null 2>&1
    assertContains "$(cat "$_STATE/calls")" "ONLY"
}

testJarSignListPrintsAllAliases() {
    export MOCK_CERTS="SIGN OTHER"
    jar_pkcs11_setup >/dev/null 2>&1
    local out
    out=$(jar_sign --list 2>&1)
    assertContains "$out" "SIGN"
    assertContains "$out" "OTHER"
}

testJarSignListFailsWithoutCert() {
    export MOCK_CERTS=""
    jar_sign -l >/dev/null 2>&1
    assertEquals 1 $?
}

testJarSignKeyFlagSelectsAlias() {
    export MOCK_CERTS="SIGN"
    jar_pkcs11_setup >/dev/null 2>&1
    touch "$_WORK/x.jar"
    jar_sign -k OTHER "$_WORK/x.jar" >/dev/null 2>&1
    assertContains "$(cat "$_STATE/calls")" "OTHER"
}

testJarSignKeyFlagOverridesPositionalAlias() {
    export MOCK_CERTS="SIGN"
    jar_pkcs11_setup >/dev/null 2>&1
    touch "$_WORK/x.jar"
    jar_sign --key OTHER "$_WORK/x.jar" SIGN >/dev/null 2>&1
    assertContains "$(cat "$_STATE/calls")" "OTHER"
}

testJarSignRejectsUnknownOption() {
    jar_sign --bogus "$_WORK/x.jar" >/dev/null 2>&1
    assertEquals 1 $?
}

testJarVerifyListPrintsAllAliases() {
    export MOCK_CERTS="SIGN OTHER"
    jar_pkcs11_setup >/dev/null 2>&1
    local out
    out=$(jar_verify --list 2>&1)
    assertContains "$out" "SIGN"
    assertContains "$out" "OTHER"
}

testJarVerifyReportsUnsigned() {
    touch "$_WORK/x.jar"
    local out
    out=$(jar_verify "$_WORK/x.jar" 2>&1)
    assertContains "$out" "unsigned"
}

testJarVerifyReportsSigned() {
    echo signed > "$_WORK/x.jar"
    local out
    out=$(jar_verify "$_WORK/x.jar" 2>&1)
    assertContains "$out" "verified"
}

testPkcs11TestSignsAndVerifiesThrowawayJar() {
    export MOCK_CERTS="SIGN"
    jar_pkcs11_setup >/dev/null 2>&1
    ( cd "$_WORK" && jar_pkcs11_test >/dev/null 2>&1 )
    assertEquals 0 $?
}

testPkcs11TestFailsWhenSignFails() {
    export MOCK_CERTS="SIGN"
    jar_pkcs11_setup >/dev/null 2>&1
    ( cd "$_WORK" && MOCK_FAIL=sign jar_pkcs11_test >/dev/null 2>&1 )
    assertEquals 1 $?
}

# ---------------------------------------------------------------------------
# ~/.m2/settings.xml — idempotentny insert oznaczonego bloku (wspólne helpery)
# ---------------------------------------------------------------------------

testEnsureSkeletonCreatesMissingFile() {
    local f="$_WORK/settings.xml"
    _maven_settings_ensure_skeleton "$f"
    assertTrue "[ -s '$f' ]"
    assertContains "$(cat "$f")" "<settings>"
}

testEnsureSkeletonLeavesExistingFileUntouched() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    local before
    before="$(cat "$f")"
    _maven_settings_ensure_skeleton "$f"
    assertEquals "$before" "$(cat "$f")"
}

testEnsureContainerAddsMissingProfiles() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    _maven_settings_ensure_container "$f" profiles
    assertContains "$(cat "$f")" "<profiles>"
    assertContains "$(cat "$f")" "nie ruszac"
}

testEnsureContainerIsIdempotent() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    _maven_settings_ensure_container "$f" profiles
    local count_before count_after
    count_before=$(grep -c '<profiles>' "$f")
    _maven_settings_ensure_container "$f" profiles
    count_after=$(grep -c '<profiles>' "$f")
    assertEquals "$count_before" "$count_after"
}

# --- jar_maven_setup / jar_maven_disable ------------------------------------

testJarMavenSetupPreservesExistingMirrorsAndComment() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_pkcs11_setup >/dev/null 2>&1
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_maven_setup >/dev/null 2>&1
    assertContains "$(cat "$f")" "nie ruszac"
    assertContains "$(cat "$f")" "koziolek.home/nexus"
    assertContains "$(cat "$f")" "jar-hw-signing"
}

testJarMavenSetupIsIdempotent() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_pkcs11_setup >/dev/null 2>&1
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_maven_setup >/dev/null 2>&1
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_maven_setup >/dev/null 2>&1
    local count
    count=$(grep -c '<id>jar-hw-signing</id>' "$f")
    assertEquals 1 "$count"
}

testJarMavenSetupWritesDetectedAlias() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    MAVEN_SETTINGS="$f" MOCK_CERTS="MYALIAS" jar_pkcs11_setup >/dev/null 2>&1
    MAVEN_SETTINGS="$f" MOCK_CERTS="MYALIAS" jar_maven_setup >/dev/null 2>&1
    assertContains "$(cat "$f")" "<jarsigner.alias>MYALIAS</jarsigner.alias>"
}

testJarMavenDisableRemovesProfileKeepsRestOfFile() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_pkcs11_setup >/dev/null 2>&1
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_maven_setup >/dev/null 2>&1
    MAVEN_SETTINGS="$f" jar_maven_disable >/dev/null 2>&1
    assertNotContains "$(cat "$f")" "jar-hw-signing"
    assertContains "$(cat "$f")" "nie ruszac"
    assertContains "$(cat "$f")" "koziolek.home/nexus"
}

testJarMavenSetupCreatesFreshFileWhenMissing() {
    local f="$_WORK/nonexistent_dir/settings.xml"
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_pkcs11_setup >/dev/null 2>&1
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_maven_setup >/dev/null 2>&1
    assertContains "$(cat "$f")" "jar-hw-signing"
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

testGpgMavenSetupFailsWithoutKeyidOrCfg() {
    local f="$_WORK/settings.xml"
    MAVEN_SETTINGS="$f" gpg_maven_setup >/dev/null 2>&1
    assertEquals 1 $?
}

testGpgMavenSetupUsesExplicitKeyid() {
    local f="$_WORK/settings.xml"
    MAVEN_SETTINGS="$f" gpg_maven_setup DEADBEEF >/dev/null 2>&1
    assertContains "$(cat "$f")" "<gpg.keyname>DEADBEEF</gpg.keyname>"
    assertContains "$(cat "$f")" "gpg-sw-signing"
}

testGpgMavenSetupFallsBackToGeneratedCfg() {
    local f="$_WORK/settings.xml"
    MOCK_FPR="CAFEBABE" gpg_sw_generate "Jan Kowalski" "jan@example.com" >/dev/null 2>&1
    MAVEN_SETTINGS="$f" gpg_maven_setup >/dev/null 2>&1
    assertContains "$(cat "$f")" "<gpg.keyname>CAFEBABE</gpg.keyname>"
}

testGpgMavenSetupPreservesExistingMirrorsAndComment() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    MAVEN_SETTINGS="$f" gpg_maven_setup DEADBEEF >/dev/null 2>&1
    assertContains "$(cat "$f")" "nie ruszac"
    assertContains "$(cat "$f")" "koziolek.home/nexus"
    assertContains "$(cat "$f")" "gpg-sw-signing"
}

testGpgMavenSetupIsIdempotent() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    MAVEN_SETTINGS="$f" gpg_maven_setup DEADBEEF >/dev/null 2>&1
    MAVEN_SETTINGS="$f" gpg_maven_setup DEADBEEF >/dev/null 2>&1
    local count
    count=$(grep -c '<id>gpg-sw-signing</id>' "$f")
    assertEquals 1 "$count"
}

testGpgMavenSetupCoexistsWithJarHwSigningProfile() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_pkcs11_setup >/dev/null 2>&1
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_maven_setup >/dev/null 2>&1
    MAVEN_SETTINGS="$f" gpg_maven_setup DEADBEEF >/dev/null 2>&1
    assertContains "$(cat "$f")" "jar-hw-signing"
    assertContains "$(cat "$f")" "gpg-sw-signing"
}

testGpgMavenDisableRemovesProfileKeepsRestOfFile() {
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
