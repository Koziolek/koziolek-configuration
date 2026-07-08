#!/usr/bin/env bash

function prepare_key(){
  local secret_file_template="$SERVICES_CONFIGURATION_DIR/nexus/etc/keystore/nexus.secrets.json.template"
  local secret_file="$NEXUS_DATA/etc/keystore/nexus.secrets.json"
  local generated_key
  generated_key=$(openssl rand -base64 32)
  if [ ! -f "$secret_file_template" ]; then
    log_warn "$secret_file_template file not found"
    return 1
  fi

  # Podstawienie robione czysto w bashu (parameter expansion), nie przez
  # `sed -i "s|X|$generated_key|g"` — tam sekret trafia jako literalny argument
  # do argv procesu sed, widoczny dla innych userów przez ps/`/proc/*/cmdline`
  # przez cały czas trwania tej komendy. Wynik leci do pliku przez stdin
  # builtina printf w pipe (nie exec'owany osobny proces), więc nigdzie
  # w argv żadnego procesu sekret się nie pojawia.
  local template_content rendered
  template_content="$(cat "$secret_file_template")"
  rendered="${template_content//%%BASED_KEY%%/$generated_key}"

  make_me_sudo
  printf '%s' "$rendered" | $SUDO tee "$secret_file" > /dev/null
  $SUDO chmod 600 "$secret_file"
  $SUDO chown 200:200 "$secret_file"
  unmake_me_sudo
}


if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f prepare_key
else
  prepare_key "$@"
fi
