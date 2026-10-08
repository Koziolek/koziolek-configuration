#!/usr/bin/env bash
#
# Podpisywanie commitów git — trzy alternatywne backendy w jednym pliku, bo
# to ten sam cel (podpis commitów/tagów), tylko inny sprzęt (albo brak
# sprzętu):
#
#   1. GPG-karta (gpg_card_*/gpg_git_*) — klucz na aplecie OpenPGP karty
#      (YubiKey 5, Nitrokey 3/Pro, Token2, Thetis Pro, ...). Klucz prywatny
#      żyje tylko na karcie.
#   2. SSH-sk (ssh_sk_*) — klucz `ed25519-sk` resident na kluczu FIDO2 BEZ
#      apletu OpenPGP (Thetis BioFP/BioFP+, Titan, Security Key NFC, ...).
#      Klucz prywatny istnieje tylko w urządzeniu.
#   3. GPG software (gpg_sw_git_*) — klucz PGP w zwykłym keyringu ~/.gnupg
#      (z gpg_sw_generate, 157_function_maven_signing.sh), gdy sprzęt nie
#      obsługuje żadnej z metod 1/2. Klucz prywatny leży na dysku, chroniony
#      tylko passphrase.
#
# Wybór backendu zależy od sprzętu: ma aplet OpenPGP → sekcja 1, ma FIDO2
# bez OpenPGP → sekcja 2, nie ma nic z tego → sekcja 3. `gpg_git_setup`,
# `ssh_sk_git_setup` i `gpg_sw_git_setup` wzajemnie się nadpisują (wszystkie
# ustawiają `gpg.format`/`user.signingkey` w ~/.gitconfig) — aktywna jest
# jedna metoda naraz, ostatnio skonfigurowana.
#
# Podpisywanie ARTEFAKTÓW MAVENA (JAR/PKCS11, JAR software, GPG software dla
# Maven Central) to inny cel — patrz 157_function_maven_signing.sh (tam też
# żyje cykl życia klucza gpg_sw_generate/gpg_sw_export, bo był pierwotnie
# pomyślany pod Maven Central; tutaj tylko reużywamy gotowy klucz do
# konfiguracji gita). Zarządzanie samym kluczem FIDO2 (PIN, enrollment
# biometrii, sudo) — 150_function_fido2.sh.
#
# --- GPG-karta ---------------------------------------------------------------
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
        log_error git_signing.gpg_missing_dependencies "${missing[*]}"
        log_info git_signing.gpg_linux_apt_install_gnupg_scdaemon
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
            log_error git_signing.gpg_no_openpgp_card_detected_gpg
            log_info git_signing.gpg_is_the_key_plugged_in
            log_info git_signing.gpg_on_a_conflict_with_pcscd
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
        log_error git_signing.gpg_the_signature_slot_on_the
        return 1
    fi

    if gpg --list-keys "$fpr" &>/dev/null; then
        log_info git_signing.gpg_public_key_is_already_in "$fpr"
    else
        local card_url src
        card_url=$(_gpg_card_field url "$status")
        for src in "$card_url" "${GPG_PUBKEY_URL:-https://github.com/${GPG_CARD_GITHUB_USER}.gpg}"; do
            [ -n "$src" ] || continue
            log_info git_signing.gpg_fetching_public_key_from "$src"
            gpg --fetch-keys "$src" &>/dev/null || true
            gpg --list-keys "$fpr" &>/dev/null && break
        done
        if ! gpg --list-keys "$fpr" &>/dev/null; then
            local ks="${GPG_KEYSERVER:-hkps://keys.openpgp.org}"
            log_info git_signing.gpg_trying_keyserver "$ks"
            gpg --keyserver "$ks" --recv-keys "$fpr" &>/dev/null || true
        fi
        if ! gpg --list-keys "$fpr" &>/dev/null; then
            log_error git_signing.gpg_failed_to_fetch_public_key "$fpr"
            log_info git_signing.gpg_set_gpg_pubkey_url_in
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
    log_info git_signing.gpg_key_ready_private_part_on "$fpr"
}

