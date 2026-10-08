#!/usr/bin/env bash
#
# Zarządzanie kluczami sprzętowymi FIDO2/U2F: wyszukiwanie, PIN, enrollment
# biometrii, rejestracja do sudo (pam_u2f). Konfiguracja MASZYNY (pakiety,
# wpis w /etc/pam.d/sudo) to nie tu — to
# $WORKSPACE_TOOLS/fix-comp/scripts/bezpieczenstwo/01-fido2-diagnostic.sh
# (jednorazowe, per maszyna). Funkcje tutaj działają per klucz/per sesja.
#
# Generyczne dla dowolnej marki FIDO2 (Yubico, Google Titan, Nitrokey, SoloKeys,
# Feitian, Thetis, ...) — wykrywanie przez `fido2-token -L` (libfido2), nie po
# twardo zakodowanej liście vendor ID. Przenośne Linux/macOS — bez zależności od
# udev/hidraw, więc działa też pod `contexts/darwin.sh` bez osobnego cienia.
# Wymaga: fido2-tools (fido2-token), pam_u2f/pamu2fcfg — instaluje je skrypt wyżej.

_fido2_check_deps() {
    local missing=()
    command -v fido2-token &>/dev/null || missing+=("fido2-tools")
    command -v pamu2fcfg   &>/dev/null || missing+=("libpam-u2f/pamu2fcfg")
    if [ "${#missing[@]}" -gt 0 ]; then
        log_error fido2.missing_dependencies "${missing[*]}"
        log_info fido2.install_via_scripts_bezpieczenstwo_01
        return 1
    fi
    return 0
}

# Zwraca ścieżki wszystkich wykrytych kluczy FIDO2/U2F (dowolna marka), jedna na
# linię, na stdout. Wykrywanie przez `fido2-token -L` (libfido2) — przenośne
# Linux/macOS, ten sam mechanizm co check_42_fido_u2f w fix-comp/lib/checks-common.sh.
_fido2_all_devices() {
    command -v fido2-token &>/dev/null || return 1
    fido2-token -L 2>/dev/null | sed -E 's/^([^:]+):.*/\1/'
}

# Opis (vendor/product) dla danej ścieżki klucza, prosto z `fido2-token -L`.
_fido2_device_desc() {
    local h="$1"
    fido2-token -L 2>/dev/null | grep -F "$h:" | sed -E 's/^[^:]+: *//'
}

# Rozwiązuje urządzenie do użycia: argument jeśli podany; jeden wykryty klucz —
# użyj go wprost; kilka — interaktywna lista z wyborem po numerze. Wywoływana
# jako `dev=$(_fido2_resolve_device ...)` — WSZYSTKO poza samą wybraną ścieżką
# (menu, prompt, błąd) musi iść na stderr, inaczej ginie w przechwyconym $dev
# i funkcja woląjąca pada po cichu (log_error z log_message pisze na stdout).
# Loguje błąd i zwraca 1 gdy nic nie znaleziono.
_fido2_resolve_device() {
    local dev="${1:-}"
    if [ -n "$dev" ]; then
        echo "$dev"
        return 0
    fi

    local devices=()
    while IFS= read -r dev; do
        devices+=("$dev")
    done < <(_fido2_all_devices)

    if [ "${#devices[@]}" -eq 0 ]; then
        log_error fido2.no_fido2_u2f_key_connected >&2
        return 1
    fi

    if [ "${#devices[@]}" -eq 1 ]; then
        echo "${devices[0]}"
        return 0
    fi

    local i desc choice
    {
        echo "fido2: wykryto kilka kluczy — wybierz numer:"
        for i in "${!devices[@]}"; do
            desc=$(_fido2_device_desc "${devices[$i]}")
            printf '  %d) %s — %s\n' "$((i + 1))" "${devices[$i]}" "$desc"
        done
    } >&2

    while true; do
        read -r -p "Numer urządzenia [1-${#devices[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#devices[@]}" ]; then
            echo "${devices[$((choice - 1))]}"
            return 0
        fi
        echo "fido2: nieprawidłowy wybór" >&2
    done
}

