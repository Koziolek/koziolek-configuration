#!/usr/bin/env bash
# Wspólna funkcja refresh_apt_gpg_keys dla update_packages_ubuntu.sh i update_packages_vanilla.sh.
# Sourcowane, nie wykonywane. Wersja NIEINTERAKTYWNA (loguje i importuje bez pytania) —
# odpowiednik dla powłoki (z are_you_sure, log_*) mieszka osobno w
# bash/functions.d/096_apt_gpg.sh, bo tamten kontekst ma dostęp do helperów powłoki.
#
# Wymaga od skryptu wołającego zdefiniowanych wcześniej (przed WYWOŁANIEM, nie przed
# source'owaniem tego pliku): $SUDO, funkcji ok()/warn()/info(), tablicy REPOS_DEAD.

KEYSERVER="hkps://keyserver.ubuntu.com"
KEYRING_DIR="/etc/apt/keyrings"

##
# Wykrywa błędy NO_PUBKEY i martwe repozytoria z `apt-get update` i naprawia klucze.
# Pobiera brakujące klucze z keyservera i przypina każdy do konkretnego repo przez
# signed-by= (nigdy trusted.gpg.d — to zaufałoby kluczowi dla WSZYSTKICH repo).
# Dopisuje martwe repozytoria (404) do globalnej tablicy REPOS_DEAD.
# Usage: refresh_apt_gpg_keys
##
refresh_apt_gpg_keys() {
    info "Sprawdzanie kluczy GPG repozytoriów apt..."
    $SUDO mkdir -p "$KEYRING_DIR"

    # Remove expired imported keys so they can be re-fetched fresh
    local keyfile removed=0
    for keyfile in "$KEYRING_DIR"/imported-*.gpg; do
        [[ -f "$keyfile" ]] || continue
        if gpg --show-keys "$keyfile" 2>/dev/null | grep -q '\[expired\]'; then
            warn "Usuwanie wygasłego klucza: $(basename "$keyfile")"
            $SUDO rm -f "$keyfile"
            (( removed++ )) || true
        fi
    done
    (( removed > 0 )) && info "Usunięto $removed wygasłych kluczy"

    local update_output
    update_output=$($SUDO apt-get update 2>&1 || true)

    # Detect dead repositories (404 / no Release file)
    while IFS= read -r line; do
        local dead_url
        dead_url=$(echo "$line" | grep -oE 'https?://[^[:space:]]+' | head -1 || true)
        [[ -z "$dead_url" ]] && continue
        REPOS_DEAD+=("$dead_url")
    done < <(echo "$update_output" | grep -E '404|nie ma pliku Release|does not have a Release file' || true)

    # Pair each missing key with the repo URL that reported it — needed to scope
    # signed-by= to that one repo instead of trusting the key for all of apt.
    local pairs
    pairs=$(echo "$update_output" \
        | grep -E 'GPG error' \
        | grep -oE '[a-zA-Z]+://[^ ]+ .*NO_PUBKEY [0-9A-F]+' \
        | sed -E 's#^([a-zA-Z]+://[^ ]+) .*NO_PUBKEY ([0-9A-F]+).*#\2 \1#' \
        | sort -u || true)

    if [[ -z "$pairs" ]]; then
        ok "Klucze GPG w porządku"
        return 0
    fi

    warn "Brakujące klucze GPG:"
    while read -r k u; do warn "  - $k ($u)"; done <<<"$pairs"

    local fixed=0 unbound=0
    while read -r key repo_url; do
        [[ -z "$key" ]] && continue

        info "Pobieranie klucza $key z $KEYSERVER..."
        local tmp_keyring
        tmp_keyring=$(mktemp)
        if ! gpg --no-default-keyring --keyring "$tmp_keyring" --keyserver "$KEYSERVER" --recv-keys "$key" 2>/dev/null; then
            warn "Klucz $key: nie udało się pobrać z keyserver"
            rm -f "$tmp_keyring" "${tmp_keyring}~"
            continue
        fi
        info "Fingerprint klucza $key (repo: $repo_url):"
        gpg --no-default-keyring --keyring "$tmp_keyring" --fingerprint

        local keyring_file="$KEYRING_DIR/imported-${key}.gpg"
        gpg --no-default-keyring --keyring "$tmp_keyring" --export "$key" \
            | $SUDO tee "$keyring_file" > /dev/null
        $SUDO chmod 644 "$keyring_file"
        rm -f "$tmp_keyring" "${tmp_keyring}~"

        # Bind the key to the specific source file via signed-by= instead of
        # trusting it globally through trusted.gpg.d.
        local host bound=0 src_file
        host=$(echo "$repo_url" | sed -E 's#^[a-zA-Z]+://([^/]+).*#\1#')
        for src_file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
            [[ -f "$src_file" ]] || continue
            grep -q "$host" "$src_file" || continue
            if grep -q 'signed-by=' "$src_file"; then
                continue
            fi
            $SUDO sed -i -E \
                -e "s#^(deb(-src)?)([[:space:]]+)\[#\1\3[signed-by=${keyring_file} #" \
                -e "t" \
                -e "s#^(deb(-src)?)([[:space:]]+)(https?://)#\1\3[signed-by=${keyring_file}] \4#" \
                "$src_file"
            ok "Klucz $key przypięty do $src_file (signed-by=${keyring_file})"
            bound=1
            break
        done

        if [[ $bound -eq 0 ]]; then
            warn "Nie znaleziono pliku źródła dla $repo_url — klucz zapisany w $keyring_file, ale NIE dowiązany do repo."
            (( unbound++ )) || true
        fi

        (( fixed++ )) || true
    done <<<"$pairs"

    if (( fixed > 0 )); then
        info "apt-get update po naprawie kluczy..."
        $SUDO apt-get -qq update 2>&1 | grep -v '^Pobieranie\|^Stary\|^Zign\|^Hit' || true
    fi

    (( unbound > 0 )) && warn "$unbound klucz(e) nie dowiązano automatycznie — apt nadal będzie zgłaszał NO_PUBKEY."
}