##
# Konfiguruje git na TEJ maszynie do podpisywania commitów i tagów kluczem z
# karty. Ustawienia trafiają do ~/.gitconfig (stub) — nie do szablonu repo,
# bo maszyna bez karty i tak nie podpisze. Uruchom raz na nowej maszynie.
##
function gpg_git_setup() {
    _gpg_card_check_deps || return 1
    command -v git &>/dev/null || { log_error git_signing.gpg_git_missing; return 1; }

    gpg_card_import_pubkey || return 1

    local status fpr
    status=$(_gpg_card_require) || return 1
    fpr=$(_gpg_card_signing_fpr "$status")

    _gpg_pinentry_setup || log_warn git_signing.gpg_pinentry_configuration_failed_the_pin

    # "!" = użyj DOKŁADNIE tego podklucza (podpisującego z karty), nie
    # "najlepszego" podklucza wybranego przez gpg.
    git config --global user.signingkey "${fpr}!"
    git config --global gpg.format openpgp
    git config --global gpg.program "$(command -v gpg)"
    git config --global commit.gpgsign true
    git config --global tag.gpgSign true

    log_info git_signing.gpg_git_signs_commits_and_tags "${fpr}"
    log_info git_signing.gpg_verify_the_signature_gpg_card
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
    log_info git_signing.gpg_commit_signing_disabled_on_this
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
    [ -n "$fpr" ] || { log_error git_signing.gpg_the_signature_slot_on_the_2; return 1; }

    log_info git_signing.gpg_test_signature_with_key_enter "$fpr"
    if echo "gpg_card_test $(date +%s)" | gpg --local-user "${fpr}!" --clearsign >/dev/null; then
        log_info git_signing.gpg_signature_works
    else
        log_error git_signing.gpg_signature_failed
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
    log_info git_signing.gpg_gpg_agent_and_scdaemon_restarted
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
    log_info git_signing.gpg_scdaemon_uses_pcscd_run_gpg "$conf"
}

export -f gpg_card_status
export -f gpg_card_import_pubkey
export -f gpg_git_setup
export -f gpg_git_disable
export -f gpg_card_test
export -f gpg_agent_restart
export -f gpg_card_use_pcscd

# --- SSH-sk --------------------------------------------------------------------
#
# Podpisywanie commitów kluczem SSH trzymanym na kluczu FIDO2 (ed25519-sk,
# resident / discoverable credential). Dla kluczy BEZ apletu OpenPGP —
# np. Thetis BioFP / BioFP+, Security Key NFC, Titan — które nie przechowają
# klucza GPG (sekcja wyżej).
#
# Model: klucz prywatny istnieje tylko w kluczu sprzętowym. Klucz jest
# "resident", więc na KAŻDEJ maszynie można z niego odtworzyć lokalny "stub"
# (`ssh-keygen -K`) — ten sam klucz podpisujący wszędzie, bez kopiowania plików:
#   1. ssh_sk_key_create — RAZ, na dowolnej maszynie: tworzy klucz na urządzeniu,
#   2. ssh_sk_git_setup  — na każdej maszynie: odtwarza stub (jeśli go nie ma),
#      dopisuje allowed_signers i ustawia git (gpg.format=ssh) w stubie
#      ~/.gitconfig (nie w szablonie — maszyna bez klucza nie próbuje podpisywać),
#   3. ssh_sk_github_upload — RAZ: klucz publiczny jako "signing key" na GitHubie
#      (żeby commity miały "Verified").
#
# Klucz jest oznaczony aplikacją $SSH_SK_APPLICATION (domyślnie ssh:git-signing),
# więc nie miesza się z kluczami do logowania SSH na tym samym urządzeniu.
# Domyślnie z `verify-required` — podpis wymaga weryfikacji użytkownika
# (odcisk palca na BioFP; starsze OpenSSH mogą zamiast tego pytać o PIN klucza).
#
# Wymaga: OpenSSH >= 8.9 z obsługą FIDO (libfido2), PIN ustawiony na kluczu
# (fido2_set_pin — wymagany dla resident keys). macOS: systemowe ssh Apple nie
# obsługuje kluczy -sk — potrzebne `openssh` z brew (contexts/darwin.sh ustawia
# SSH_KEYGEN).
#
# Zmienne (opcjonalne, np. w ~/.senv):
#   SSH_KEYGEN          — binarka ssh-keygen (domyślnie z PATH)
#   SSH_SK_KEY_FILE     — lokalny stub (domyślnie ~/.ssh/id_ed25519_sk_git)
#   SSH_SK_APPLICATION  — aplikacja FIDO klucza (domyślnie ssh:git-signing)
#   SSH_SK_VERIFY       — 1 (domyślnie): verify-required; 0: wystarczy dotyk

