#!/usr/bin/env bash

KEYSERVER="hkps://keyserver.ubuntu.com"
KEYRING_DIR="/etc/apt/keyrings"

##
# Detects NO_PUBKEY and dead-repo errors from apt-get update and fixes them.
# Fetches missing keys from keyserver and scopes each to the specific repo that
# needs it via signed-by= (never trusted.gpg.d — that would trust the key for
# ALL repos, not just the one that requested it).
# Prints a list of dead repositories (404) that require manual removal.
# Usage: refresh_apt_gpg_keys
##
function refresh_apt_gpg_keys() {
    local sudo_cmd=''
    (( EUID != 0 )) && sudo_cmd='sudo'

    log_info "Sprawdzanie kluczy GPG repozytoriów apt..."
    $sudo_cmd mkdir -p "$KEYRING_DIR"

    # Remove expired imported keys so they can be re-fetched fresh
    local keyfile removed=0
    for keyfile in "$KEYRING_DIR"/imported-*.gpg; do
        [[ -f "$keyfile" ]] || continue
        if gpg --show-keys "$keyfile" 2>/dev/null | grep -q '\[expired\]'; then
            log_warn "Usuwanie wygasłego klucza: $(basename "$keyfile")"
            $sudo_cmd rm -f "$keyfile"
            (( removed++ )) || true
        fi
    done
    (( removed > 0 )) && log_info "Usunięto $removed wygasłych kluczy"

    local update_output
    update_output=$($sudo_cmd apt-get update 2>&1 || true)

    # Detect dead repositories
    local dead_repos=()
    while IFS= read -r line; do
        local dead_url
        dead_url=$(echo "$line" | grep -oE 'https?://[^[:space:]]+' | head -1 || true)
        [[ -z "$dead_url" ]] && continue
        dead_repos+=("$dead_url")
    done < <(echo "$update_output" | grep -E '404|nie ma pliku Release|does not have a Release file' || true)

    if [ "${#dead_repos[@]}" -gt 0 ]; then
        log_warn "Martwe repozytoria (wymagają ręcznego usunięcia z /etc/apt/sources.list.d/):"
        local r; for r in "${dead_repos[@]}"; do log_warn "  - $r"; done
    fi

    # Parse "GPG error" lines to pair each missing key with the repo URL that
    # reported it — needed to scope signed-by= to that one repo, not all of apt.
    local pairs
    pairs=$(echo "$update_output" \
        | grep -E 'GPG error' \
        | grep -oE '[a-zA-Z]+://[^ ]+ .*NO_PUBKEY [0-9A-F]+' \
        | sed -E 's#^([a-zA-Z]+://[^ ]+) .*NO_PUBKEY ([0-9A-F]+).*#\2 \1#' \
        | sort -u)

    if [[ -z "$pairs" ]]; then
        log_info "Brak problemów z kluczami GPG"
        return 0
    fi

    log_warn "Brakujące klucze GPG:"
    while read -r k u; do log_warn "  - $k ($u)"; done <<<"$pairs"

    local fixed=0 failed=0 unbound=0
    while read -r key repo_url; do
        [[ -z "$key" ]] && continue

        log_info "Pobieranie klucza $key z $KEYSERVER..."
        local tmp_keyring
        tmp_keyring=$(mktemp)
        if ! gpg --no-default-keyring --keyring "$tmp_keyring" --keyserver "$KEYSERVER" --recv-keys "$key" 2>/dev/null; then
            log_error "Klucz $key: nie udało się pobrać z keyserver"
            rm -f "$tmp_keyring" "${tmp_keyring}~"
            (( failed++ )) || true
            continue
        fi

        log_man "Fingerprint klucza $key (repo: $repo_url):"
        gpg --no-default-keyring --keyring "$tmp_keyring" --fingerprint

        local ans
        ans=$(are_you_sure 'n')
        if [[ "${ans,,}" != y* ]]; then
            log_warn "Pominięto import klucza $key (odrzucone przez użytkownika)"
            rm -f "$tmp_keyring" "${tmp_keyring}~"
            continue
        fi

        local keyring_file="$KEYRING_DIR/imported-${key}.gpg"
        gpg --no-default-keyring --keyring "$tmp_keyring" --export "$key" \
            | $sudo_cmd tee "$keyring_file" > /dev/null
        $sudo_cmd chmod 644 "$keyring_file"
        rm -f "$tmp_keyring" "${tmp_keyring}~"

        # Bind the key to the specific source file via signed-by= instead of
        # trusting it globally through trusted.gpg.d.
        local host bound=0 src_file
        host=$(echo "$repo_url" | sed -E 's#^[a-zA-Z]+://([^/]+).*#\1#')
        for src_file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
            [[ -f "$src_file" ]] || continue
            grep -q "$host" "$src_file" || continue
            if grep -q 'signed-by=' "$src_file"; then
                # Already scoped to some other keyring — not ours to touch.
                continue
            fi
            $sudo_cmd sed -i -E \
                -e "s#^(deb(-src)?)([[:space:]]+)\[#\1\3[signed-by=${keyring_file} #" \
                -e "t" \
                -e "s#^(deb(-src)?)([[:space:]]+)(https?://)#\1\3[signed-by=${keyring_file}] \4#" \
                "$src_file"
            log_info "Klucz $key przypięty do $src_file (signed-by=${keyring_file})"
            bound=1
            break
        done

        if [[ $bound -eq 0 ]]; then
            log_warn "Nie znaleziono pliku źródła dla $repo_url — klucz zapisany w $keyring_file,"
            log_warn "ale NIE dowiązany do repo. Dowiąż ręcznie: dodaj [signed-by=${keyring_file}] do wpisu deb."
            (( unbound++ )) || true
        fi

        (( fixed++ )) || true
    done <<<"$pairs"

    if (( fixed > 0 )); then
        log_info "apt-get update po naprawie kluczy..."
        $sudo_cmd apt-get -qq update 2>&1 | grep -v '^Pobieranie\|^Stary\|^Zign\|^Hit' || true
    fi

    (( unbound > 0 )) && log_warn "$unbound klucz(e) nie dowiązano automatycznie do repo — apt nadal będzie zgłaszał NO_PUBKEY."

    (( failed == 0 ))
}

export -f refresh_apt_gpg_keys
