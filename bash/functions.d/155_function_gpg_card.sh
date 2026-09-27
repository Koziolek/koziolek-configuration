#!/usr/bin/env bash
#
# Podpisywanie commitów kluczem GPG trzymanym na kluczu sprzętowym (aplet
# OpenPGP card: YubiKey 5, Nitrokey 3/Pro, Token2, Thetis Pro, ...).
#
# Model: klucz PRYWATNY żyje tylko na karcie — nigdy na dysku. Na każdej
# maszynie potrzebny jest wyłącznie klucz PUBLICZNY + "stub" w ~/.gnupg
# wskazujący na kartę. `gpg_git_setup` robi to jedną komendą:
#   1. czyta fingerprint slotu podpisującego z karty (bez twardego kodowania),
#   2. dociąga klucz publiczny (karta URL → $GPG_PUBKEY_URL → keyserver),
#   3. tworzy stuby (`gpg --card-status`) i nadaje kluczowi ultimate trust,
#   4. ustawia w ~/.gitconfig (stub, `git config --global`) signingkey +
#      commit.gpgsign/tag.gpgSign — przeżywa regenerację .gitconfig.generated
#      i nie włącza podpisu na maszynach, na których nikt nie wpiął karty.
#
# Klucze "czysto FIDO2/U2F" (np. Thetis BioFP, Security Key NFC) NIE mają
# apletu OpenPGP — `gpg --card-status` ich nie zobaczy. Sudo/logowanie przez
# FIDO2 to osobny moduł: 150_function_fido2.sh.
#
# Wymaga: gpg (gnupg2) ze scdaemon. Linux: pakiety `scdaemon` (+ `pcscd`),
# macOS: `gnupg` + `pinentry-mac` (patrz packages/*_packages.sh).

# Zmienne (opcjonalne, np. w ~/.senv):
#   GPG_PUBKEY_URL — skąd pobrać klucz publiczny, gdy karta nie ma ustawionego URL
#                    (domyślnie https://github.com/<GITHUB_USER>.gpg)
#   GPG_KEYSERVER  — keyserver na ostatnią próbę (domyślnie hkps://keys.openpgp.org)
GPG_CARD_GITHUB_USER="${GPG_CARD_GITHUB_USER:-Koziolek}"

_gpg_card_check_deps() {
    local missing=()
    command -v gpg     &>/dev/null || missing+=("gnupg")
    command -v gpgconf &>/dev/null || missing+=("gpgconf (gnupg)")
    if [ "${#missing[@]}" -gt 0 ]; then
        log_error "gpg: brakujące zależności: ${missing[*]}"
        log_info "gpg: Linux: apt install gnupg scdaemon pcscd; macOS: brew install gnupg pinentry-mac"
        return 1
    fi
    return 0
}

# Surowy status karty w formacie --with-colons albo kod 1 gdy karty nie ma.
_gpg_card_status_colons() {
    gpg --card-status --with-colons 2>/dev/null
}

# Wartość pola z linii `<rekord>:` statusu karty. gpg ucieka ':' w wartościach
# jako "\x3a" (czasem "%3a") — odwracamy to, żeby URL był używalny.
_gpg_card_field() {
    local record="$1" status="$2"
    awk -F: -v r="$record" '$1 == r { print $2; exit }' <<<"$status" \
        | sed -e 's/\\x3[aA]/:/g' -e 's/%3[aA]/:/g'
}

# Fingerprint podklucza SIGNATURE z karty (pierwsze pole rekordu `fpr:`).
# Pusty wynik = slot podpisu na karcie jest pusty.
_gpg_card_signing_fpr() {
    _gpg_card_field fpr "$1" | tr '[:lower:]' '[:upper:]'
}

# Fingerprint klucza GŁÓWNEGO, do którego należy podany (pod)klucz.
_gpg_primary_fpr() {
    gpg --with-colons --list-keys "$1" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }'
}

