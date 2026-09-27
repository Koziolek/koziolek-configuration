#!/usr/bin/env bash
# Testy integracyjne (Docker, prawdziwy JDK): weryfikuje, że certyfikat
# wygenerowany przez prepare_cert (services/nginx/ssl/ssl_setup.sh) i zaimportowany
# przez update_sdkman_jdk_certs (services/services_functions.sh) jest FAKTYCZNIE
# zaufany przez JVM - prawdziwy openssl generuje cert, prawdziwy keytool go
# importuje, prawdziwy serwer TLS (openssl s_server) go serwuje, a klient JVM
# (HttpsURLConnection) łączy się z nim przez realny handshake TLS.
#
# W przeciwieństwie do test/unit/test_services_functions.sh (tam keytool jest
# mockiem) - tu nic nie jest mockowane poza $SUDO (kontener jest rootem).
#
# Uruchamiane przez: test/run.sh --e2e-certs (osobny obraz z JDK, poza szybkim
# zestawem unit/integration na alpine - patrz test/Dockerfile-e2e-certs).

set -u

PROJECT_ROOT="/project"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
export SUDO=""

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"

# make_me_sudo/unmake_me_sudo normalnie żyją w bash/functions.d/ (pełny stos
# wymagałby X11/docker/itd. w kontenerze) - tu kontener jest rootem, więc no-op.
function make_me_sudo() { :; }
function unmake_me_sudo() { :; }
export -f make_me_sudo unmake_me_sudo

# shellcheck source=/dev/null
. "$PROJECT_ROOT/services/nginx/ssl/ssl_setup.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/services/services_functions.sh"

_CLASS_DIR=''
_WORK=''
_SERVER_PID=''
_TLS_PORT=''

# ---------------------------------------------------------------------------
# TlsCheck - minimalny klient JVM: łączy się po HTTPS i zwraca TRUSTED/UNTRUSTED
# w zależności od tego, czy JVM (dla podanego -Djavax.net.ssl.trustStore) ufa
# certyfikatowi serwera. To weryfikuje prawdziwe zaufanie JVM, nie tylko
# obecność wpisu w keystore.

oneTimeSetUp() {
    _CLASS_DIR="$(mktemp -d)"
    cat > "$_CLASS_DIR/TlsCheck.java" <<'JAVA'
import java.net.URL;
import javax.net.ssl.HttpsURLConnection;

public class TlsCheck {
    public static void main(String[] args) throws Exception {
        HttpsURLConnection conn = (HttpsURLConnection) new URL(args[0]).openConnection();
        conn.setConnectTimeout(3000);
        conn.setReadTimeout(3000);
        try {
            conn.connect();
            System.out.println("TRUSTED:" + conn.getResponseCode());
        } catch (javax.net.ssl.SSLHandshakeException e) {
            System.out.println("UNTRUSTED:" + e.getClass().getSimpleName());
        }
    }
}
JAVA
    javac -d "$_CLASS_DIR" "$_CLASS_DIR/TlsCheck.java" >/dev/null 2>&1
}

oneTimeTearDown() {
    rm -rf "$_CLASS_DIR"
}

# setUp/tearDown per-test (nie oneTimeSetUp) - każdy test dostaje własny
# NGINX_DATA/SDKMAN_DIR/serwer TLS na osobnym porcie. Testy nie zależą od
# kolejności wykonania (shunit2 sortuje testy alfabetycznie, nie wg deklaracji).
setUp() {
    _WORK="$(mktemp -d)"
    export NGINX_DATA="$_WORK/nginx"
    export SDKMAN_DIR="$_WORK/sdkman"
    mkdir -p "$NGINX_DATA/ssl" "$SDKMAN_DIR/candidates/java/temurin-real/lib/security"

    # kopia PRAWDZIWEGO cacerts z JDK obrazu (nie fake plik) - żeby keytool
    # operował na realnym, poprawnym formacie keystore
    cp "$JAVA_HOME/lib/security/cacerts" "$(_cacerts)"

    prepare_cert >/dev/null 2>&1

    _TLS_PORT=$((20000 + RANDOM % 20000))
    openssl s_server -quiet -accept "$_TLS_PORT" \
        -cert "$NGINX_DATA/ssl/nginx.crt" -key "$NGINX_DATA/ssl/nginx.key" \
        -www >"$_WORK/s_server.log" 2>&1 &
    _SERVER_PID=$!
    sleep 1
}

tearDown() {
    [ -n "$_SERVER_PID" ] && kill "$_SERVER_PID" 2>/dev/null
    wait "$_SERVER_PID" 2>/dev/null
    rm -rf "$_WORK"
}

_cacerts() {
    echo "$SDKMAN_DIR/candidates/java/temurin-real/lib/security/cacerts"
}

_check_trust() {
    java -Djavax.net.ssl.trustStore="$(_cacerts)" \
         -Djavax.net.ssl.trustStorePassword=changeit \
         -cp "$_CLASS_DIR" TlsCheck "https://127.0.0.1:$_TLS_PORT/" 2>/dev/null
}

# ---------------------------------------------------------------------------

testCertGeneratedByPrepareCert() {
    assertTrue "prepare_cert musi wygenerować nginx.crt/nginx.key" \
        "[ -f '$NGINX_DATA/ssl/nginx.crt' ] && [ -f '$NGINX_DATA/ssl/nginx.key' ]"
}

testJdkRejectsCertBeforeImport() {
    local out
    out="$(_check_trust)"
    assertContains "przed importem JVM musi odrzucić self-signed cert (PKIX/UNTRUSTED)" \
        "$out" "UNTRUSTED"
}

testUpdateSdkmanJdkCertsImportsIntoRealCacerts() {
    update_sdkman_jdk_certs >/dev/null 2>&1

    local out
    out="$(keytool -list -alias koziolek-nexus -keystore "$(_cacerts)" -storepass changeit 2>&1)"
    assertContains "keytool -list musi znaleźć zaimportowany alias koziolek-nexus" \
        "$out" "koziolek-nexus"
}

testJdkTrustsCertAfterImport() {
    update_sdkman_jdk_certs >/dev/null 2>&1

    local out
    out="$(_check_trust)"
    assertContains "po imporcie JVM musi zaufać certyfikatowi i połączyć się po TLS" \
        "$out" "TRUSTED"
}

testReimportIsIdempotent() {
    update_sdkman_jdk_certs >/dev/null 2>&1
    update_sdkman_jdk_certs >/dev/null 2>&1

    local count
    count="$(keytool -list -keystore "$(_cacerts)" -storepass changeit 2>/dev/null \
        | grep -c 'koziolek-nexus')"
    assertEquals "powtórny import nie może zduplikować aliasu" 1 "$count"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
