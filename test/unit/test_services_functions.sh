#!/usr/bin/env bash
# Testy jednostkowe: services/services_functions.sh
# Zakres: update_sdkman_jdk_certs (import certyfikatu nginx do cacerts JDK zarządzanych sdkman),
#         start_services, configurate_sonar oraz statyczne sprawdzenie compose/vhosta SonarQube

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export MESSAGES_LANG=pl
export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/services/services_functions.sh"

_TEST_DIR=''
_ORIG_PATH=''

setUp() {
    _TEST_DIR="$(mktemp -d)"
    _ORIG_PATH="$PATH"

    export NGINX_DATA="$_TEST_DIR/nginx"
    export SDKMAN_DIR="$_TEST_DIR/sdkman"
    mkdir -p "$NGINX_DATA/ssl"

    KEYTOOL_LOG="$_TEST_DIR/keytool.log"
    export KEYTOOL_LOG
    unset KEYTOOL_FAIL_IMPORT

    mkdir -p "$_TEST_DIR/bin"
    cat >"$_TEST_DIR/bin/keytool" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$KEYTOOL_LOG"
for a in "$@"; do
  [ "$a" = "-delete" ] && exit 1
done
[ -n "$KEYTOOL_FAIL_IMPORT" ] && exit 1
exit 0
EOF
    chmod +x "$_TEST_DIR/bin/keytool"
    export PATH="$_TEST_DIR/bin:$PATH"

    # start_services / configurate_sonar
    ORDER_LOG="$_TEST_DIR/order.log"
    export ORDER_LOG
    unset DOCKER_FAIL_UP DOCKER_FAIL_EXEC DOCKER_COMPOSE
    export SERVICES_CONFIGURATION_DIR="$_TEST_DIR/services"
    export SONAR_DATA="$_TEST_DIR/sonar_data"
    mkdir -p "$SERVICES_CONFIGURATION_DIR/docker"
    : >"$SERVICES_CONFIGURATION_DIR/docker/docker-compose.yaml"

    cat >"$_TEST_DIR/bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >> "$ORDER_LOG"
[[ " $* " == *" up "* && -n "$DOCKER_FAIL_UP" ]] && exit 1
[[ " $* " == *" exec "* && -n "$DOCKER_FAIL_EXEC" ]] && exit 1
exit 0
EOF
    cat >"$_TEST_DIR/bin/mycompose" <<'EOF'
#!/usr/bin/env bash
echo "mycompose $*" >> "$ORDER_LOG"
exit 0
EOF
    chmod +x "$_TEST_DIR/bin/docker" "$_TEST_DIR/bin/mycompose"

    # atrapy: configurate_services i sudo (mkdir wykonywany naprawdę, reszta tylko logowana)
    CONFIGURE_RC=0
    configurate_services() {
        echo "configure" >>"$ORDER_LOG"
        return "$CONFIGURE_RC"
    }
    make_me_sudo() { :; }
    unmake_me_sudo() { :; }
    SUDO=_fake_sudo
}

_fake_sudo() {
    case "$1" in
    mkdir) "$@" ;;
    tee) echo "tee $2: $(cat)" >>"$ORDER_LOG" ;;
    *) echo "sudo $*" >>"$ORDER_LOG" ;;
    esac
}

tearDown() {
    export PATH="$_ORIG_PATH"
    rm -rf "$_TEST_DIR"
}

_make_cert() {
    printf 'fake-cert' >"$NGINX_DATA/ssl/nginx.crt"
}

_make_jdk() {
    # $1 = nazwa katalogu JDK
    mkdir -p "$SDKMAN_DIR/candidates/java/$1/lib/security"
    printf 'fake-cacerts' >"$SDKMAN_DIR/candidates/java/$1/lib/security/cacerts"
}

# ---------------------------------------------------------------------------

testMissingCertFileFails() {
    mkdir -p "$SDKMAN_DIR/candidates/java"
    local out
    out="$(update_sdkman_jdk_certs)"
    local rc=$?
    assertEquals 1 "$rc"
    assertContains "$out" "WARN"
}

testMissingSdkmanDirFails() {
    _make_cert
    local out
    out="$(update_sdkman_jdk_certs)"
    local rc=$?
    assertEquals 1 "$rc"
    assertContains "$out" "WARN"
}

testImportsCertToEachJdk() {
    _make_cert
    _make_jdk "17.0.9-tem"
    _make_jdk "21.0.1-tem"
    ln -s "17.0.9-tem" "$SDKMAN_DIR/candidates/java/current"

    update_sdkman_jdk_certs >/dev/null

    local calls
    calls="$(grep -c -- '-importcert' "$KEYTOOL_LOG")"
    assertEquals 2 "$calls"
    assertFalse "symlink 'current' nie powinien być przetwarzany" \
        "grep -q 'candidates/java/current/' '$KEYTOOL_LOG'"
}

testSkipsJdkWithoutCacerts() {
    _make_cert
    mkdir -p "$SDKMAN_DIR/candidates/java/broken-jdk"

    local out
    out="$(update_sdkman_jdk_certs)"

    assertContains "$out" "WARN"
    assertFalse "keytool nie powinien być wołany dla JDK bez cacerts" \
        "[ -f '$KEYTOOL_LOG' ]"
}

testLogsErrorWhenImportFails() {
    _make_cert
    _make_jdk "17.0.9-tem"
    export KEYTOOL_FAIL_IMPORT=1

    local out
    out="$(update_sdkman_jdk_certs)"

    assertContains "$out" "ERROR"
}

