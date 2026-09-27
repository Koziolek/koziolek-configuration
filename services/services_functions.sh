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
    log_warn "Certyfikat $cert_file nie istnieje - uruchom najpierw prepare_cert"
    return 1
  fi

  if [ ! -d "$sdkman_java_dir" ]; then
    log_warn "Brak katalogu $sdkman_java_dir - sdkman nie ma zainstalowanych JDK"
    return 1
  fi

  local jdk_dir cacerts
  for jdk_dir in "$sdkman_java_dir"/*/; do
    [ -L "${jdk_dir%/}" ] && continue
    cacerts="${jdk_dir}lib/security/cacerts"
    if [ ! -f "$cacerts" ]; then
      log_warn "Brak cacerts w $jdk_dir, pomijam"
      continue
    fi

    keytool -delete -noprompt \
      -alias "$cert_alias" -keystore "$cacerts" -storepass "$keystore_pass" >/dev/null 2>&1

    if keytool -importcert -noprompt -trustcacerts \
      -alias "$cert_alias" -file "$cert_file" \
      -keystore "$cacerts" -storepass "$keystore_pass" >/dev/null 2>&1; then
      log_info "Certyfikat zaimportowany do $(basename "${jdk_dir%/}")"
    else
      log_error "Nie udało się zaimportować certyfikatu do $jdk_dir"
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
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f configurate_services
  export -f configurate_nginx
  export -f configurate_postgres
  export -f configurate_nexus
  export -f update_sdkman_jdk_certs
else
  configurate_services "$@"
fi
