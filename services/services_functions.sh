#!/usr/bin/env bash

# Kopiuje zawartość katalogu <src> do <dst> (tworzy <dst>; pliki ukryte też, bez globu).
# Wymaga ustawionego $SUDO (make_me_sudo w wołającym). Błąd = log_error + kod 1.
function _services_copy_dir() {
    local src="$1" dst="$2"
    if ! $SUDO mkdir -p "$dst" || ! $SUDO cp -R "$src"/. "$dst"/; then
        log_error services.copy_failed "$src" "$dst"
        return 1
    fi
}

function configurate_nginx() {
    make_me_sudo
    local src="$SERVICES_CONFIGURATION_DIR/nginx" rc=0
    _services_copy_dir "$src/config" "$NGINX_DATA/config" || rc=1
    _services_copy_dir "$src/www" "$NGINX_DATA/www" || rc=1
    # katalog ssl/ jest potrzebny też prepare_cert (pisze tu nginx.crt/nginx.key)
    $SUDO mkdir -p "$NGINX_DATA/ssl" || rc=1
    # certy z repo są opcjonalne - brak katalogu to nie błąd, ale błąd kopiowania już tak
    if [ -d "$src/ssl/certs" ]; then
        _services_copy_dir "$src/ssl/certs" "$NGINX_DATA/ssl/certs" || rc=1
    fi
    unmake_me_sudo
    return "$rc"
}
function configurate_postgres() {
    make_me_sudo
    local rc=0
    _services_copy_dir "$SERVICES_CONFIGURATION_DIR/postgres" "$POSTGRES_DATA" || rc=1
    unmake_me_sudo
    return "$rc"
}
function configurate_nexus() {
    make_me_sudo
    local rc=0
    _services_copy_dir "$SERVICES_CONFIGURATION_DIR/nexus/etc" "$NEXUS_DATA/etc" || rc=1
    $SUDO chown -R 200:200 "$NEXUS_DATA/etc/" || rc=1
    unmake_me_sudo
    return "$rc"
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

    # sdkman jest opcjonalny - jego brak to nie awaria
    if [ ! -d "$sdkman_java_dir" ]; then
        log_warn certs.no_sdkman_jdks "$sdkman_java_dir"
        return 0
    fi

    local jdk_dir cacerts failed=0
    for jdk_dir in "$sdkman_java_dir"/*/; do
        # niedopasowany glob (pusty katalog) zostaje dosłownym łańcuchem z gwiazdką
        [ -d "$jdk_dir" ] || continue
        [ -L "${jdk_dir%/}" ] && continue
        cacerts="${jdk_dir}lib/security/cacerts"
        if [ ! -f "$cacerts" ]; then
            log_warn certs.no_cacerts "$jdk_dir"
            continue
        fi
        if [ ! -w "$cacerts" ]; then
            log_error certs.not_writable "$cacerts"
            failed=$((failed + 1))
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
            failed=$((failed + 1))
        fi
    done
    [ "$failed" -eq 0 ]
}

# Konfiguruje wszystkie serwisy. Każdy krok krytyczny, który się nie powiedzie, loguje błąd
# i podnosi kod wyjścia, ale pozostałe kroki nadal lecą. Import certyfikatu do JDK z sdkman
# jest krokiem miękkim - jego porażka to ostrzeżenie, bez wpływu na kod wyjścia.
function configurate_services() {
    local rc=0 step
    source_if_exists ssl_setup "$SERVICES_CONFIGURATION_DIR/nginx/ssl/"
    source_if_exists key_setup "$SERVICES_CONFIGURATION_DIR/nexus/"
    for step in configurate_postgres configurate_nginx prepare_cert configurate_nexus prepare_key; do
        "$step" || {
            log_error services.configure_step_failed "$step"
            rc=1
        }
    done
    update_sdkman_jdk_certs || log_warn services.optional_step_failed update_sdkman_jdk_certs
    configurate_sonar || {
        log_error services.configure_step_failed configurate_sonar
        rc=1
    }
    return "$rc"
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

# Restartuje serwisy z docker-compose przez restart kontenera. Bez twardej listy - nazwy
# sprawdzane względem `compose config --services`.
# Serwis nie działa -> tylko start (+ ostrzeżenie). Działa -> stop, czekanie aż stanie
# (co RESTART_SERVICE_WAIT_INTERVAL s, maks. RESTART_SERVICE_WAIT_RETRIES prób), potem start.
# Zwraca 1, jeśli któryś serwis się nie powiódł (pozostałe są i tak przetwarzane).
RESTART_SERVICE_WAIT_INTERVAL="${RESTART_SERVICE_WAIT_INTERVAL:-1}"
RESTART_SERVICE_WAIT_RETRIES="${RESTART_SERVICE_WAIT_RETRIES:-60}"

function _restart_service_running() {
    # shellcheck disable=SC2086
    [ -n "$(${DOCKER_COMPOSE:-docker compose} -f "$1" ps -q --status running "$2" 2>/dev/null)" ]
}

function restart_service() {
    local compose_file="$SERVICES_CONFIGURATION_DIR/docker/docker-compose.yaml"

    if [ $# -eq 0 ]; then
        log_error services.restart_usage
        return 1
    fi
    if [ ! -f "$compose_file" ]; then
        log_error services.compose_missing "$compose_file"
        return 1
    fi

    local known svc attempt rc=0
    # shellcheck disable=SC2086
    known="$(${DOCKER_COMPOSE:-docker compose} -f "$compose_file" config --services 2>/dev/null)"

    for svc in "$@"; do
        if ! printf '%s\n' "$known" | grep -qx -- "$svc"; then
            log_error services.unknown_service "$svc"
            rc=1
            continue
        fi

        if ! _restart_service_running "$compose_file" "$svc"; then
            log_warn services.restart_not_running "$svc"
        else
            log_info services.stopping "$svc"
            # shellcheck disable=SC2086
            if ! ${DOCKER_COMPOSE:-docker compose} -f "$compose_file" stop "$svc" >/dev/null; then
                log_error services.stop_failed "$svc"
                rc=1
                continue
            fi
            attempt=1
            while _restart_service_running "$compose_file" "$svc" &&
                [ "$attempt" -lt "$RESTART_SERVICE_WAIT_RETRIES" ]; do
                attempt=$((attempt + 1))
                sleep "$RESTART_SERVICE_WAIT_INTERVAL"
            done
            if _restart_service_running "$compose_file" "$svc"; then
                log_error services.stop_timeout "$svc" "$RESTART_SERVICE_WAIT_RETRIES"
                rc=1
                continue
            fi
            log_info services.stopped "$svc"
        fi

        # shellcheck disable=SC2086
        if ${DOCKER_COMPOSE:-docker compose} -f "$compose_file" up -d "$svc" >/dev/null; then
            log_info services.started "$svc"
        else
            log_error services.start_failed "$svc"
            rc=1
        fi
    done
    return $rc
}

# --- list_services (#180) ---
# Wypisuje linie "nazwa status" (running|stopped) dla serwisów z docker-compose.yaml.
# Lista pochodzi z `compose config --services` (nowe serwisy pojawiają się same);
# serwis bez kontenera ma status stopped.
function list_services() {
    local compose_file="$SERVICES_CONFIGURATION_DIR/docker/docker-compose.yaml"

    if [ ! -f "$compose_file" ]; then
        log_error services.compose_missing "$compose_file"
        return 1
    fi

    local all running
    # shellcheck disable=SC2086
    all="$(${DOCKER_COMPOSE:-docker compose} -f "$compose_file" config --services)" || {
        log_error services.list_failed
        return 1
    }
    # shellcheck disable=SC2086
    running="$(${DOCKER_COMPOSE:-docker compose} -f "$compose_file" ps --status running --services 2>/dev/null)"

    local name
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        if grep -qxF -- "$name" <<<"$running"; then
            echo "$name running"
        else
            echo "$name stopped"
        fi
    done <<<"$all"
}
# --- /list_services ---

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f configurate_services
    export -f configurate_nginx
    export -f configurate_postgres
    export -f configurate_nexus
    export -f configurate_sonar
    export -f update_sdkman_jdk_certs
    export -f list_services
    export -f start_services
    export -f restart_service
else
    configurate_services "$@"
fi
