#!/usr/bin/env bash

function configurate_nginx() {
    make_me_sudo
    $SUDO cp -r $SERVICES_CONFIGURATION_DIR/nginx/config $NGINX_DATA/.
    $SUDO cp -r $SERVICES_CONFIGURATION_DIR/nginx/www $NGINX_DATA/.
    $SUDO cp -r $SERVICES_CONFIGURATION_DIR/nginx/ssl/certs $NGINX_DATA/ssl/. 2>/dev/null || true
    unmake_me_sudo
}
function configurate_postgres() {
    make_me_sudo
    $SUDO cp -r $SERVICES_CONFIGURATION_DIR/postgres/* $POSTGRES_DATA/.
    unmake_me_sudo
}
function configurate_nexus() {
    make_me_sudo
    if [ ! -d "$NEXUS_DATA" ] || [ ! -d "$NEXUS_DATA"/etc ]; then
        $SUDO mkdir -p $NEXUS_DATA/etc
    fi
    $SUDO cp -r $SERVICES_CONFIGURATION_DIR/nexus/etc/* $NEXUS_DATA/etc/.
    $SUDO chown -R 200:200 $NEXUS_DATA/etc/
    unmake_me_sudo
}
function configurate_sonar() {
    make_me_sudo
    $SUDO mkdir -p "$SONAR_DATA"/{data,extensions,logs}
    # obraz sonarqube działa jako uid 1000
    $SUDO chown -R 1000:1000 "$SONAR_DATA"
    # wbudowany Elasticsearch wymaga vm.max_map_count >= 262144 (tylko Linux)
    if [ -e /proc/sys/vm/max_map_count ]; then
        echo "vm.max_map_count=262144" | $SUDO tee /etc/sysctl.d/99-sonarqube.conf >/dev/null
        $SUDO sysctl -w vm.max_map_count=262144 >/dev/null
    fi
    unmake_me_sudo
}

# Importuje self-signed certyfikat nginx ($NGINX_DATA/ssl/nginx.crt) do cacerts każdego
# JDK zainstalowanego przez sdkman (~/.sdkman/candidates/java/*), żeby Maven/JVM nie
# odrzucały TLS do lokalnego Nexusa (certificate_unknown / PKIX path building failed).
# Idempotentne: usuwa istniejący alias przed importem, więc powtórne wywołanie nie duplikuje.
function update_sdkman_jdk_certs() {
    local cert_file="$NGINX_DATA/ssl/nginx.crt"
    local sdkman_java_dir="${SDKMAN_DIR:-$HOME/.sdkman}/candidates/java"
    local cert_alias="koziolek-nexus"
    local keystore_pass="changeit"

    if [ ! -f "$cert_file" ]; then
        log_warn certs.cert_missing "$cert_file"
        return 1
    fi

    if [ ! -d "$sdkman_java_dir" ]; then
        log_warn certs.no_sdkman_jdks "$sdkman_java_dir"
        return 1
    fi

    local jdk_dir cacerts
    for jdk_dir in "$sdkman_java_dir"/*/; do
        [ -L "${jdk_dir%/}" ] && continue
        cacerts="${jdk_dir}lib/security/cacerts"
        if [ ! -f "$cacerts" ]; then
            log_warn certs.no_cacerts "$jdk_dir"
            continue
        fi

        keytool -delete -noprompt \
            -alias "$cert_alias" -keystore "$cacerts" -storepass "$keystore_pass" >/dev/null 2>&1

        if keytool -importcert -noprompt -trustcacerts \
            -alias "$cert_alias" -file "$cert_file" \
            -keystore "$cacerts" -storepass "$keystore_pass" >/dev/null 2>&1; then
            log_info certs.imported "$(basename "${jdk_dir%/}")"
        else
            log_error certs.import_failed "$jdk_dir"
        fi
    done
}

function configurate_services() {
    source_if_exists ssl_setup $SERVICES_CONFIGURATION_DIR/nginx/ssl/
    source_if_exists key_setup $SERVICES_CONFIGURATION_DIR/nexus/
    configurate_postgres
    configurate_nginx
    prepare_cert
    configurate_nexus
    prepare_key
    update_sdkman_jdk_certs
    configurate_sonar
}

# Konfiguruje serwisy, a potem startuje kontenery. `up -d` odtwarza tylko serwisy
# ze zmienioną konfiguracją - już działające i niezmienione zostają nietknięte; na końcu
# przeładowuje nginx-proxy.
# Opcjonalne argumenty = nazwy serwisów (domyślnie wszystkie).
function start_services() {
    local compose_file="$SERVICES_CONFIGURATION_DIR/docker/docker-compose.yaml"

    if [ ! -f "$compose_file" ]; then
        log_error services.compose_missing "$compose_file"
        return 1
    fi

    configurate_services || return $?

    # shellcheck disable=SC2086
    ${DOCKER_COMPOSE:-docker compose} -f "$compose_file" up -d "$@" || {
        log_error services.compose_failed
        return 1
    }

    # nginx-proxy czyta conf.d z zamontowanego katalogu, więc zmiana configu nie odtwarza
    # kontenera - bez reloadu nowe vhosty nie zadziałają. configurate_services kopiuje config
    # zawsze, więc reload też jest bezwarunkowy (nawet przy starcie wybranych serwisów).
    "${DOCKER_CLI:-docker}" exec nginx-proxy nginx -s reload >/dev/null 2>&1 ||
        log_warn services.nginx_reload_failed
}


if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f configurate_services
    export -f start_services
    export -f configurate_nginx
    export -f configurate_postgres
    export -f configurate_nexus
    export -f configurate_sonar
    export -f update_sdkman_jdk_certs
else
    configurate_services "$@"
fi
