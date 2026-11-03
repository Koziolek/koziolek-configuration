#!/usr/bin/env bash

#;
# Przygotowuje self-signed certyfikat dla domowego serwera. Jest idempotentne: gdy w
# `$NGINX_DATA/ssl` leży para `nginx.crt`/`nginx.key`, a certyfikat jest ważny jeszcze co najmniej
# `PREPARE_CERT_MIN_DAYS` dni (domyślnie 30; `openssl x509 -checkend`), nic nie jest generowane -
# dzięki temu kolejne `start_services` nie podmieniają certyfikatu, któremu klienci już zaufali.
# Brak pary, wygasający lub uszkodzony certyfikat -> generowanie. Uruchamia się jako root (sudo).
# ## Użycie
# ```
# $ prepare_cert [--force|-f]
# ```
# `--force` (albo `PREPARE_CERT_FORCE=1`) zawsze regeneruje parę.
# Alternatywnie można zrobić sourcing do skryptu i tam wywołać jak zwykłą funkcję.
#;
function prepare_cert() {
    local force="${PREPARE_CERT_FORCE:-0}" arg
    for arg in "$@"; do
        case "$arg" in
            --force | -f) force=1 ;;
        esac
    done
    local ssl_dir="$NGINX_DATA/ssl"
    local crt="$ssl_dir/nginx.crt" key="$ssl_dir/nginx.key"
    local min_days="${PREPARE_CERT_MIN_DAYS:-30}"

    make_me_sudo
    if [[ "$force" != 1 ]] && $SUDO test -s "$crt" && $SUDO test -s "$key" &&
        $SUDO openssl x509 -checkend "$((min_days * 86400))" -noout -in "$crt" >/dev/null 2>&1; then
        log_info ssl.cert_up_to_date "$crt" "$min_days"
        unmake_me_sudo
        return 0
    fi

    $SUDO mkdir -p "$ssl_dir"
    # Generuj self-signed certificate
    $SUDO openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$key" \
        -out "$crt" \
        -subj "/C=PL/ST=Lower Silesia/L=Wroclaw/O=Home/OU=IT/CN=koziolek.home" \
        -addext "subjectAltName=DNS:koziolek.home,DNS:home,IP:127.0.0.1" || {
        unmake_me_sudo
        return 1
    }

    log_info ssl.generated "$crt" "$key"

    # Ustaw odpowiednie uprawnienia
    $SUDO chmod 600 "$key"
    $SUDO chmod 644 "$crt"

    unmake_me_sudo
    log_info ssl.next_steps
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f prepare_cert
else
    prepare_cert "$@"
fi
