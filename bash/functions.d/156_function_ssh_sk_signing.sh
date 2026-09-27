#!/usr/bin/env bash
#
# Podpisywanie commitów kluczem SSH trzymanym na kluczu FIDO2 (ed25519-sk,
# resident / discoverable credential). Dla kluczy BEZ apletu OpenPGP —
# np. Thetis BioFP / BioFP+, Security Key NFC, Titan — które nie przechowają
# klucza GPG (tamte obsługuje 155_function_gpg_card.sh).
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