_ssh_sk_keygen()      { echo "${SSH_KEYGEN:-ssh-keygen}"; }
_ssh_sk_key_file()    { echo "${SSH_SK_KEY_FILE:-$HOME/.ssh/id_ed25519_sk_git}"; }
_ssh_sk_application() { echo "${SSH_SK_APPLICATION:-ssh:git-signing}"; }
_ssh_sk_allowed_signers() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/git/allowed_signers"; }

_ssh_sk_check_deps() {
    local missing=() keygen
    keygen=$(_ssh_sk_keygen)
    command -v "$keygen" &>/dev/null || missing+=("ssh-keygen (openssh)")
    command -v git       &>/dev/null || missing+=("git")
    if [ "${#missing[@]}" -gt 0 ]; then
        log_error git_signing.ssh_sk_missing_dependencies "${missing[*]}"
        log_info git_signing.ssh_sk_linux_openssh_client_libfido2
        return 1
    fi
    return 0
}

# E-mail do allowed_signers i komentarza klucza: argument → git user.email.
_ssh_sk_email() {
    local email="${1:-}"
    [ -n "$email" ] || email=$(git config --get user.email 2>/dev/null)
    if [ -z "$email" ]; then
        log_error git_signing.ssh_sk_no_e_mail_pass >&2
        return 1
    fi
    echo "$email"
}

##
# Tworzy NOWY klucz podpisujący na urządzeniu FIDO2 (resident, aplikacja
# $SSH_SK_APPLICATION) i zapisuje stub w $SSH_SK_KEY_FILE. Uruchom RAZ —
# kolejne maszyny używają ssh_sk_git_setup (odtworzenie z urządzenia).
# Usage: ssh_sk_key_create [email]
##
function ssh_sk_key_create() {
    _ssh_sk_check_deps || return 1
    local email key_file app
    email=$(_ssh_sk_email "${1:-}") || return 1
    key_file=$(_ssh_sk_key_file)
    app=$(_ssh_sk_application)

    if [ -e "$key_file" ]; then
        log_error git_signing.ssh_sk_already_exists_the_key "$key_file"
        return 1
    fi

    local opts=(-O resident -O "application=$app")
    [ "${SSH_SK_VERIFY:-1}" = 1 ] && opts+=(-O verify-required)

    mkdir -p "$(dirname "$key_file")"
    chmod 700 "$(dirname "$key_file")"
    log_info git_signing.ssh_sk_creating_key_enter_the "$app"
    # -N '' — stub nie zawiera sekretu (to tylko uchwyt do klucza w urządzeniu)
    if ! "$(_ssh_sk_keygen)" -t ed25519-sk "${opts[@]}" -C "git-signing $email" -N '' -f "$key_file"; then
        log_error git_signing.ssh_sk_key_creation_failed_pin
        return 1
    fi
    log_info git_signing.ssh_sk_key_created_pub "$key_file"
    log_info git_signing.ssh_sk_next_ssh_sk_git
}

