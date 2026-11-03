#!/usr/bin/env bash
# Testy jednostkowe: services/services_functions.sh
# Zakres: update_sdkman_jdk_certs (import certyfikatu nginx do cacerts JDK zarządzanych sdkman),
#         start_services, configure_sonar oraz statyczne sprawdzenie compose/vhosta SonarQube

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export MESSAGES_LANG=pl
export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/005_function_messages.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/services/services_functions.sh"

_REAL_CONFIGURE_SERVICES="$(declare -f configure_services)"
# prawdziwe funkcje kroków - testy z atrapami (_use_real_configure_services) nadpisują je globalnie,
# więc przywracamy po każdym teście (kolejność testów nie może mieć znaczenia)
_REAL_STEP_FUNCS="$(declare -f configure_postgres configure_nginx configure_nexus configure_jenkins configure_sonar update_sdkman_jdk_certs)"
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
    unset KEYTOOL_FAIL_IMPORT KEYTOOL_FAIL_ON

    mkdir -p "$_TEST_DIR/bin"
    cat >"$_TEST_DIR/bin/keytool" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$KEYTOOL_LOG"
for a in "$@"; do
  [ "$a" = "-delete" ] && exit 1
done
[ -n "$KEYTOOL_FAIL_IMPORT" ] && exit 1
[ -n "$KEYTOOL_FAIL_ON" ] && [[ "$*" == *"$KEYTOOL_FAIL_ON"* ]] && exit 1
exit 0
EOF
    chmod +x "$_TEST_DIR/bin/keytool"
    export PATH="$_TEST_DIR/bin:$PATH"

    # start_services / configure_sonar
    ORDER_LOG="$_TEST_DIR/order.log"
    export ORDER_LOG
    unset DOCKER_FAIL_UP DOCKER_FAIL_EXEC DOCKER_COMPOSE DOCKER_NGINX_DOWN DOCKER_FAIL_NGINX_T
    export SERVICES_CONFIGURATION_DIR="$_TEST_DIR/services"
    export SONAR_DATA="$_TEST_DIR/sonar_data"
    export JENKINS_DATA="$_TEST_DIR/jenkins_data"
    mkdir -p "$SERVICES_CONFIGURATION_DIR/docker"
    : >"$SERVICES_CONFIGURATION_DIR/docker/docker-compose.yaml"

    cat >"$_TEST_DIR/bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >> "$ORDER_LOG"
[[ " $* " == *" up "* && -n "$DOCKER_FAIL_UP" ]] && exit 1
[[ " $* " == *" ps "* ]] && { [ -z "$DOCKER_NGINX_DOWN" ] && echo abc123; exit 0; }
[[ " $* " == *" nginx -t "* && -n "$DOCKER_FAIL_NGINX_T" ]] && { echo "nginx: [emerg] bad directive"; exit 1; }
[[ " $* " == *" nginx -s reload "* && -n "$DOCKER_FAIL_EXEC" ]] && exit 1
exit 0
EOF
    cat >"$_TEST_DIR/bin/mycompose" <<'EOF'
