#!/usr/bin/env bash

#;
# Przygotowuje klucz szyfrowania sekretów Nexusa (`$NEXUS_DATA/etc/keystore/nexus.secrets.json`).
# Jest idempotentne: gdy plik już istnieje i zawiera klucz, nic nie jest generowane - Nexus szyfruje
# tym kluczem sekrety w bazie (hasła proxy/SMTP/LDAP, tokeny), więc jego podmiana (stałe id `home`,
# nowa wartość) unieważnia zapisane sekrety, a skutek wychodzi dopiero po restarcie kontenera.
# Klucz powstaje tylko przy braku pliku (albo pliku bez klucza). Uruchamia się jako root (sudo).
# ## Użycie
# ```
# $ prepare_key [--force|-f]
# ```
# `--force` (albo `PREPARE_KEY_FORCE=1`) wymusza rotację: nowy klucz nadpisuje stary, a sekrety
# zapisane w Nexusie starym kluczem przestają działać (trzeba je wpisać od nowa).
# Alternatywnie można zrobić sourcing do skryptu i tam wywołać jak zwykłą funkcję.
#;
function prepare_key() {
    local force="${PREPARE_KEY_FORCE:-0}" arg
    for arg in "$@"; do
        case "$arg" in
            --force | -f) force=1 ;;
        esac
    done
    local secret_file_template="$SERVICES_CONFIGURATION_DIR/nexus/etc/keystore/nexus.secrets.json.template"
    local secret_file="$NEXUS_DATA/etc/keystore/nexus.secrets.json"
    if [ ! -f "$secret_file_template" ]; then
        log_warn nexus.secret_template_missing "$secret_file_template"
        return 1
    fi

    make_me_sudo
    # Plik ma 600 i właściciela 200:200 - czytamy go przez $SUDO. Istniejący klucz = niepusta
    # wartość "key" i brak niepodstawionego znacznika szablonu.
    local existing=""
    if $SUDO test -s "$secret_file"; then
        existing="$($SUDO cat "$secret_file" 2>/dev/null)"
    fi
    if [[ -n "$existing" && "$existing" == *'"key"'* && "$existing" != *'%%BASED_KEY%%'* &&
        "$existing" =~ \"key\"[[:space:]]*:[[:space:]]*\"[^\"]+\" ]]; then
        if [[ "$force" != 1 ]]; then
            log_info nexus.secret_up_to_date "$secret_file"
            unmake_me_sudo
            return 0
        fi
        log_warn nexus.secret_rotated "$secret_file"
    fi

    local generated_key
    generated_key=$(openssl rand -base64 32) && [[ -n "$generated_key" ]] || {
        log_error nexus.secret_generate_failed
        unmake_me_sudo
        return 1
    }

    # Podstawienie robione czysto w bashu (parameter expansion), nie przez
    # `sed -i "s|X|$generated_key|g"` — tam sekret trafia jako literalny argument
    # do argv procesu sed, widoczny dla innych userów przez ps/`/proc/*/cmdline`
    # przez cały czas trwania tej komendy. Wynik leci do pliku przez stdin
    # builtina printf w pipe (nie exec'owany osobny proces), więc nigdzie
    # w argv żadnego procesu sekret się nie pojawia.
    local template_content rendered
    template_content="$(cat "$secret_file_template")"
    rendered="${template_content//%%BASED_KEY%%/$generated_key}"

    if ! printf '%s' "$rendered" | $SUDO tee "$secret_file" >/dev/null; then
        unmake_me_sudo
        return 1
    fi
    $SUDO chmod 600 "$secret_file"
    $SUDO chown 200:200 "$secret_file"
    unmake_me_sudo
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f prepare_key
else
    prepare_key "$@"
fi