##
# Odtwarza lokalny stub klucza z urządzenia (ssh-keygen -K) — na nowej
# maszynie. Wybiera klucz po aplikacji $SSH_SK_APPLICATION, pomija pozostałe
# resident keys z urządzenia. Idempotentne (istniejący stub zostaje).
##
function ssh_sk_key_load() {
    _ssh_sk_check_deps || return 1
    local key_file app suffix
    key_file=$(_ssh_sk_key_file)
    app=$(_ssh_sk_application)

    if [ -s "$key_file" ] && [ -s "$key_file.pub" ]; then
        log_info git_signing.ssh_sk_stub_already_exists "$key_file"
        return 0
    fi

    local tmp rc=0
    tmp=$(mktemp -d) || return 1
    log_info git_signing.ssh_sk_fetching_resident_keys_from
    (cd "$tmp" && "$(_ssh_sk_keygen)" -K -N '') || rc=$?
    if [ "$rc" -ne 0 ]; then
        rm -rf "$tmp"
        log_error git_signing.ssh_sk_ssh_keygen_k_failed
        return 1
    fi

    # ssh-keygen -K nazywa pliki id_ed25519_sk_rk[_<aplikacja bez "ssh:">][_<user>].
    # Domyślna aplikacja "ssh:" nie dodaje segmentu — wtedy bierzemy tylko
    # dokładne id_ed25519_sk_rk (wariant z _<user> byłby nie do odróżnienia od
    # klucza innej aplikacji).
    suffix="${app#ssh:}"
    local found='' candidates=()
    if [ -n "$suffix" ]; then
        candidates=("$tmp/id_ed25519_sk_rk_${suffix}" "$tmp"/id_ed25519_sk_rk_"${suffix}"_*)
    else
        candidates=("$tmp/id_ed25519_sk_rk")
    fi
    for f in "${candidates[@]}"; do
        [ -f "$f" ] && [ "${f%.pub}" = "$f" ] && { found="$f"; break; }
    done
    if [ -z "$found" ] || [ ! -f "$found.pub" ]; then
        rm -rf "$tmp"
        log_error git_signing.ssh_sk_the_device_has_no "$app"
        return 1
    fi

    mkdir -p "$(dirname "$key_file")"
    chmod 700 "$(dirname "$key_file")"
    mv "$found" "$key_file"
    mv "$found.pub" "$key_file.pub"
    chmod 600 "$key_file"
    chmod 644 "$key_file.pub"
    rm -rf "$tmp"
    log_info git_signing.ssh_sk_stub_restored "$key_file"
}

##
# Konfiguruje git na TEJ maszynie do podpisywania commitów i tagów kluczem
# SSH z urządzenia FIDO2. Odtwarza stub, jeśli go brak. Ustawienia trafiają do
# ~/.gitconfig (stub), allowed_signers do ~/.config/git/allowed_signers.
# Usage: ssh_sk_git_setup [email]
##
function ssh_sk_git_setup() {
    _ssh_sk_check_deps || return 1
    local email key_file signers blob
    email=$(_ssh_sk_email "${1:-}") || return 1
    key_file=$(_ssh_sk_key_file)
    signers=$(_ssh_sk_allowed_signers)

    ssh_sk_key_load || return 1

    # allowed_signers: "<email> namespaces="git" <typ> <klucz>" — potrzebne do
    # lokalnej weryfikacji (git log --show-signature, git verify-commit).
    blob=$(awk '{ print $1, $2 }' "$key_file.pub")
    mkdir -p "$(dirname "$signers")"
    touch "$signers"
    if ! grep -qF "$blob" "$signers"; then
        printf '%s namespaces="git" %s\n' "$email" "$blob" >> "$signers"
    fi

    git config --global gpg.format ssh
    git config --global user.signingkey "$key_file"
    git config --global gpg.ssh.program "$(command -v "$(_ssh_sk_keygen)")"
    git config --global gpg.ssh.allowedSignersFile "$signers"
    git config --global commit.gpgsign true
    git config --global tag.gpgSign true

    log_info git_signing.ssh_sk_git_signs_commits_and "$key_file"
    log_info git_signing.ssh_sk_verify_ssh_sk_test
}

