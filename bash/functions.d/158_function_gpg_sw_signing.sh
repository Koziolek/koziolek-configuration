#!/usr/bin/env bash
#
# Softwarowe podpisywanie artefaktów Mavena kluczem PGP (maven-gpg-plugin,
# publikacja na Maven Central przez Sonatype Central) — dla maszyn/kluczy bez
# apletu OpenPGP/PIV na karcie (patrz 155_function_gpg_card.sh /
# 157_function_jar_signing.sh: czysty FIDO2, np. Thetis BioFP+, tego nie
# obsłuży — FIDO2 to challenge-response, nie generyczny RSA/EC/EdDSA sign
# oracle). Klucz prywatny leży w zwykłym keyringu gpg (~/.gnupg), chroniony
# tylko passphrase — jeśli karta z apletem OpenPGP jest dostępna, użyj zamiast
# tego 155_function_gpg_card.sh (klucz nigdy nie opuszcza karty).
#
# Zależy od helperów manipulacji ~/.m2/settings.xml zdefiniowanych w
# 157_function_jar_signing.sh (_jar_ensure_settings_skeleton/_jar_ensure_container/
# _jar_upsert_marked_block/_jar_remove_marked_block/_jar_maven_settings_path) —
# ten sam, oznaczony blok XML co jar-hw-signing, tylko inny profil. Działa
# dzięki kolejności ładowania source_directory() (patrz CLAUDE.md): 157 < 158
# alfabetycznie, więc te funkcje są już zdefiniowane w powłoce.
#
# Jedno polecenie na cały proces: gpg_sw_setup
#   1. generuje klucz (gpg_sw_generate — pyta o imię/nazwisko + email,
#      passphrase przez zwykły pinentry gpg-agent, ten sam hook co w 155)
#   2. klucz ląduje w lokalnym keyringu gpg (~/.gnupg) — jedyne miejsce,
#      w którym GPG w ogóle przechowuje klucze prywatne
#   3. eksport na keyserver (gpg_sw_export — ubuntu/openpgp/both)
#   4. pyta, czy dopiąć klucz do Mavena (gpg_maven_setup)
#
# Zmienne (opcjonalne — pozwalają odpalić gpg_sw_setup nieinteraktywnie,
# np. w testach, analogicznie do GIT_ASSUME_YES w git/git_functions.sh):
#   GPG_SW_NAME, GPG_SW_EMAIL       — pomijają pytania o dane klucza
#   GPG_SW_KEY_ALGO   (default: ed25519)
#   GPG_SW_KEY_USAGE  (default: sign)   — tylko podpis, bez szyfrowania
#   GPG_SW_KEY_EXPIRE (default: 2y)
#   GPG_SW_EXPORT_TARGET (ubuntu|openpgp|both|none) — pomija pytanie o eksport
#   GPG_SW_MAVEN_CONFIRM (T/n)          — pomija pytanie o konfigurację Mavena

_gpg_sw_check_deps() {
    command -v gpg &>/dev/null || { log_error "gpg_sw: brak gpg — apt/yum install gnupg2; brew install gnupg"; return 1; }
    return 0
}

_gpg_sw_config_dir() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/git-configuration-signing"; }
_gpg_sw_cfg_path()   { echo "$(_gpg_sw_config_dir)/gpg-sw.cfg"; }

##
# Listuje klucze prywatne dostępne w lokalnym keyringu (do wyboru $keyid dla
# gpg_sw_export / gpg_maven_setup / maven-gpg-plugin).
##
function gpg_sw_list_keys() {
    _gpg_sw_check_deps || return 1
    gpg --list-secret-keys --keyid-format=long
}