# Pobiera status karty na stdout; zwraca 1 gdy karty nie widać. Diagnostyka
# idzie na stderr, bo wołający przechwytuje stdout przez $(...).
_gpg_card_require() {
    local status
    if ! status=$(_gpg_card_status_colons) || [ -z "$status" ]; then
        {
            log_error "gpg: nie widzę karty OpenPGP (gpg --card-status)."
            log_info  "gpg: czy klucz jest wpięty i ma aplet OpenPGP? Klucze czysto FIDO2/U2F go nie mają."
            log_info  "gpg: przy konflikcie z pcscd: gpg_card_use_pcscd, potem gpg_agent_restart"
        } >&2
        return 1
    fi
    printf '%s\n' "$status"
}

# Konfiguracja pinentry — na Linuksie gpg-agent sam wybiera (curses/gnome3)
# przez $GPG_TTY. macOS cieniuje to w bash/contexts/darwin.sh (pinentry-mac).
_gpg_pinentry_setup() { return 0; }

##
# Status karty OpenPGP w czytelnej postaci (gpg --card-status).
##
function gpg_card_status() {
    _gpg_card_check_deps || return 1
    _gpg_card_require >/dev/null || return 1
    gpg --card-status
}

##
# Dociąga klucz publiczny pasujący do klucza na karcie i tworzy stuby w
# ~/.gnupg (klucz prywatny dalej tylko na karcie). Idempotentne.
# Kolejność źródeł: URL zapisany na karcie → $GPG_PUBKEY_URL
# (domyślnie https://github.com/<user>.gpg) → keyserver $GPG_KEYSERVER.
##
function gpg_card_import_pubkey() {
    _gpg_card_check_deps || return 1
    local status fpr
    status=$(_gpg_card_require) || return 1
    fpr=$(_gpg_card_signing_fpr "$status")
    if [ -z "$fpr" ]; then
        log_error "gpg: slot podpisu na karcie jest pusty — najpierw wygeneruj/wgraj klucz (gpg --edit-key … keytocard)"
        return 1
    fi

    if gpg --list-keys "$fpr" &>/dev/null; then
        log_info "gpg: klucz publiczny $fpr już jest w keyringu"
    else
        local card_url src
        card_url=$(_gpg_card_field url "$status")
        for src in "$card_url" "${GPG_PUBKEY_URL:-https://github.com/${GPG_CARD_GITHUB_USER}.gpg}"; do
            [ -n "$src" ] || continue
            log_info "gpg: pobieram klucz publiczny z $src"
            gpg --fetch-keys "$src" &>/dev/null || true
            gpg --list-keys "$fpr" &>/dev/null && break
        done
        if ! gpg --list-keys "$fpr" &>/dev/null; then
            local ks="${GPG_KEYSERVER:-hkps://keys.openpgp.org}"
            log_info "gpg: próbuję keyserver $ks"
            gpg --keyserver "$ks" --recv-keys "$fpr" &>/dev/null || true
        fi
        if ! gpg --list-keys "$fpr" &>/dev/null; then
            log_error "gpg: nie udało się pobrać klucza publicznego $fpr"
            log_info  "gpg: ustaw GPG_PUBKEY_URL w ~/.senv albo zapisz URL na karcie (gpg --card-edit → admin → url)"
            return 1
        fi
    fi

    # Stuby "shadowed private key" → gpg wie, że prywatna część jest na karcie.
    gpg --card-status &>/dev/null

    local primary
    primary=$(_gpg_primary_fpr "$fpr")
    if [ -n "$primary" ]; then
        # Własny klucz — ultimate trust, inaczej `git log --show-signature` marudzi.
        printf '%s:6:\n' "$primary" | gpg --import-ownertrust &>/dev/null || true
    fi
    log_info "gpg: klucz $fpr gotowy (prywatna część na karcie)"
}

