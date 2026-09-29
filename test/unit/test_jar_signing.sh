#!/usr/bin/env bash
# Testy jednostkowe: bash/functions.d/157_function_jar_signing.sh
# pkcs11-tool i jarsigner są mockowane (skrypty w PATH) — kontener testowy
# nie ma karty PIV. Blok testów "maven settings" testuje realne pliki
# (_jar_ensure_*/_jar_upsert_*/_jar_remove_* to czysta manipulacja tekstem,
# bez zależności zewnętrznych) — sprawdza że cudza zawartość (komentarze,
# mirrory) nigdy nie jest ruszana.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/157_function_jar_signing.sh"

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
}
oneTimeTearDown() { rm -rf "$_BIN"; }

_STATE=''
_WORK=''
setUp() {
    _STATE="$(mktemp -d)"
    _WORK="$(mktemp -d)"
    export MOCK_STATE="$_STATE"
    unset JAR_PKCS11_MODULE JAR_PKCS11_ALIAS MOCK_CERTS MOCK_FAIL
    export JAR_PKCS11_MODULE="$_BIN/opensc-pkcs11.so"
    touch "$JAR_PKCS11_MODULE"
    export XDG_CONFIG_HOME="$_WORK/config"
    export PATH="$_BIN:$PATH"
}
tearDown() {
    rm -rf "$_STATE" "$_WORK"
    unset JAR_PKCS11_MODULE JAR_PKCS11_ALIAS MOCK_CERTS MOCK_FAIL XDG_CONFIG_HOME MAVEN_SETTINGS MOCK_STATE
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
# ~/.m2/settings.xml — idempotentny insert oznaczonego bloku
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

testEnsureSkeletonCreatesMissingFile() {
    local f="$_WORK/settings.xml"
    _jar_ensure_settings_skeleton "$f"
    assertTrue "[ -s '$f' ]"
    assertContains "$(cat "$f")" "<settings>"
}

testEnsureSkeletonLeavesExistingFileUntouched() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    local before
    before="$(cat "$f")"
    _jar_ensure_settings_skeleton "$f"
    assertEquals "$before" "$(cat "$f")"
}

testEnsureContainerAddsMissingProfiles() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    _jar_ensure_container "$f" profiles
    assertContains "$(cat "$f")" "<profiles>"
    assertContains "$(cat "$f")" "nie ruszac"
}

testEnsureContainerIsIdempotent() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    _jar_ensure_container "$f" profiles
    local count_before count_after
    count_before=$(grep -c '<profiles>' "$f")
    _jar_ensure_container "$f" profiles
    count_after=$(grep -c '<profiles>' "$f")
    assertEquals "$count_before" "$count_after"
}

testMavenSetupPreservesExistingMirrorsAndComment() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_pkcs11_setup >/dev/null 2>&1
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_maven_setup >/dev/null 2>&1
    assertContains "$(cat "$f")" "nie ruszac"
    assertContains "$(cat "$f")" "koziolek.home/nexus"
    assertContains "$(cat "$f")" "jar-hw-signing"
}

testMavenSetupIsIdempotent() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_pkcs11_setup >/dev/null 2>&1
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_maven_setup >/dev/null 2>&1
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_maven_setup >/dev/null 2>&1
    local count
    count=$(grep -c '<id>jar-hw-signing</id>' "$f")
    assertEquals 1 "$count"
}

testMavenSetupWritesDetectedAlias() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    MAVEN_SETTINGS="$f" MOCK_CERTS="MYALIAS" jar_pkcs11_setup >/dev/null 2>&1
    MAVEN_SETTINGS="$f" MOCK_CERTS="MYALIAS" jar_maven_setup >/dev/null 2>&1
    assertContains "$(cat "$f")" "<jarsigner.alias>MYALIAS</jarsigner.alias>"
}

testMavenDisableRemovesProfileKeepsRestOfFile() {
    local f="$_WORK/settings.xml"
    _realistic_settings "$f"
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_pkcs11_setup >/dev/null 2>&1
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_maven_setup >/dev/null 2>&1
    MAVEN_SETTINGS="$f" jar_maven_disable >/dev/null 2>&1
    assertNotContains "$(cat "$f")" "jar-hw-signing"
    assertContains "$(cat "$f")" "nie ruszac"
    assertContains "$(cat "$f")" "koziolek.home/nexus"
}

testMavenSetupCreatesFreshFileWhenMissing() {
    local f="$_WORK/nonexistent_dir/settings.xml"
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_pkcs11_setup >/dev/null 2>&1
    MAVEN_SETTINGS="$f" MOCK_CERTS="SIGN" jar_maven_setup >/dev/null 2>&1
    assertContains "$(cat "$f")" "jar-hw-signing"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