##
# Generuje nowy klucz PGP (tylko do podpisu — bez subklucza szyfrującego) i
# zapisuje jego fingerprint w configu (do domyślnego użycia przez
# gpg_maven_setup). Wypisuje fingerprint na stdout — logi (log_info/log_error)
# przekierowane na stderr, żeby nie mieszały się ze zwracaną wartością.
# Usage: gpg_sw_generate [imię i nazwisko] [email]
##
function gpg_sw_generate() {
    _gpg_sw_check_deps || return 1
    local name="${1:-${GPG_SW_NAME:-}}" email="${2:-${GPG_SW_EMAIL:-}}"
    local algo="${GPG_SW_KEY_ALGO:-ed25519}" usage="${GPG_SW_KEY_USAGE:-sign}" expire="${GPG_SW_KEY_EXPIRE:-2y}"

    if [ -z "$name" ] || [ -z "$email" ]; then
        log_error "Usage: gpg_sw_generate <imię i nazwisko> <email>"
        return 1
    fi

    local uid="$name <$email>"
    log_info "gpg_sw: generuję klucz ($algo/$usage, wygasa $expire) dla \"$uid\" — podaj passphrase gdy poprosi" >&2
    gpg --quick-generate-key "$uid" "$algo" "$usage" "$expire" || {
        log_error "gpg_sw: generowanie klucza nie powiodło się" >&2
        return 1
    }

    local fpr
    fpr=$(gpg --list-secret-keys --with-colons --fingerprint "$uid" 2>/dev/null | awk -F: '/^fpr:/ { print $10; exit }')
    if [ -z "$fpr" ]; then
        log_error "gpg_sw: klucz wygenerowany, ale nie udało się odczytać jego fingerprintu" >&2
        return 1
    fi

    mkdir -p "$(_gpg_sw_config_dir)"
    chmod 700 "$(_gpg_sw_config_dir)"
    printf 'KEYID=%s\n' "$fpr" > "$(_gpg_sw_cfg_path)"
    chmod 600 "$(_gpg_sw_cfg_path)"

    echo "$fpr"
}

##
# Eksportuje klucz publiczny na keyserver.
# Usage: gpg_sw_export <keyid> [ubuntu|openpgp|both]
#   ubuntu  — keyserver.ubuntu.com (SKS-owy, publikuje UID-y od razu)
#   openpgp — keys.openpgp.org (VKS API); UID-y zostają niezweryfikowane
#             (niewidoczne w wyszukiwaniu po adresie e-mail), dopóki nie
#             potwierdzisz linku z maila, który stamtąd przyjdzie
##
function gpg_sw_export() {
    _gpg_sw_check_deps || return 1
    local keyid="${1:-}" target="${2:-both}" rc=0

    if [ -z "$keyid" ]; then
        log_error "Usage: gpg_sw_export <keyid> [ubuntu|openpgp|both]"
        return 1
    fi
    case "$target" in
        ubuntu|openpgp|both) : ;;
        *) log_error "gpg_sw: nieznany cel eksportu '$target' (ubuntu|openpgp|both)"; return 1 ;;
    esac

    if [ "$target" = ubuntu ] || [ "$target" = both ]; then
        log_info "gpg_sw: eksport $keyid → keyserver.ubuntu.com"
        gpg --keyserver hkps://keyserver.ubuntu.com --send-keys "$keyid" || rc=1
    fi

    if [ "$target" = openpgp ] || [ "$target" = both ]; then
        command -v curl &>/dev/null || { log_error "gpg_sw: curl wymagany do eksportu na keys.openpgp.org"; return 1; }
        log_info "gpg_sw: eksport $keyid → keys.openpgp.org (VKS API)"
        local resp
        resp=$(gpg --export "$keyid" | curl -sS -T - https://keys.openpgp.org/vks/v1/upload) || rc=1
        log_info "gpg_sw: odpowiedź keys.openpgp.org: $resp"
        log_info "gpg_sw: UID-y pozostają niezweryfikowane, dopóki nie potwierdzisz linku z maila wysłanego przez keys.openpgp.org"
    fi

    return "$rc"
}

