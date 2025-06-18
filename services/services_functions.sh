#!/usr/bin/env bash

function configurate_nginx() {
  make_me_sudo
  $SUDO cp -r $SERVICES_CONFIGURATION_DIR/nginx/* $NGINX_DATA/.
}
function configurate_postgres() {
  make_me_sudo
  $SUDO cp -r $SERVICES_CONFIGURATION_DIR/postgres/* $POSTGRES_DATA/.
}
function configurate_nexus() {
  make_me_sudo
  if [ ! -d "$NEXUS_DATA" ] && [ ! -d "$NEXUS_DATA"/etc ]; then
    $SUDO mkdir -p $NEXUS_DATA/etc
  fi
  $SUDO cp -r $SERVICES_CONFIGURATION_DIR/nexus/etc/* $NEXUS_DATA/etc/.
  $SUDO chown -R 200:200 $NEXUS_DATA/etc/
}

function configurate_services() {
  make_me_sudo
  source_if_exists ssl_setup $SERVICES_CONFIGURATION_DIR/nginx/ssl/
  source_if_exists key_setup $SERVICES_CONFIGURATION_DIR/nexus/
  configurate_postgres
  configurate_nginx
  prepare_cert
  configurate_nexus
  prepare_key
  unmake_me_sudo
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f configurate_services
  export -f configurate_nginx
  export -f configurate_postgres
  export -f configurate_nexus
else
  configurate_services "$@"
fi