##
# Konfiguruje git na TEJ maszynie do podpisywania commitów i tagów kluczem z
# karty. Ustawienia trafiają do ~/.gitconfig (stub) — nie do szablonu repo,
# bo maszyna bez karty i tak nie podpisze. Uruchom raz na nowej maszynie.
##
function gpg_git_setup() {
    _gpg_card_check_deps || return 1
    command -v git &>/dev/null || { log_error "gpg: brak git"; return 1; }

    gpg_card_import_pubkey || return 1

    local status fpr
    status=$(_gpg_card_require) || return 1
    fpr=$(_gpg_card_signing_fpr "$status")

    _gpg_pinentry_setup || log_warn "gpg: konfiguracja pinentry nie powiodła się — PIN może nie mieć gdzie się pokazać"

    # "!" = użyj DOKŁADNIE tego podklucza (podpisującego z karty), nie
    # "najlepszego" podklucza wybranego przez gpg.
    git config --global user.signingkey "${fpr}!"
    git config --global gpg.format openpgp
    git config --global gpg.program "$(command -v gpg)"
    git config --global commit.gpgsign true
    git config --global tag.gpgSign true

    log_info "gpg: git podpisuje commity i tagi kluczem ${fpr} (~/.gitconfig)"
    log_info "gpg: sprawdź podpis: gpg_card_test (poprosi o PIN/dotyk)"
}

##
# Wyłącza podpisywanie na tej maszynie (np. klucz został w domu).
# Commity nie będą podpisane, dopóki nie uruchomisz ponownie gpg_git_setup.
##
function gpg_git_disable() {
    local k
    for k in commit.gpgsign tag.gpgSign user.signingkey gpg.program gpg.format; do
        git config --global --unset "$k" 2>/dev/null || true
    done
    log_info "gpg: podpisywanie commitów wyłączone na tej maszynie"
}

##
# Próbny podpis kluczem z karty — weryfikuje całą ścieżkę: karta, PIN,
# pinentry, dotyk. Nic nie zapisuje.
##
function gpg_card_test() {
    _gpg_card_check_deps || return 1
    local status fpr
    status=$(_gpg_card_require) || return 1
    fpr=$(_gpg_card_signing_fpr "$status")
    [ -n "$fpr" ] || { log_error "gpg: slot podpisu na karcie jest pusty"; return 1; }

    log_info "gpg: próbny podpis kluczem $fpr — podaj PIN/dotknij klucza gdy poprosi"
    if echo "gpg_card_test $(date +%s)" | gpg --local-user "${fpr}!" --clearsign >/dev/null; then
        log_info "gpg: podpis działa"
    else
        log_error "gpg: podpis nie powiódł się"
        return 1
    fi
}

##
# Restart gpg-agent i scdaemon — typowy lek po przepięciu klucza między
# portami/maszynami (scdaemon trzyma uchwyt do starego czytnika).
##
function gpg_agent_restart() {
    _gpg_card_check_deps || return 1
    gpgconf --kill scdaemon
    gpgconf --kill gpg-agent
    gpg-connect-agent /bye &>/dev/null || true
    log_info "gpg: gpg-agent i scdaemon zrestartowane"
}

##
# Przełącza scdaemon na współdzielenie czytnika przez pcscd (disable-ccid +
# pcsc-shared w ~/.gnupg/scdaemon.conf). Potrzebne, gdy pcscd już trzyma kartę
# (np. inne narzędzia PIV/OATH) i gpg zgłasza "Card not present". Idempotentne.
##
function gpg_card_use_pcscd() {
    local gnupg_home="${GNUPGHOME:-$HOME/.gnupg}"
    local conf="$gnupg_home/scdaemon.conf" line
    mkdir -p "$gnupg_home"
    chmod 700 "$gnupg_home"
    touch "$conf"
    for line in disable-ccid pcsc-shared; do
        grep -qxF "$line" "$conf" || echo "$line" >> "$conf"
    done
    log_info "gpg: scdaemon używa pcscd ($conf) — uruchom gpg_agent_restart"
}

export -f gpg_card_status
export -f gpg_card_import_pubkey
export -f gpg_git_setup
export -f gpg_git_disable
export -f gpg_card_test
export -f gpg_agent_restart
export -f gpg_card_use_pcscd
