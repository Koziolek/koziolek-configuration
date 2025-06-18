#!/usr/bin/env bash

function prepare_key(){
  local secret_file_template="$SERVICES_CONFIGURATION_DIR/nexus/etc/keystore/nexus.secrets.json.template"
  local secret_file="$NEXUS_DATA/etc/keystore/nexus.secrets.json"
  local generated_key=$(openssl rand -base64 32)
  if [ ! -f $secret_file_template ]; then
    log_wanr "$secret_file_template file not found"
    return 1
  fi
  make_me_sudo
  $SUDO cp $secret_file_template $secret_file
  $SUDO sed -i "s|%%BASED_KEY%%|${generated_key}|g" $secret_file
}


if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f prepare_key
else
  prepare_key "$@"
fi