##
# Podpisuje ISTNIEJĄCYM kluczem FIDO2 (np. tym, którym łączysz się z GitHubem)
# zamiast osobnego ssh:git-signing. Przyjmuje tylko klucze sprzętowe (-sk) —
# zwykły klucz z dysku łamałby zasadę "prywatny klucz tylko w urządzeniu".
# Ustawienie trzeba utrwalić w ~/.senv (SSH_SK_KEY_FILE), żeby ssh_sk_test /
# ssh_sk_github_upload wskazywały ten sam plik — funkcja wypisuje gotowe linie.
# Usage: ssh_sk_use_existing <plik_klucza_prywatnego|stub> [email]
##
function ssh_sk_use_existing() {
    local key_file="${1:-}"
    if [ -z "$key_file" ]; then
        log_error git_signing.usage_ssh_sk_use_existing_key
        return 1
    fi
    key_file="${key_file%.pub}"
    if [ ! -s "$key_file" ] || [ ! -s "$key_file.pub" ]; then
        log_error git_signing.ssh_sk_missing_or_pub "$key_file" "$key_file"
        return 1
    fi
    local type
    type=$(awk '{ print $1; exit }' "$key_file.pub")
    case "$type" in
        sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) ;;
        *)
            log_error git_signing.ssh_sk_is_a_key_the "$key_file" "$type"
            log_info git_signing.ssh_sk_use_an_sk_key
            return 1
            ;;
    esac

    SSH_SK_KEY_FILE="$key_file" ssh_sk_git_setup "${2:-}" || return 1
    log_warn git_signing.ssh_sk_persist_in_senv_so
    log_man  "export SSH_SK_KEY_FILE=$key_file"
    log_info git_signing.ssh_sk_on_github_add_the
    log_info git_signing.ssh_sk_on_a_new_machine
}

##
# Wyłącza podpisywanie kluczem SSH na tej maszynie. Stub i allowed_signers
# zostają — ponowne ssh_sk_git_setup włącza podpis bez dotykania urządzenia.
##
function ssh_sk_git_disable() {
    local k
    for k in commit.gpgsign tag.gpgSign user.signingkey gpg.format \
             gpg.ssh.program gpg.ssh.allowedSignersFile; do
        git config --global --unset "$k" 2>/dev/null || true
    done
    log_info git_signing.ssh_sk_commit_signing_disabled_on
}

##
# Próbny podpis i weryfikacja — sprawdza całą ścieżkę: urządzenie, odcisk/PIN,
# stub, allowed_signers. Nic nie zapisuje w repo.
##
function ssh_sk_test() {
    _ssh_sk_check_deps || return 1
    local email key_file signers tmp keygen rc=0
    email=$(_ssh_sk_email "${1:-}") || return 1
    key_file=$(_ssh_sk_key_file)
    signers=$(_ssh_sk_allowed_signers)
    keygen=$(_ssh_sk_keygen)
    [ -s "$key_file" ] || { log_error git_signing.ssh_sk_missing_stub_run_ssh "$key_file"; return 1; }

    tmp=$(mktemp -d) || return 1
    echo "ssh_sk_test $(date +%s)" > "$tmp/msg"
    log_info git_signing.ssh_sk_test_signature_touch_the
    if ! "$keygen" -Y sign -n git -f "$key_file" "$tmp/msg" >/dev/null; then
        log_error git_signing.ssh_sk_signature_failed
        rc=1
    elif ! "$keygen" -Y verify -n git -f "$signers" -I "$email" -s "$tmp/msg.sig" < "$tmp/msg" >/dev/null; then
        log_error git_signing.ssh_sk_signature_created_but_verification "$signers"
        rc=1
    else
        log_info git_signing.ssh_sk_signature_works
    fi
    rm -rf "$tmp"
    return "$rc"
}

##
# Wysyła klucz publiczny na GitHuba jako SIGNING key (gh CLI, zalogowane) —
# commity dostają "Verified". Jednorazowo, z dowolnej maszyny.
##
function ssh_sk_github_upload() {
    local key_file
    key_file=$(_ssh_sk_key_file)
    command -v gh &>/dev/null || { log_error git_signing.ssh_sk_gh_github_cli_missing; return 1; }
    [ -s "$key_file.pub" ] || { log_error git_signing.ssh_sk_missing_pub_run_ssh "$key_file"; return 1; }
    gh ssh-key add "$key_file.pub" --type signing --title "git-signing ($(_ssh_sk_application))"
}

export -f ssh_sk_key_create
export -f ssh_sk_key_load
export -f ssh_sk_git_setup
export -f ssh_sk_git_disable
export -f ssh_sk_use_existing
export -f ssh_sk_test
export -f ssh_sk_github_upload

