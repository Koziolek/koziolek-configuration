#!/usr/bin/env bash
#
# Zarządzanie kluczami sprzętowymi FIDO2/U2F: wyszukiwanie, PIN, enrollment
# biometrii, rejestracja do sudo (pam_u2f). Konfiguracja MASZYNY (pakiety,
# wpis w /etc/pam.d/sudo) to nie tu — to
# $WORKSPACE_TOOLS/fix-comp/scripts/bezpieczenstwo/01-fido2-sudo.sh
# (jednorazowe, per maszyna). Funkcje tutaj działają per klucz/per sesja.
#
# Generyczne dla dowolnej marki FIDO2 (Yubico, Google Titan, Nitrokey, SoloKeys,
# Feitian, Thetis, ...) — wykrywanie przez udev ID_FIDO_TOKEN, nie vendor ID.
# Wymaga: fido2-tools (fido2-token), pam_u2f/pamu2fcfg — instaluje je skrypt wyżej.

_fido2_check_deps() {
    local missing=()
    command -v fido2-token &>/dev/null || missing+=("fido2-tools")
    command -v pamu2fcfg   &>/dev/null || missing+=("libpam-u2f/pamu2fcfg")
    if [ "${#missing[@]}" -gt 0 ]; then
        log_error "fido2: brakujące zależności: ${missing[*]}"
        log_info "fido2: zainstaluj przez scripts/bezpieczenstwo/01-fido2-sudo.sh w fix-comp"
        return 1
    fi
    return 0
}

# Zwraca ścieżkę pierwszego wykrytego klucza FIDO2/U2F (dowolna marka) na stdout,
# albo nic + kod 1 gdy brak. Wykrywanie po udev ID_FIDO_TOKEN, nie po vendor ID —
# ten sam mechanizm co check_46_fido_u2f w fix-comp/lib/checks-common.sh.
_fido2_default_device() {
    local h
    for h in /dev/hidraw*; do
        [ -e "$h" ] || continue
        if udevadm info --query=property --name="$h" 2>/dev/null | grep -q '^ID_FIDO_TOKEN=1'; then
            echo "$h"
            return 0
        fi
    done
    return 1
}

# Rozwiązuje urządzenie do użycia: argument jeśli podany, inaczej pierwszy wykryty.
# Loguje błąd i zwraca 1 gdy nic nie znaleziono.
_fido2_resolve_device() {
    local dev="${1:-}"
    if [ -n "$dev" ]; then
        echo "$dev"
        return 0
    fi
    if dev=$(_fido2_default_device); then
        echo "$dev"
        return 0
    fi
    log_error "fido2: brak podłączonego klucza FIDO2/U2F (i nie podano urządzenia jawnie)"
    return 1
}

##
# Listuje podłączone klucze FIDO2/U2F (dowolna marka) z nazwą producenta/modelu
# wprost z deskryptora USB (sysfs), nie z twardo zakodowanej listy.
##
function fido2_list_devices() {
    local found=0 h p walk manu prod
    for h in /dev/hidraw*; do
        [ -e "$h" ] || continue
        p=$(udevadm info --query=property --name="$h" 2>/dev/null)
        if grep -q '^ID_FIDO_TOKEN=1' <<<"$p"; then
            found=$((found + 1))
            walk=$(udevadm info -a -n "$h" 2>/dev/null)
            manu=$(grep -m1 'ATTRS{manufacturer}' <<<"$walk" | grep -o '"[^"]*"' | tr -d '"')
            prod=$(grep -m1 'ATTRS{product}' <<<"$walk" | grep -o '"[^"]*"' | tr -d '"')
            echo "${C_GREEN}$h${C_NC}: ${manu:-nieznany producent} ${prod:-}"
        fi
    done
    if [ "$found" -eq 0 ]; then
        log_warn "fido2: brak podłączonych kluczy FIDO2/U2F"
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
    log_info "fido2: ustawianie PIN na $dev — podaj PIN gdy poprosi (min. długość zależy od klucza)"
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
    log_info "fido2: enrollment biometrii na $dev — kilkukrotnie dotknij/zeskanuj palec wg promptów"
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
        log_error "Usage: fido2_enroll_name <template_id> <nazwa> [device]"
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
        log_error "Usage: fido2_enroll_delete <template_id> [device]"
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
# pam_u2f.so — o to dba scripts/bezpieczenstwo/01-fido2-sudo.sh w fix-comp.
# Nadpisuje istniejący plik — do dopisania KOLEJNEGO klucza użyj fido2_register_sudo_backup.
##
function fido2_register_sudo() {
    _fido2_check_deps || return 1
    local dev
    dev=$(_fido2_resolve_device "${1:-}") || return 1

    local u2f_dir="$HOME/.config/Yubico"
    local u2f_keys="$u2f_dir/u2f_keys"

    if [ -s "$u2f_keys" ]; then
        log_warn "fido2: $u2f_keys już istnieje i ma wpisy — to NADPISZE plik."
        log_warn "Do dopisania kolejnego klucza użyj fido2_register_sudo_backup zamiast tej funkcji."
    fi

    log_info "fido2: rejestracja $dev do sudo — potwierdź na kluczu (dotyk/odcisk) gdy poprosi"
    mkdir -p "$u2f_dir"
    chmod 700 "$u2f_dir"
    if pamu2fcfg > "$u2f_keys"; then
        chmod 600 "$u2f_keys"
        log_info "fido2: zarejestrowano → $u2f_keys"
        return 0
    else
        log_error "fido2: rejestracja nie powiodła się"
        rm -f "$u2f_keys"
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
        log_warn "fido2: $u2f_keys nie istnieje jeszcze — użyj fido2_register_sudo dla pierwszego klucza"
        return 1
    fi

    log_info "fido2: dopisywanie zapasowego klucza ($dev) do sudo — potwierdź na kluczu"
    mkdir -p "$u2f_dir"
    if pamu2fcfg -n >> "$u2f_keys" 2>/dev/null; then
        chmod 600 "$u2f_keys"
        log_info "fido2: dopisano zapasowy klucz → $u2f_keys"
        return 0
    else
        log_error "fido2: dopisanie zapasowego klucza nie powiodło się"
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
        log_warn "fido2: brak zarejestrowanych kluczy ($u2f_keys nie istnieje lub jest pusty)"
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
