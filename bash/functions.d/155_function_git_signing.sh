#!/usr/bin/env bash
#
# Podpisywanie commitów git — dwa alternatywne backendy w jednym pliku, bo
# to ten sam cel (podpis commitów/tagów), tylko inny sprzęt:
#
#   1. GPG-karta (gpg_card_*/gpg_git_*) — klucz na aplecie OpenPGP karty
#      (YubiKey 5, Nitrokey 3/Pro, Token2, Thetis Pro, ...). Klucz prywatny
#      żyje tylko na karcie.
#   2. SSH-sk (ssh_sk_*) — klucz `ed25519-sk` resident na kluczu FIDO2 BEZ
#      apletu OpenPGP (Thetis BioFP/BioFP+, Titan, Security Key NFC, ...).
#      Klucz prywatny istnieje tylko w urządzeniu.
#
# Wybór backendu zależy wyłącznie od sprzętu: ma aplet OpenPGP → sekcja 1,
# nie ma → sekcja 2. `gpg_git_setup` i `ssh_sk_git_setup` wzajemnie się
# nadpisują (oba ustawiają `gpg.format` w ~/.gitconfig) — aktywna jest jedna
# metoda naraz, ostatnio skonfigurowana.
#
# Podpisywanie ARTEFAKTÓW MAVENA (JAR/PKCS11, GPG software dla Maven Central)
# to inny cel — patrz 157_function_maven_signing.sh. Zarządzanie samym
# kluczem FIDO2 (PIN, enrollment biometrii, sudo) — 150_function_fido2.sh.
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
        log_error "ssh-sk: brakujące zależności: ${missing[*]}"
        log_info  "ssh-sk: Linux: openssh-client + libfido2; macOS: brew install openssh"
        return 1
    fi
    return 0
}

# E-mail do allowed_signers i komentarza klucza: argument → git user.email.
_ssh_sk_email() {
    local email="${1:-}"
    [ -n "$email" ] || email=$(git config --get user.email 2>/dev/null)
    if [ -z "$email" ]; then
        log_error "ssh-sk: brak e-maila (podaj jako argument albo ustaw git user.email)" >&2
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
        log_error "ssh-sk: $key_file już istnieje — klucz jest utworzony (ssh_sk_git_setup go użyje)"
        return 1
    fi

    local opts=(-O resident -O "application=$app")
    [ "${SSH_SK_VERIFY:-1}" = 1 ] && opts+=(-O verify-required)

    mkdir -p "$(dirname "$key_file")"
    chmod 700 "$(dirname "$key_file")"
    log_info "ssh-sk: tworzenie klucza $app — podaj PIN klucza i potwierdź odciskiem/dotykiem"
    # -N '' — stub nie zawiera sekretu (to tylko uchwyt do klucza w urządzeniu)
    if ! "$(_ssh_sk_keygen)" -t ed25519-sk "${opts[@]}" -C "git-signing $email" -N '' -f "$key_file"; then
        log_error "ssh-sk: tworzenie klucza nie powiodło się (PIN ustawiony? fido2_set_pin)"
        return 1
    fi
    log_info "ssh-sk: klucz utworzony → $key_file(.pub)"
    log_info "ssh-sk: dalej: ssh_sk_git_setup, potem jednorazowo ssh_sk_github_upload"
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
        log_info "ssh-sk: stub $key_file już jest"
        return 0
    fi

    local tmp rc=0
    tmp=$(mktemp -d) || return 1
    log_info "ssh-sk: pobieram resident keys z urządzenia — podaj PIN klucza gdy poprosi"
    (cd "$tmp" && "$(_ssh_sk_keygen)" -K -N '') || rc=$?
    if [ "$rc" -ne 0 ]; then
        rm -rf "$tmp"
        log_error "ssh-sk: ssh-keygen -K nie powiodło się (klucz wpięty? PIN poprawny?)"
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
        log_error "ssh-sk: na urządzeniu nie ma klucza z aplikacją $app — utwórz go: ssh_sk_key_create"
        return 1
    fi

    mkdir -p "$(dirname "$key_file")"
    chmod 700 "$(dirname "$key_file")"
    mv "$found" "$key_file"
    mv "$found.pub" "$key_file.pub"
    chmod 600 "$key_file"
    chmod 644 "$key_file.pub"
    rm -rf "$tmp"
    log_info "ssh-sk: stub odtworzony → $key_file"
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

    log_info "ssh-sk: git podpisuje commity i tagi kluczem $key_file (~/.gitconfig)"
    log_info "ssh-sk: sprawdź: ssh_sk_test (poprosi o odcisk/PIN)"
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
        log_error "Usage: ssh_sk_use_existing <plik_klucza> [email]"
        return 1
    fi
    key_file="${key_file%.pub}"
    if [ ! -s "$key_file" ] || [ ! -s "$key_file.pub" ]; then
        log_error "ssh-sk: brak $key_file lub $key_file.pub"
        return 1
    fi
    local type
    type=$(awk '{ print $1; exit }' "$key_file.pub")
    case "$type" in
        sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) ;;
        *)
            log_error "ssh-sk: $key_file to klucz '$type' — klucz prywatny leży na dysku, nie w urządzeniu FIDO2"
            log_info  "ssh-sk: użyj klucza -sk albo utwórz nowy: ssh_sk_key_create"
            return 1
            ;;
    esac

    SSH_SK_KEY_FILE="$key_file" ssh_sk_git_setup "${2:-}" || return 1
    log_warn "ssh-sk: utrwal w ~/.senv, żeby pozostałe funkcje używały tego klucza:"
    log_man  "export SSH_SK_KEY_FILE=$key_file"
    log_info "ssh-sk: na GitHubie dodaj ten sam klucz drugi raz jako signing key: ssh_sk_github_upload"
    log_info "ssh-sk: na nowej maszynie klucz odtworzy się z urządzenia tylko jeśli jest resident"
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
    log_info "ssh-sk: podpisywanie commitów wyłączone na tej maszynie"
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
    [ -s "$key_file" ] || { log_error "ssh-sk: brak stuba $key_file — uruchom ssh_sk_git_setup"; return 1; }

    tmp=$(mktemp -d) || return 1
    echo "ssh_sk_test $(date +%s)" > "$tmp/msg"
    log_info "ssh-sk: próbny podpis — przyłóż palec/podaj PIN gdy poprosi"
    if ! "$keygen" -Y sign -n git -f "$key_file" "$tmp/msg" >/dev/null; then
        log_error "ssh-sk: podpis nie powiódł się"
        rc=1
    elif ! "$keygen" -Y verify -n git -f "$signers" -I "$email" -s "$tmp/msg.sig" < "$tmp/msg" >/dev/null; then
        log_error "ssh-sk: podpis powstał, ale weryfikacja przez $signers nie przeszła"
        rc=1
    else
        log_info "ssh-sk: podpis działa"
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
    command -v gh &>/dev/null || { log_error "ssh-sk: brak gh (GitHub CLI)"; return 1; }
    [ -s "$key_file.pub" ] || { log_error "ssh-sk: brak $key_file.pub — uruchom ssh_sk_git_setup"; return 1; }
    gh ssh-key add "$key_file.pub" --type signing --title "git-signing ($(_ssh_sk_application))"
}

export -f ssh_sk_key_create
export -f ssh_sk_key_load
export -f ssh_sk_git_setup
export -f ssh_sk_git_disable
export -f ssh_sk_use_existing
export -f ssh_sk_test
export -f ssh_sk_github_upload