# --- GPG software (commit signing) ------------------------------------------
#
# Podpisywanie commitów softwarowym kluczem PGP — dla sprzętu bez apletu
# OpenPGP i bez FIDO2 (albo gdy po prostu nie chcesz sprzętowego klucza).
# Klucz sam w sobie generuje gpg_sw_generate (157_function_maven_signing.sh
# — tam żyje cały cykl życia klucza: generowanie, eksport na keyserver, bo
# pierwotnie pomyślany pod podpisywanie artefaktów Maven Central). Tutaj
# tylko konfiguracja gita, bez wymogu karty — klucz leży w zwykłym keyringu
# ~/.gnupg, chroniony tylko passphrase.
#
# Softwarowy klucz (w przeciwieństwie do karty/FIDO2) nie "przenosi się"
# sam między maszynami — na każdej maszynie musi być w lokalnym ~/.gnupg
# (eksport/import ręcznie, albo osobny klucz per maszyna).
#
# Ścieżka configu z gpg_sw_generate ($XDG_CONFIG_HOME/git-configuration-
# signing/gpg-sw.cfg) zaszyta tu jako stała — celowo NIE wołamy prywatnych
# helperów z 157 (157 ładuje się PO 155 alfabetycznie, więc jego funkcje
# nie są jeszcze zdefiniowane, gdy 155 się ładuje; odwrotna kolejność niż
# przy 157/_maven_settings_*, gdzie taka zależność jest bezpieczna).

_gpg_sw_default_keyid() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/git-configuration-signing/gpg-sw.cfg"
    [ -f "$cfg" ] || return 1
    awk -F= '/^KEYID=/ { print $2 }' "$cfg"
}

##
# Konfiguruje git na TEJ maszynie do podpisywania commitów i tagów
# softwarowym kluczem PGP (z gpg_sw_generate). Bez wymogu karty.
# Usage: gpg_sw_git_setup [keyid]   (bez argumentu: keyid z gpg_sw_generate)
##
function gpg_sw_git_setup() {
    command -v gpg &>/dev/null || { log_error git_signing.gpg_sw_gpg_missing; return 1; }
    command -v git &>/dev/null || { log_error git_signing.gpg_sw_git_missing; return 1; }

    local keyid="${1:-}"
    [ -z "$keyid" ] && keyid=$(_gpg_sw_default_keyid)
    if [ -z "$keyid" ]; then
        log_error git_signing.usage_gpg_sw_git_setup_keyid
        return 1
    fi

    git config --global user.signingkey "$keyid"
    git config --global gpg.format openpgp
    git config --global gpg.program "$(command -v gpg)"
    git config --global commit.gpgsign true
    git config --global tag.gpgSign true

    log_info git_signing.gpg_sw_git_signs_commits_and "$keyid"
    log_info git_signing.gpg_sw_verify_the_signature_gpg
}

##
# Wyłącza podpisywanie softwarowym kluczem na tej maszynie.
##
function gpg_sw_git_disable() {
    local k
    for k in commit.gpgsign tag.gpgSign user.signingkey gpg.program gpg.format; do
        git config --global --unset "$k" 2>/dev/null || true
    done
    log_info git_signing.gpg_sw_commit_signing_with_the
}

##
# Próbny podpis softwarowym kluczem — sprawdza że klucz jest w keyringu i
# passphrase działa. Nic nie zapisuje.
# Usage: gpg_sw_test [keyid]
##
function gpg_sw_test() {
    command -v gpg &>/dev/null || { log_error git_signing.gpg_sw_gpg_missing; return 1; }
    local keyid="${1:-}"
    [ -z "$keyid" ] && keyid=$(_gpg_sw_default_keyid)
    [ -n "$keyid" ] || { log_error git_signing.gpg_sw_missing_keyid_pass_it; return 1; }

    log_info git_signing.gpg_sw_test_signature_with_key "$keyid"
    if echo "gpg_sw_test $(date +%s)" | gpg --local-user "$keyid" --clearsign >/dev/null; then
        log_info git_signing.gpg_sw_signature_works
    else
        log_error git_signing.gpg_sw_signature_failed
        return 1
    fi
}

export -f gpg_sw_git_setup
export -f gpg_sw_git_disable
export -f gpg_sw_test
