#!/usr/bin/env bash

# Maps repo hostname → "key_url|keyring_path"
# key_url may be armored (.asc) or binary (.gpg) — both handled via gpg --dearmor
declare -A _APT_GPG_KNOWN_REPOS=(
    ["repository.spotify.com"]="https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.gpg|/etc/apt/trusted.gpg.d/spotify.gpg"
    ["cli.github.com"]="https://cli.github.com/packages/githubcli-archive-keyring.gpg|/etc/apt/keyrings/githubcli-archive-keyring.gpg"
    ["download.docker.com"]="https://download.docker.com/linux/ubuntu/gpg|/etc/apt/keyrings/docker.gpg"
)

_gpg_save_key() {
    local src_file="$1" dst_path="$2" sudo_cmd="$3"
    local tmp_out
    tmp_out="$(mktemp)"
    # Dearmor only if ASCII-armored; binary keys pass through as-is
    if grep -qE '^-----BEGIN' "$src_file" 2>/dev/null; then
        gpg --dearmor < "$src_file" > "$tmp_out" 2>/dev/null || { rm -f "$tmp_out"; return 1; }
    else
        cp "$src_file" "$tmp_out"
    fi
    $sudo_cmd mkdir -p "$(dirname "$dst_path")"
    $sudo_cmd install -o root -g root -m 644 "$tmp_out" "$dst_path"
    rm -f "$tmp_out"
}

##
# Detects NO_PUBKEY and dead-repo errors from apt-get update and fixes them.
# For known repositories re-fetches the official key; unknown keys fall back to keyserver.
# Prints a list of dead repositories (404) that require manual removal.
# Usage: refresh_apt_gpg_keys
##
function refresh_apt_gpg_keys() {
    local sudo_cmd=''
    (( EUID != 0 )) && sudo_cmd='sudo'

    log_info "Sprawdzanie kluczy GPG repozytoriów apt..."

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

    local -A keys_to_fix=()
    while IFS= read -r line; do
        local key_id repo_url
        key_id=$(echo "$line" | grep -oE 'NO_PUBKEY [0-9A-F]+' | awk '{print $2}' || true)
        repo_url=$(echo "$line" | grep -oE 'https?://[^[:space:]]+' | head -1 || true)
        [[ -z "$key_id" ]] && continue
        keys_to_fix["$key_id"]="${repo_url:-unknown}"
    done <<< "$update_output"

    if [ "${#keys_to_fix[@]}" -eq 0 ]; then
        log_info "Brak problemów z kluczami GPG"
        return 0
    fi

    log_warn "Brakujące klucze GPG: ${!keys_to_fix[*]}"

    local key_id repo_url hostname fixed=0 failed=0
    for key_id in "${!keys_to_fix[@]}"; do
        repo_url="${keys_to_fix[$key_id]}"
        hostname=$(echo "$repo_url" | sed -E 's|https?://([^/]+).*|\1|' || true)

        log_info "Naprawa klucza $key_id (${hostname:-nieznane repo})..."

        local known_entry="${_APT_GPG_KNOWN_REPOS[$hostname]:-}"
        if [[ -n "$known_entry" ]]; then
            local key_url keyring_path tmpkey
            key_url="${known_entry%%|*}"
            keyring_path="${known_entry##*|}"
            tmpkey="$(mktemp)"
            if wget -qO "$tmpkey" "$key_url" 2>/dev/null; then
                _gpg_save_key "$tmpkey" "$keyring_path" "$sudo_cmd"
                rm -f "$tmpkey"
                log_info "Klucz $key_id: pobrano z $key_url → $keyring_path"
                (( fixed++ )) || true
                continue
            fi
            rm -f "$tmpkey"
            log_warn "Klucz $key_id: oficjalny URL niedostępny, próba keyserver..."
        fi

        local recovered=/etc/apt/trusted.gpg.d/recovered-keys.gpg
        local tmprecovered
        tmprecovered="$(mktemp)"
        if gpg \
                --keyserver keyserver.ubuntu.com \
                --no-default-keyring \
                --keyring "$tmprecovered" \
                --recv-keys "$key_id" 2>/dev/null; then
            _gpg_save_key "$tmprecovered" "$recovered" "$sudo_cmd"
            rm -f "$tmprecovered"
            log_info "Klucz $key_id: pobrano z keyserver.ubuntu.com → $recovered"
            (( fixed++ )) || true
        else
            rm -f "$tmprecovered"
            log_error "Klucz $key_id: nie udało się naprawić"
            (( failed++ )) || true
        fi
    done

    if (( fixed > 0 )); then
        log_info "apt-get update po naprawie kluczy..."
        $sudo_cmd apt-get -qq update 2>&1 | grep -v '^Pobieranie\|^Stary\|^Zign\|^Hit' || true
    fi

    (( failed == 0 ))
}