##
# Listuje podłączone klucze FIDO2/U2F (dowolna marka) z nazwą producenta/modelu
# wprost z `fido2-token -L`, nie z twardo zakodowanej listy.
##
function fido2_list_devices() {
    if ! command -v fido2-token &>/dev/null; then
        log_error fido2.fido2_tools_fido2_token_missing
        return 1
    fi
    local found=0 h desc
    while IFS= read -r h; do
        found=$((found + 1))
        desc=$(_fido2_device_desc "$h")
        echo "${C_GREEN}$h${C_NC}: $desc"
    done < <(_fido2_all_devices)
    if [ "$found" -eq 0 ]; then
        log_warn fido2.no_fido2_u2f_keys_connected
        return 1
    fi
    return 0
}

##
# Szczegóły klucza (fido2-token -I): capabilities, PIN protocols, opcje CTAP2.
# Bez argumentu — pierwszy wykryty klucz.
##
function fido2_info() {
    _fido2_check_deps || return 1
    local dev
    dev=$(_fido2_resolve_device "${1:-}") || return 1
    fido2-token -I "$dev"
}

##
# Ustawia PIN klucza (interaktywnie — fido2-token pyta w terminalu, nie przez
# argument, żeby PIN nie trafił do historii powłoki). Wymagany przed enrollmentem
# biometrii na większości kluczy CTAP2.
##
function fido2_set_pin() {
    _fido2_check_deps || return 1
    local dev
    dev=$(_fido2_resolve_device "${1:-}") || return 1
    log_info fido2.setting_pin_on_enter_the "$dev"
    fido2-token -S "$dev"
}

##
# Zmienia istniejący PIN (fido2-token -C) — pyta o stary i nowy.
##
function fido2_change_pin() {
    _fido2_check_deps || return 1
    local dev
    dev=$(_fido2_resolve_device "${1:-}") || return 1
    fido2-token -C "$dev"
}

##
# Nowy enrollment biometryczny (odcisk palca) — klucze typu Thetis BioFP,
# YubiKey Bio itp. Wymaga PIN ustawionego wcześniej (fido2_set_pin). Program
# każe kilkukrotnie dotknąć/zeskanować palec, buduje mapę odcisku.
##
function fido2_enroll() {
    _fido2_check_deps || return 1
    local dev
    dev=$(_fido2_resolve_device "${1:-}") || return 1
    log_info fido2.biometric_enrollment_on_touch_scan "$dev"
    fido2-token -S -e "$dev"
}

##
# Listuje zarejestrowane odciski (template ID + nazwa) na kluczu.
##
function fido2_enroll_list() {
    _fido2_check_deps || return 1
    local dev
    dev=$(_fido2_resolve_device "${1:-}") || return 1
    fido2-token -L -e "$dev"
}

##
# Nadaje/zmienia przyjazną nazwę zarejestrowanemu odciskowi.
# Usage: fido2_enroll_name <template_id> <nazwa> [device]
##
function fido2_enroll_name() {
    local template_id="$1" name="$2"
    if [ -z "$template_id" ] || [ -z "$name" ]; then
        log_error fido2.usage_fido2_enroll_name_template_id
        return 1
    fi
    _fido2_check_deps || return 1
    local dev
    dev=$(_fido2_resolve_device "${3:-}") || return 1
    fido2-token -S -e -i "$template_id" -n "$name" "$dev"
}

##
# Usuwa zarejestrowany odcisk po template ID (patrz fido2_enroll_list).
# Usage: fido2_enroll_delete <template_id> [device]
##
function fido2_enroll_delete() {
    local template_id="$1"
    if [ -z "$template_id" ]; then
        log_error fido2.usage_fido2_enroll_delete_template_id
        return 1
    fi
    _fido2_check_deps || return 1
    local dev
    dev=$(_fido2_resolve_device "${2:-}") || return 1
    fido2-token -D -e -i "$template_id" "$dev"
}