#!/usr/bin/env bash
echo "mycompose $*" >> "$ORDER_LOG"
exit 0
EOF
    chmod +x "$_TEST_DIR/bin/docker" "$_TEST_DIR/bin/mycompose"

    # atrapy: configure_services i sudo (mkdir wykonywany naprawdę, reszta tylko logowana)
    CONFIGURE_RC=0
    configure_services() {
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
    eval "$_REAL_STEP_FUNCS"
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

testMissingSdkmanDirIsOnlyAWarning() {
    _make_cert
    local out
    out="$(update_sdkman_jdk_certs)"
    local rc=$?
    assertEquals 0 "$rc"
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

testStartServicesTestsNginxConfigBeforeReload() {
    start_services >/dev/null
    assertEquals "docker exec nginx-proxy nginx -t" "$(tail -n 2 "$ORDER_LOG" | head -n 1)"
    assertEquals "docker exec nginx-proxy nginx -s reload" "$(tail -n 1 "$ORDER_LOG")"
}

testStartServicesSkipsReloadWhenNginxNotRunning() {
    export DOCKER_NGINX_DOWN=1
    local out rc
    out="$(start_services)"
    rc=$?
    assertEquals 0 "$rc"
    assertFalse "bez działającego nginx-proxy brak exec" "grep -q ' exec ' '$ORDER_LOG'"
    assertNotContains "bez ostrzeżenia o reloadzie" "$out" "WARN"
}

testStartServicesInvalidNginxConfigErrorsWithoutReload() {
    export DOCKER_FAIL_NGINX_T=1
    local out rc
    out="$(start_services)"
    rc=$?
    assertEquals 0 "$rc"
    assertContains "$out" "ERROR"
    assertContains "$out" "bad directive"
    assertFalse "błędny config = brak reloadu" "grep -q 'nginx -s reload' '$ORDER_LOG'"
}

# ---------------------------------------------------------------------------
# configure_sonar

testConfigurateSonarCreatesDataDirs() {
    configure_sonar >/dev/null
    assertTrue "data" "[ -d '$SONAR_DATA/data' ]"
    assertTrue "extensions" "[ -d '$SONAR_DATA/extensions' ]"
    assertTrue "logs" "[ -d '$SONAR_DATA/logs' ]"
}

testConfigurateSonarChownsToUid1000() {
    configure_sonar >/dev/null
    assertContains "$(cat "$ORDER_LOG")" "sudo chown -R 1000:1000 $SONAR_DATA"
}

testConfigurateSonarSetsMaxMapCount() {
    [ -e /proc/sys/vm/max_map_count ] || startSkipping
    configure_sonar >/dev/null
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

# --- list_services (#180) ---
_setup_compose_mock() {
    # $1 = serwisy z compose (spacje), $2 = działające (spacje)
    export MOCK_ALL="$1" MOCK_RUNNING="$2"
    cat >"$_TEST_DIR/bin/mycompose" <<'EOF2'
#!/usr/bin/env bash
if [[ " $* " == *" config "* ]]; then
    [ -n "$MOCK_CONFIG_FAIL" ] && exit 1
    for s in $MOCK_ALL; do echo "$s"; done
elif [[ " $* " == *" ps "* ]]; then
    for s in $MOCK_RUNNING; do echo "$s"; done
fi
exit 0
EOF2
    chmod +x "$_TEST_DIR/bin/mycompose"
    export DOCKER_COMPOSE=mycompose
}

testListServicesRunning() {
    _setup_compose_mock "nginx postgres" "nginx postgres"
    assertEquals "$(printf 'nginx running\npostgres running')" "$(list_services)"
}

testListServicesStopped() {
    _setup_compose_mock "nginx postgres" "nginx"
    assertEquals "$(printf 'nginx running\npostgres stopped')" "$(list_services)"
}

testListServicesNoContainerIsStopped() {
    _setup_compose_mock "nginx" ""
    assertEquals "nginx stopped" "$(list_services)"
}

testListServicesPicksUpNewService() {
    _setup_compose_mock "nginx brandnew" "brandnew"
    assertContains "$(list_services)" "brandnew running"
    assertContains "$(list_services)" "nginx stopped"
}

testListServicesDoesNotMatchPrefix() {
    _setup_compose_mock "nginx nginx-proxy" "nginx-proxy"
    assertEquals "$(printf 'nginx stopped\nnginx-proxy running')" "$(list_services)"
}

testListServicesMissingComposeFile() {
    rm -f "$SERVICES_CONFIGURATION_DIR/docker/docker-compose.yaml"
    local out rc
    out="$(list_services)"
    rc=$?
    assertEquals 1 "$rc"
    assertContains "$out" "Brak pliku docker-compose"
}

testListServicesConfigFailure() {
    _setup_compose_mock "nginx" "nginx"
    export MOCK_CONFIG_FAIL=1
    local out rc
    out="$(list_services)"
    rc=$?
    unset MOCK_CONFIG_FAIL
    assertEquals 1 "$rc"
    assertContains "$out" "ERROR"
}
# --- /list_services ---

# --- configure_nginx / configure_postgres / configure_nexus (#183) ---
# SUDO wykonuje polecenia naprawdę (bez sudo); ścieżki celowo ze spacjami.
_real_sudo() { "$@"; }
_failing_cp_sudo() {
    [ "$1" = cp ] && return 1
    "$@"
}

_setup_copy_dirs() {
    export SERVICES_CONFIGURATION_DIR="$_TEST_DIR/my services"
    export NGINX_DATA="$_TEST_DIR/data dir/nginx"
    export POSTGRES_DATA="$_TEST_DIR/data dir/postgres"
    export NEXUS_DATA="$_TEST_DIR/data dir/nexus"
    mkdir -p "$SERVICES_CONFIGURATION_DIR"/{nginx/config,nginx/www,postgres,nexus/etc}
    echo main >"$SERVICES_CONFIGURATION_DIR/nginx/config/main.conf"
    echo html >"$SERVICES_CONFIGURATION_DIR/nginx/www/index.html"
    echo sql >"$SERVICES_CONFIGURATION_DIR/postgres/init.sql"
    echo hidden >"$SERVICES_CONFIGURATION_DIR/postgres/.hidden"
    echo nexus >"$SERVICES_CONFIGURATION_DIR/nexus/etc/nexus.properties"
    SUDO=_real_sudo
}

testConfigurateNginxCopiesWithSpacesAndCreatesMissingDirs() {
    _setup_copy_dirs
    rm -rf "$NGINX_DATA" # czysta maszyna: brak $NGINX_DATA i ssl/
    configure_nginx >/dev/null
    assertEquals 0 $?
    assertTrue "config" "[ -f '$NGINX_DATA/config/main.conf' ]"
    assertTrue "www" "[ -f '$NGINX_DATA/www/index.html' ]"
    assertTrue "ssl dir (potrzebny prepare_cert)" "[ -d '$NGINX_DATA/ssl' ]"
}

testConfigurateNginxNoCertsDirIsNotAnError() {
    _setup_copy_dirs
    local out
    out="$(configure_nginx)"
    assertEquals 0 $?
    assertNotContains "$out" "ERROR"
}

testConfigurateNginxCopiesCertsWhenPresent() {
    _setup_copy_dirs
    mkdir -p "$SERVICES_CONFIGURATION_DIR/nginx/ssl/certs"
    echo ca >"$SERVICES_CONFIGURATION_DIR/nginx/ssl/certs/ca.crt"
    configure_nginx >/dev/null
    assertEquals 0 $?
    assertTrue "certs" "[ -f '$NGINX_DATA/ssl/certs/ca.crt' ]"
}

testConfigurateNginxCertCopyFailureIsReported() {
    _setup_copy_dirs
    mkdir -p "$SERVICES_CONFIGURATION_DIR/nginx/ssl/certs"
    SUDO=_failing_cp_sudo
    local out
    out="$(configure_nginx)"
    assertEquals 1 $?
    assertContains "$out" "ERROR"
    assertContains "$out" "Nie udało się skopiować"
}

testConfigurateNginxFailsWhenSourceMissing() {
    _setup_copy_dirs
    rm -rf "$SERVICES_CONFIGURATION_DIR/nginx/www"
    local out
    out="$(configure_nginx)"
    assertEquals 1 $?
    assertContains "$out" "ERROR"
}

testConfigurateNginxCreatesDirsAndStillRunsPrepareCertTarget() {
    _setup_copy_dirs
    rm -rf "$NGINX_DATA"
    configure_nginx >/dev/null
    # prepare_cert zapisuje tutaj - katalog musi istnieć
    assertTrue "zapis do ssl" "echo x > '$NGINX_DATA/ssl/nginx.crt'"
}

testConfiguratePostgresCopiesHiddenFilesAndCreatesDir() {
    _setup_copy_dirs
    configure_postgres >/dev/null
    assertEquals 0 $?
    assertTrue "init.sql" "[ -f '$POSTGRES_DATA/init.sql' ]"
    assertTrue "plik ukryty" "[ -f '$POSTGRES_DATA/.hidden' ]"
}

testConfiguratePostgresEmptySourceDoesNotCopyLiteralGlob() {
    _setup_copy_dirs
    rm -rf "$SERVICES_CONFIGURATION_DIR/postgres"/* "$SERVICES_CONFIGURATION_DIR/postgres"/.hidden
    configure_postgres >/dev/null
    assertEquals 0 $?
    assertFalse "literalna gwiazdka" "[ -e '$POSTGRES_DATA/*' ]"
}

testConfiguratePostgresCopyFailureReturnsError() {
    _setup_copy_dirs
    SUDO=_failing_cp_sudo
    local out
    out="$(configure_postgres)"
    assertEquals 1 $?
    assertContains "$out" "ERROR"
}

testConfigurateNexusCopiesWithSpacesAndChowns() {
    _setup_copy_dirs
    SUDO=_nexus_sudo
    configure_nexus >/dev/null
    assertEquals 0 $?
    assertTrue "etc" "[ -f '$NEXUS_DATA/etc/nexus.properties' ]"
    assertContains "$(cat "$ORDER_LOG")" "chown -R 200:200 $NEXUS_DATA/etc/"
}
_nexus_sudo() {
    # chown tylko logowany (bez roota), reszta naprawdę
    if [ "$1" = chown ]; then
        echo "chown $*" >>"$ORDER_LOG"
        return 0
    fi
    "$@"
}
# --- /configure_* (#183) ---

# --- propagacja błędów (#184) ---
testImportFailureOnOneJdkReturnsErrorButContinues() {
    _make_cert
    _make_jdk jdk-a
    _make_jdk jdk-b
    export KEYTOOL_FAIL_ON="candidates/java/jdk-a/"
    local out
    out="$(update_sdkman_jdk_certs)"
    assertEquals 1 $?
    assertContains "$out" "ERROR"
    assertContains "kolejny JDK nadal importowany" "$out" "jdk-b"
}

testImportFailureOnLastJdkAlsoReturnsError() {
    _make_cert
    _make_jdk jdk-a
    _make_jdk jdk-b
    export KEYTOOL_FAIL_ON="candidates/java/jdk-b/"
    update_sdkman_jdk_certs >/dev/null
    assertEquals 1 $?
}

testEmptyJdkDirGivesNoGlobWarning() {
    _make_cert
    mkdir -p "$SDKMAN_DIR/candidates/java"
    local out
    out="$(update_sdkman_jdk_certs)"
    assertEquals 0 $?
    assertNotContains "$out" "*"
}

testReadOnlyCacertsIsReportedWithReason() {
    [ "$(id -u)" -eq 0 ] && startSkipping
    _make_cert
    _make_jdk jdk-a
    chmod a-w "$SDKMAN_DIR/candidates/java/jdk-a/lib/security/cacerts"
    local out
    out="$(update_sdkman_jdk_certs)"
    assertEquals 1 $?
    assertContains "$out" "Brak prawa zapisu do cacerts"
}

# prawdziwy configure_services (setUp podmienia go atrapą) z atrapami kroków
_use_real_configure_services() {
    eval "$_REAL_CONFIGURE_SERVICES"
    source_if_exists() { :; }
    STEPS_LOG="$_TEST_DIR/steps.log"
    : >"$STEPS_LOG"
    local s
    for s in configure_postgres configure_nginx prepare_cert configure_nexus \
        prepare_key configure_jenkins update_sdkman_jdk_certs configure_sonar; do
        eval "$s() { echo $s >>\"\$STEPS_LOG\"; return \"\${RC_$s:-0}\"; }"
    done
    unset RC_configure_postgres RC_configure_nginx RC_prepare_cert RC_configure_nexus \
        RC_prepare_key RC_configure_jenkins RC_update_sdkman_jdk_certs RC_configure_sonar
}

testConfigurateServicesSucceedsWhenAllStepsSucceed() {
    _use_real_configure_services
    configure_services >/dev/null
    assertEquals 0 $?
    assertEquals 8 "$(wc -l <"$STEPS_LOG")"
}

testConfigurateServicesReturnsErrorWhenCriticalStepFailsButRunsRest() {
    _use_real_configure_services
    local step
    for step in configure_postgres configure_nginx prepare_cert configure_nexus prepare_key configure_jenkins configure_sonar; do
        _use_real_configure_services
        eval "RC_$step=1"
        export "RC_$step"
        local out
        out="$(configure_services)"
        assertEquals "rc dla $step" 1 $?
        assertContains "$out" "Krok konfiguracji nie powiódł się: $step"
        assertEquals "pozostałe kroki lecą ($step)" 8 "$(wc -l <"$STEPS_LOG")"
        unset "RC_$step"
    done
}

testConfigurateServicesTreatsJdkCertsAsSoftStep() {
    _use_real_configure_services
    export RC_update_sdkman_jdk_certs=1
    local out
    out="$(configure_services)"
    assertEquals 0 $?
    assertContains "$out" "WARN"
    unset RC_update_sdkman_jdk_certs
}

testStartServicesDoesNotRunComposeWhenRealConfigureFails() {
    _use_real_configure_services
    export RC_configure_nginx=1
    : >"$ORDER_LOG"
    start_services >/dev/null
    assertEquals 1 $?
    assertNotContains "$(cat "$ORDER_LOG")" "up -d"
    unset RC_configure_nginx
}
# --- /propagacja błędów (#184) ---

# --- jedna sesja sudo na configure_services (#185) ---
# Prawdziwe make/unmake_me_sudo (setUp podmienia je atrapami) + atrapa `sudo` liczącą `-K`.
_use_real_sudo_session() {
    # shellcheck source=/dev/null
    . "$PROJECT_ROOT/bash/functions.d/020_function_process.sh"
    unset _SUDO_DEPTH
    SUDO_LOG="$_TEST_DIR/sudo.log"
    : >"$SUDO_LOG"
    printf '#!/usr/bin/env bash\necho "sudo $*" >> "%s"\n' "$SUDO_LOG" >"$_TEST_DIR/bin/sudo"
    chmod +x "$_TEST_DIR/bin/sudo"
    _use_real_configure_services
    # każdy krok sam otwiera i zamyka sesję sudo, jak prawdziwe configure_*
    local s
    for s in configure_postgres configure_nginx prepare_cert configure_nexus \
        prepare_key configure_jenkins configure_sonar; do
        eval "$s() { make_me_sudo; echo $s >>\"\$STEPS_LOG\"; local r=\"\${RC_$s:-0}\"; unmake_me_sudo; return \"\$r\"; }"
    done
}

testConfigurateServicesRevokesSudoOnce() {
    [ "$(id -u)" -eq 0 ] && startSkipping
    _use_real_sudo_session
    configure_services >/dev/null
    assertEquals 0 $?
    assertEquals 1 "$(grep -c -- 'sudo -K' "$SUDO_LOG")"
    assertNull "SUDO nie wycieka" "${SUDO:-}"
}

testConfigurateServicesRevokesSudoOnceEvenWhenStepFails() {
    [ "$(id -u)" -eq 0 ] && startSkipping
    _use_real_sudo_session
    export RC_configure_nginx=1
    configure_services >/dev/null
    assertEquals 1 $?
    assertEquals 1 "$(grep -c -- 'sudo -K' "$SUDO_LOG")"
    assertNull "SUDO nie wycieka" "${SUDO:-}"
    assertNull "RESET_SUDO nie wycieka" "${RESET_SUDO:-}"
    unset RC_configure_nginx
}
# --- /jedna sesja sudo (#185) ---

# --- zmiana nazw configurate_* -> configure_* (#188) ---
testDeprecatedNamesDelegateAndWarn() {
    local name new out
    for name in services nginx postgres nexus sonar; do
        new="configure_$name"
        : >"$ORDER_LOG"
        eval "$new() { echo \"$new \$*\" >>\"\$ORDER_LOG\"; return 0; }"
        out="$("configurate_$name" arg1 arg2 2>&1)"
        assertEquals "rc configurate_$name" 0 $?
        assertContains "$out" "WARN"
        assertContains "$out" "configurate_$name"
        assertContains "$out" "$new"
        assertContains "deleguje z argumentami" "$(cat "$ORDER_LOG")" "$new arg1 arg2"
    done
}

testDeprecatedWrapperPropagatesReturnCode() {
    configure_services() { return 7; }
    configurate_services >/dev/null 2>&1
    assertEquals 7 $?
}

testBothNamesAreFunctionsAndExported() {
    local name
    for name in services nginx postgres nexus sonar; do
        assertEquals "function" "$(type -t "configure_$name")"
        assertEquals "function" "$(type -t "configurate_$name")"
    done
    # eksport: proces potomny widzi obie nazwy oraz funkcje pomocnicze, od których zależą
    local out
    out="$(bash -c 'for f in configure_services configurate_services configure_nginx configurate_nginx \
        _services_copy_dir _services_deprecated_name _services_reload_nginx _services_container_running \
        _restart_service_running _services_compose; do declare -F "$f" >/dev/null || echo "BRAK:$f"; done')"
    assertEquals "" "$out"
}

testStartServicesCallsNewName() {
    : >"$ORDER_LOG"
    start_services >/dev/null
    assertContains "$(cat "$ORDER_LOG")" "configure"
    assertNotContains "$(declare -f start_services)" "configurate_"
}
# --- /zmiana nazw (#188) ---

# --- Jenkins (#182) ---
_JENKINS_DIR="$PROJECT_ROOT/services/jenkins"
_jenkins_block() { sed -n '/^  jenkins:/,/^  [a-z-]*:$/p' "$_COMPOSE"; }

_setup_jenkins_src() {
    export SERVICES_CONFIGURATION_DIR="$_TEST_DIR/my services"
    mkdir -p "$SERVICES_CONFIGURATION_DIR/jenkins/casc"
    echo "jenkins: {}" >"$SERVICES_CONFIGURATION_DIR/jenkins/casc/jenkins.yaml"
    export JENKINS_ADMIN_USER=admin JENKINS_ADMIN_PASSWORD=s3cret
    SUDO=_real_sudo
}
_jenkins_sudo() {
    if [ "$1" = chown ]; then
        echo "sudo $*" >>"$ORDER_LOG"
        return 0
    fi
    "$@"
}

testConfigureJenkinsCopiesCascAndChownsToUid1000() {
    _setup_jenkins_src
    SUDO=_jenkins_sudo
    configure_jenkins >/dev/null
    assertEquals 0 $?
    assertTrue "casc skopiowany" "[ -f '$JENKINS_DATA/casc/jenkins.yaml' ]"
    assertContains "$(cat "$ORDER_LOG")" "sudo chown -R 1000:1000 $JENKINS_DATA"
}

testConfigureJenkinsFailsWithoutAdminCredentials() {
    _setup_jenkins_src
    local var out
    for var in JENKINS_ADMIN_USER JENKINS_ADMIN_PASSWORD; do
        _setup_jenkins_src
        unset "$var"
        out="$(configure_jenkins)"
        assertEquals "rc bez $var" 1 $?
        assertContains "$out" "JENKINS_ADMIN_USER"
        assertFalse "nic nie kopiuje bez poświadczeń" "[ -e '$JENKINS_DATA/casc' ]"
    done
}

testConfigureJenkinsCopyFailureReturnsError() {
    _setup_jenkins_src
    SUDO=_failing_cp_sudo
    local out
    out="$(configure_jenkins)"
    assertEquals 1 $?
    assertContains "$out" "ERROR"
}

testComposeJenkinsPinsLtsTagAndDoesNotUseLatest() {
    local block
    block="$(_jenkins_block)"
    assertContains "$block" "image: koziolek/jenkins:2.580.2-lts-jdk21"
    assertNotContains "$block" ":latest"
    assertContains "$(cat "$_JENKINS_DIR/Dockerfile")" "FROM jenkins/jenkins:2.580.2-lts-jdk21"
}

testComposeJenkinsStoresDataInJenkinsDataAndWaitsForHealthyDb() {
    local block
    block="$(_jenkins_block)"
    assertContains "$block" '$JENKINS_DATA:/var/jenkins_home'
    assertContains "$block" "condition: service_healthy"
    assertContains "$block" 'DB_USERNAME: ${DB_USERNAME}'
    assertContains "$block" "service-network"
}

testComposeJenkinsDoesNotLoadWholeSenvFile() {
    assertNotContains "$(_jenkins_block)" "env_file:"
}

testComposeJenkinsPrefixMatchesNginxVhostAndHealthcheck() {
    local conf="$PROJECT_ROOT/services/nginx/config/includes/jenkins.conf"
    assertContains "$(_jenkins_block)" "JENKINS_OPTS: --prefix=/jenkins"
    assertContains "$(_jenkins_block)" "localhost:8080/jenkins/login"
    assertContains "$(cat "$conf")" "location /jenkins/"
    assertContains "$(cat "$conf")" "http://jenkins:8080"
    assertContains "$(cat "$conf")" "proxy_buffering off"
}

testNginxJenkinsUpstreamIsResolvedLazily() {
    local conf="$PROJECT_ROOT/services/nginx/config/includes/jenkins.conf"
    assertContains "nginx nie może paść, gdy kontenera jenkins brak" "$(cat "$conf")" "set \$jenkins_upstream"
    assertContains "$(cat "$conf")" "resolver 127.0.0.11"
}

testJenkinsLinkOnIndexPage() {
    assertContains "$(cat "$PROJECT_ROOT/services/nginx/www/index.html")" "/jenkins"
}

testPluginsArePinnedAndIncludeDatabasePlugins() {
    local plugins
    plugins="$(grep -v '^#' "$_JENKINS_DIR/plugins.txt" | grep -v '^$')"
    local line
    while IFS= read -r line; do
        assertContains "wersja przypięta: $line" "$line" ":"
    done <<<"$plugins"
    for line in configuration-as-code database-postgresql postgresql-api junit-sql-storage pipeline-maven pipeline-maven-database adoptopenjdk maven-plugin; do
        assertContains "$plugins" "$line:"
    done
}

testCascUsesHomeDbAndNoHardcodedSecrets() {
    local casc
    casc="$(cat "$_JENKINS_DIR/casc/jenkins.yaml")"
    assertContains "$casc" "jdbc:postgresql://home-db:5432/jenkins"
    assertContains "$casc" 'hostname: "home-db"'
    assertContains "$casc" 'storage: "database"'
    assertContains "$casc" 'JdbcCredentialsId: "home-db"'
    assertContains "$casc" '${JENKINS_ADMIN_PASSWORD}'
    assertContains "$casc" '${DB_PASSWORD}'
    assertContains "$casc" 'allowsSignup: false'
    assertContains "$casc" 'allowAnonymousRead: false'
}

testCascDeclaresToolInstallersWithOverridableVersions() {
    local casc
    casc="$(cat "$_JENKINS_DIR/casc/jenkins.yaml")"
    assertContains "$casc" "adoptOpenJdkInstaller"
    assertContains "$casc" '${JENKINS_JDK_ID:-'
    assertContains "$casc" '${JENKINS_MAVEN_ID:-'
}

testSenvTemplateHasJenkinsAdminKeys() {
    local tpl
    tpl="$(cat "$PROJECT_ROOT/.senv.template")"
    assertContains "$tpl" "export JENKINS_ADMIN_USER="
    assertContains "$tpl" "export JENKINS_ADMIN_PASSWORD="
}

testJenkinsDataExportedByServicesMain() {
    assertContains "$(cat "$PROJECT_ROOT/services/main.sh")" 'export JENKINS_DATA=${SERVICES_DATA}/jenkins_data'
}
# --- /Jenkins (#182) ---

# --- healthchecki nexus i pgadmin (#196) ---
_service_block() { sed -n "/^  $1:/,/^  [a-z-]*:\$/p" "$_COMPOSE"; }

testNexusHealthcheckUsesContextPathFromNexusProperties() {
    local ctx
    ctx="$(sed -n 's/^nexus-context-path=//p' "$PROJECT_ROOT/services/nexus/etc/nexus.properties")"
    assertNotNull "nexus-context-path ustawiony" "$ctx"
    assertContains "healthcheck musi iść pod prefiks z nexus.properties" \
        "$(_service_block nexus)" "http://localhost:8081${ctx}/service/rest/v1/status"
    assertNotContains "bez prefiksu daje 404" "$(_service_block nexus | grep 'test:')" "8081/service/rest"
}

testPgadminHealthcheckDoesNotUseMissingCurl() {
    local test_line
    test_line="$(_service_block pgadmin | grep 'test:')"
    assertNotContains "obraz pgadmin4 nie ma curl" "$test_line" "curl"
    assertNotContains "obraz pgadmin4 nie ma wget" "$test_line" "wget"
    assertContains "$test_line" "python3"
    assertContains "ping aplikacji (bez prefiksu nginx)" "$test_line" "http://localhost/misc/ping"
}

testPgadminHealthcheckFailsOnHttpErrors() {
    # urlopen rzuca wyjątek przy 4xx/5xx, więc python3 kończy się kodem != 0 (jak curl -f)
    command -v python3 >/dev/null || startSkipping
    local srv_dir port pid
    srv_dir="$(mktemp -d)"
    port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
    mkdir -p "$srv_dir/misc" && echo pong >"$srv_dir/misc/ping"
    (cd "$srv_dir" && python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1) &
    pid=$!
    sleep 1
    python3 -c "import urllib.request as u; u.urlopen('http://127.0.0.1:$port/misc/ping')" 2>/dev/null
    assertEquals "200 -> kod 0" 0 $?
    python3 -c "import urllib.request as u; u.urlopen('http://127.0.0.1:$port/misc/nie-ma')" 2>/dev/null
    assertNotEquals "404 -> kod != 0" 0 $?
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    rm -rf "$srv_dir"
}
# --- /healthchecki (#196) ---

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
