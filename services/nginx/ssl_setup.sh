#!/usr/bin/env bash

function prepare_cert() {
  # Generuj self-signed certificate
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout $NGINX_DATA/ssl/server.key \
    -out $NGINX_DATA/ssl/server.crt \
    -subj "/C=PL/ST=Lower Silesia/L=Wroclaw/O=Home/OU=IT/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,DNS:home,IP:127.0.0.1"

  log_info "
  SSL certificates generated successfully!
    Certificate: $NGINX_DATA/ssl/server.crt
    Private key: $NGINX_DATA/ssl/server.key
  "

  # Ustaw odpowiednie uprawnienia
  chmod 600 $NGINX_DATA/ssl/server.key
  chmod 644 $NGINX_DATA/ssl/server.crt

  log_info "
  Next steps:
  1. Add '127.0.0.1 home' to your /etc/hosts file
  2. Run: docker-compose up -d
  3. Access services at:
     - https://localhost/artifactory (or https://home/artifactory)
     - https://localhost/postgres (or https://home/postgres)"
}