# ---------------------------------------------------------------------------
# start_services

testStartServicesMissingComposeFileFails() {
    rm -f "$SERVICES_CONFIGURATION_DIR/docker/docker-compose.yaml"
    local out rc
    out="$(start_services)"
    rc=$?
    assertEquals 1 "$rc"
    assertContains "$out" "ERROR"
    assertFalse "bez pliku compose nie wolno konfigurować ani startować" \
        "[ -f '$ORDER_LOG' ]"
}

testStartServicesConfiguresBeforeCompose() {
    start_services >/dev/null
    assertEquals "configure" "$(sed -n 1p "$ORDER_LOG")"
    assertContains "$(sed -n 2p "$ORDER_LOG")" \
        "docker compose -f $SERVICES_CONFIGURATION_DIR/docker/docker-compose.yaml up -d"
}

testStartServicesStopsWhenConfigureFails() {
    CONFIGURE_RC=3
    start_services >/dev/null
    assertEquals 3 "$?"
    assertFalse "compose nie powinien lecieć po błędzie konfiguracji" \
        "grep -q '^docker ' '$ORDER_LOG'"
}

testStartServicesPassesServiceNames() {
    start_services sonarqube nexus >/dev/null
    assertContains "$(grep ' up ' "$ORDER_LOG")" "up -d sonarqube nexus"
}

testStartServicesHonoursDockerComposeVariable() {
    export DOCKER_COMPOSE=mycompose
    start_services >/dev/null
    assertContains "$(cat "$ORDER_LOG")" "mycompose -f"
    assertFalse "przy DOCKER_COMPOSE nie wolno wołać 'docker compose'" \
        "grep -q '^docker compose' '$ORDER_LOG'"
}

testStartServicesFailsWhenComposeFails() {
    export DOCKER_FAIL_UP=1
    local out rc
    out="$(start_services)"
    rc=$?
    assertEquals 1 "$rc"
    assertContains "$out" "ERROR"
    assertFalse "po błędzie compose nie przeładowujemy nginx" \
        "grep -q 'nginx -s reload' '$ORDER_LOG'"
}

testStartServicesReloadsNginxAfterCompose() {
    start_services sonarqube >/dev/null
    assertEquals "docker exec nginx-proxy nginx -s reload" "$(tail -n 1 "$ORDER_LOG")"
}

testStartServicesNginxReloadFailureOnlyWarns() {
    export DOCKER_FAIL_EXEC=1
    local out rc
    out="$(start_services)"
    rc=$?
    assertEquals 0 "$rc"
    assertContains "$out" "WARN"
}

# ---------------------------------------------------------------------------
# configurate_sonar

testConfigurateSonarCreatesDataDirs() {
    configurate_sonar >/dev/null
    assertTrue "data" "[ -d '$SONAR_DATA/data' ]"
    assertTrue "extensions" "[ -d '$SONAR_DATA/extensions' ]"
    assertTrue "logs" "[ -d '$SONAR_DATA/logs' ]"
}

testConfigurateSonarChownsToUid1000() {
    configurate_sonar >/dev/null
    assertContains "$(cat "$ORDER_LOG")" "sudo chown -R 1000:1000 $SONAR_DATA"
}

testConfigurateSonarSetsMaxMapCount() {
    [ -e /proc/sys/vm/max_map_count ] || startSkipping
    configurate_sonar >/dev/null
    assertContains "$(cat "$ORDER_LOG")" "tee /etc/sysctl.d/99-sonarqube.conf: vm.max_map_count=262144"
    assertContains "$(cat "$ORDER_LOG")" "sudo sysctl -w vm.max_map_count=262144"
}

# ---------------------------------------------------------------------------
# statyczne sprawdzenie SonarQube w compose / nginx

_COMPOSE="$PROJECT_ROOT/services/docker/docker-compose.yaml"

testComposeSonarUsesCommunityImage() {
    assertContains "$(grep -E '^\s+image: sonarqube:' "$_COMPOSE")" "-community"
}

testComposeSonarUsesHomeDbSonarDatabase() {
    assertContains "$(cat "$_COMPOSE")" "jdbc:postgresql://home-db:5432/sonar"
}

testComposeSonarStoresDataInSonarData() {
    local content
    content="$(cat "$_COMPOSE")"
    assertContains "$content" '$SONAR_DATA/data:/opt/sonarqube/data'
    assertContains "$content" '$SONAR_DATA/extensions:/opt/sonarqube/extensions'
    assertContains "$content" '$SONAR_DATA/logs:/opt/sonarqube/logs'
}

testComposeSonarWaitsForHealthyDb() {
    local block
    block="$(sed -n '/^  sonarqube:/,/^  [a-z-]*:$/p' "$_COMPOSE")"
    assertContains "$block" "home-db:"
    assertContains "$block" "condition: service_healthy"
}

testComposeSonarContextMatchesNginxVhost() {
    local conf="$PROJECT_ROOT/services/nginx/config/includes/sonar.conf"
    assertContains "$(cat "$_COMPOSE")" "SONAR_WEB_CONTEXT: /sonar"
    assertContains "$(cat "$conf")" "proxy_pass http://sonarqube:9000/sonar/;"
    assertContains "$(cat "$conf")" "location /sonar/"
}

testComposeIsValidYaml() {
    { command -v python3 >/dev/null && python3 -c 'import yaml' 2>/dev/null; } || startSkipping
    assertTrue "python3 -c \"import yaml; yaml.safe_load(open('$_COMPOSE'))\""
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