##
# Rejestruje klucz jako metodę logowania sudo — dopisuje do ~/.config/Yubico/u2f_keys
# (ścieżka zaszyta w pam_u2f, nie zależy od marki klucza). PAM musi już mieć linię
# pam_u2f.so — o to dba scripts/bezpieczenstwo/01-fido2-diagnostic.sh w fix-comp.
# Nadpisuje istniejący plik — do dopisania KOLEJNEGO klucza użyj fido2_register_sudo_backup.
##
function fido2_register_sudo() {
    _fido2_check_deps || return 1
    local dev
    dev=$(_fido2_resolve_device "${1:-}") || return 1

    local u2f_dir="$HOME/.config/Yubico"
    local u2f_keys="$u2f_dir/u2f_keys"

    if [ -s "$u2f_keys" ]; then
        log_warn fido2.already_exists_and_has_entries "$u2f_keys"
        log_warn fido2.to_append_another_key_use_fido2
    fi

    log_info fido2.registering_for_sudo_confirm_on "$dev"
    mkdir -p "$u2f_dir"
    chmod 700 "$u2f_dir"

    # Pisz do pliku tymczasowego — błąd pamu2fcfg (timeout, zły PIN, odłączony
    # klucz) nie może skasować już zarejestrowanych kluczy w u2f_keys.
    local tmp_keys
    tmp_keys=$(mktemp "${u2f_keys}.XXXXXX") || {
        log_error fido2.failed_to_create_a_temporary
        return 1
    }
    if pamu2fcfg > "$tmp_keys"; then
        chmod 600 "$tmp_keys"
        mv "$tmp_keys" "$u2f_keys"
        log_info fido2.registered "$u2f_keys"
        return 0
    else
        log_error fido2.registration_failed_left_unchanged "$u2f_keys"
        rm -f "$tmp_keys"
        return 1
    fi
}

##
# Dopisuje KOLEJNY (zapasowy) klucz do istniejącego ~/.config/Yubico/u2f_keys,
# nie kasując poprzednich wpisów. Dowolna marka, niekoniecznie ta sama co
# pierwszy klucz.
##
function fido2_register_sudo_backup() {
    _fido2_check_deps || return 1
    local dev
    dev=$(_fido2_resolve_device "${1:-}") || return 1

    local u2f_dir="$HOME/.config/Yubico"
    local u2f_keys="$u2f_dir/u2f_keys"

    if [ ! -s "$u2f_keys" ]; then
        log_warn fido2.does_not_exist_yet_use "$u2f_keys"
        return 1
    fi

    log_info fido2.appending_backup_key_to_sudo "$dev"
    mkdir -p "$u2f_dir"
    if pamu2fcfg -n >> "$u2f_keys" 2>/dev/null; then
        chmod 600 "$u2f_keys"
        log_info fido2.backup_key_appended "$u2f_keys"
        return 0
    else
        log_error fido2.appending_the_backup_key_failed
        return 1
    fi
}

##
# Pokazuje zarejestrowane wpisy w ~/.config/Yubico/u2f_keys (ile kluczy, dla
# jakiego usera) bez ujawniania samych handle'y/kluczy publicznych w pełni.
##
function fido2_sudo_keys_list() {
    local u2f_keys="$HOME/.config/Yubico/u2f_keys"
    if [ ! -s "$u2f_keys" ]; then
        log_warn fido2.no_registered_keys_does_not "$u2f_keys"
        return 1
    fi
    local line user count
    # "|| [ -n "$line" ]" — u2f_keys od pamu2fcfg nie ma trailing newline, a `read`
    # bez tego zwraca 1 na ostatniej linii (mimo poprawnego wczytania) i pętla
    # pomija jedyny/ostatni wpis.
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        user="${line%%:*}"
        count=$(( $(grep -o ':' <<<"$line" | wc -l) ))
        echo "${C_GREEN}$user${C_NC}: $count zarejestrowanych kluczy"
    done < "$u2f_keys"
}

export -f fido2_list_devices
export -f fido2_info
export -f fido2_set_pin
export -f fido2_change_pin
export -f fido2_enroll
export -f fido2_enroll_list
export -f fido2_enroll_name
export -f fido2_enroll_delete
export -f fido2_register_sudo
export -f fido2_register_sudo_backup
export -f fido2_sudo_keys_list