##
# Wystawia gpg.keyname jako domyślnie aktywny profil Mavena "gpg-sw-signing"
# w ~/.m2/settings.xml — maven-gpg-plugin (goal `sign`, patrz devtools-maven-
# extension/pom.xml) podpisze artefakty automatycznie przy `mvn verify`/
# `deploy`, bez zmian per-projekt. Ten sam, oznaczony-blokowy mechanizm co
# jar_maven_setup w 157 (idempotentny insert, reszta pliku nietknięta) —
# inny profil (gpg-sw-signing zamiast jar-hw-signing), więc oba mogą
# współistnieć w jednym settings.xml.
# Usage: gpg_maven_setup [keyid]   (bez argumentu: keyid z gpg_sw_generate)
##
function gpg_maven_setup() {
    local keyid="${1:-}" settings

    if [ -z "$keyid" ] && [ -f "$(_gpg_sw_cfg_path)" ]; then
        keyid=$(awk -F= '/^KEYID=/ { print $2 }' "$(_gpg_sw_cfg_path)")
    fi
    if [ -z "$keyid" ]; then
        log_error "Usage: gpg_maven_setup <keyid> (albo uruchom najpierw gpg_sw_generate)"
        return 1
    fi

    settings=$(_jar_maven_settings_path)
    _jar_ensure_settings_skeleton "$settings"
    _jar_ensure_container "$settings" profiles
    _jar_ensure_container "$settings" activeProfiles

    local profile_block active_block
    profile_block=$(cat <<XML
  <profile>
    <id>gpg-sw-signing</id>
    <properties>
      <gpg.keyname>${keyid}</gpg.keyname>
    </properties>
  </profile>
XML
)
    active_block="  <activeProfile>gpg-sw-signing</activeProfile>"

    _jar_upsert_marked_block "$settings" gpg-sw-signing-profile profiles "$profile_block"
    _jar_upsert_marked_block "$settings" gpg-sw-signing-active activeProfiles "$active_block"

    log_info "gpg_sw: $settings skonfigurowany — profil gpg-sw-signing (klucz $keyid) aktywny domyślnie"
}

##
# Usuwa profil gpg-sw-signing z ~/.m2/settings.xml (kontenery <profiles>/
# <activeProfiles> zostają, nawet puste — reszta pliku nietknięta).
##
function gpg_maven_disable() {
    local settings
    settings=$(_jar_maven_settings_path)
    [ -f "$settings" ] || { log_warn "gpg_sw: $settings nie istnieje — nic do wyłączenia"; return 0; }
    _jar_remove_marked_block "$settings" gpg-sw-signing-profile
    _jar_remove_marked_block "$settings" gpg-sw-signing-active
    log_info "gpg_sw: profil gpg-sw-signing usunięty z $settings"
}

##
# Jedno polecenie na cały proces: generuje klucz, eksportuje na keyserver,
# opcjonalnie dopina do Mavena. Interaktywne pytania pomijalne przez
# GPG_SW_NAME/GPG_SW_EMAIL/GPG_SW_EXPORT_TARGET/GPG_SW_MAVEN_CONFIRM.
##
function gpg_sw_setup() {
    _gpg_sw_check_deps || return 1
    local name email keyid target confirm

    name="${GPG_SW_NAME:-}"
    [ -z "$name" ] && read -r -p "Imię i nazwisko (User ID klucza): " name
    email="${GPG_SW_EMAIL:-}"
    [ -z "$email" ] && read -r -p "Adres email: " email
    if [ -z "$name" ] || [ -z "$email" ]; then
        log_error "gpg_sw: imię i nazwisko oraz email są wymagane"
        return 1
    fi

    keyid=$(GPG_SW_NAME="$name" GPG_SW_EMAIL="$email" gpg_sw_generate) || return 1
    log_info "gpg_sw: wygenerowano klucz $keyid"

    target="${GPG_SW_EXPORT_TARGET:-}"
    if [ -z "$target" ]; then
        read -r -p "Eksport na keyserver [ubuntu/openpgp/both/none] (both): " target
        target="${target:-both}"
    fi
    if [ "$target" != none ]; then
        gpg_sw_export "$keyid" "$target"
    fi

    confirm="${GPG_SW_MAVEN_CONFIRM:-}"
    if [ -z "$confirm" ]; then
        read -r -p "Dodać ten klucz do konfiguracji Mavena (~/.m2/settings.xml)? [T/n] " confirm
        confirm="${confirm:-T}"
    fi
    case "$confirm" in
        [tTyY]*) gpg_maven_setup "$keyid" ;;
        *) log_info "gpg_sw: pominięto konfigurację Mavena — uruchom później: gpg_maven_setup $keyid" ;;
    esac
}

export -f gpg_sw_list_keys
export -f gpg_sw_generate
export -f gpg_sw_export
export -f gpg_maven_setup
export -f gpg_maven_disable
export -f gpg_sw_setup
