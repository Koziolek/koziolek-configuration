#!/usr/bin/env bash

#;
# Przygotowuje klucze dla domowego serwera. Co do zasady powinno się to odpalać jedynie raz,
# ale można regenerować klucze. Uruchamia się jako root.
# ## Użycie
# ```
# $ prepare_cert
# ```
# Alternatywnie można zrobić sourcing do skryptu i tam wywołać jak zwykłą funkcję.
#;
function prepare_cert() {
  make_me_sudo
  # Generuj self-signed certificate
  $SUDO openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout $NGINX_DATA/ssl/nginx.key \
    -out $NGINX_DATA/ssl/nginx.crt \
    -subj "/C=PL/ST=Lower Silesia/L=Wroclaw/O=Home/OU=IT/CN=koziolek.home" \
    -addext "subjectAltName=DNS:koziolek.home,DNS:home,IP:127.0.0.1"

  log_info "
  SSL certificates generated successfully!
    Certificate: $NGINX_DATA/ssl/nginx.crt
    Private key: $NGINX_DATA/ssl/nginx.key
  "

  # Ustaw odpowiednie uprawnienia
  $SUDO chmod 600 $NGINX_DATA/ssl/nginx.key
  $SUDO chmod 644 $NGINX_DATA/ssl/nginx.crt

  unmake_me_sudo
  log_info "
  Next steps:
  1. Add '127.0.0.1 home' to your /etc/hosts file
  2. Run: docker-compose up -d
  3. Access services at:
     - https://koziolek.home/artifactory (or https://home/artifactory)
     - https://koziolek.home/postgres (or https://home/postgres)"
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f prepare_cert
else
  prepare_cert "$@"
fi
