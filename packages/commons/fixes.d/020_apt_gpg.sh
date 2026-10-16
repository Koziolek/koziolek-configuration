#!/usr/bin/env bash
# Fix `apt-gpg`: brakujące (NO_PUBKEY) lub wygasłe klucze GPG repozytoriów apt oraz martwe repozytoria.
# Sourcowane przez runner (packages/commons/fixes_runner.sh), niczego nie wykonuje przy source'owaniu.
# Wersja NIEINTERAKTYWNA (loguje i importuje bez pytania) — odpowiednik dla powłoki (z are_you_sure,
# log_*) to bash/functions.d/096_function_apt_trust.sh; patrz „Dwie implementacje” niżej.
#
# Wykrywanie NIE woła `apt-get update` (sieć + root + zapis list). Źródłem dowodu jest log ostatniego
# `apt-get update` (FIX_APT_UPDATE_LOG; zapisuje go wrapper refresh_apt_gpg_keys i sam fix po naprawie)
# oraz stan keyringu na dysku:
#   • wiersze `NO_PUBKEY <id>` w logu            -> brakujące klucze,
#   • pliki imported-*.gpg z `[expired]`         -> wygasłe klucze (offline, bez logu),
#   • wiersze 404 / „Release” w logu             -> martwe repo (tylko informacja: fix_note_dead_repo;
#                                                   wymagają ręcznej interwencji, nie wpływają na stan).
# Bez logu i bez wygasłych kluczy stanu nie da się ustalić => `unknown` (nigdy `ok` ani `detected` z braku
# danych). Log starszy niż 7 dni jest ignorowany tak samo.
#
# Naprawa: pobiera brakujące klucze z keyservera do izolowanego tymczasowego keyringu i przypina każdy do
# konkretnego pliku źródła przez `signed-by=` — NIGDY trusted.gpg.d (to zaufałoby kluczowi dla WSZYSTKICH
# repo na maszynie). Wygasłe imported-*.gpg usuwa, żeby pobrać je od nowa. Na końcu odświeża log.
#
# Dwie implementacje: powłokowa 096 (interaktywna, pyta o zgodę per klucz, log_*/i18n) i ta (bootstrap
# pakietów, bez pytań). Zostają osobno: różnią się UX i zależnościami (096 nie może wołać runnera z
# `set -e` skryptów instalacyjnych, a ten fix nie ma helperów powłoki). Wspólna jest tylko logika opisana
# powyżej; zmiana algorytmu wymaga poprawki w obu miejscach.
#
# Ścieżki przekierowywane w testach: FIX_APT_UPDATE_LOG, FIX_APT_KEYRINGS_DIR, FIX_APT_SOURCES_LIST,
# FIX_APT_SOURCES_DIR, FIX_APT_KEYSERVER.

FIX_ID=apt-gpg
FIX_DESC="brakujące lub wygasłe klucze GPG repozytoriów apt (NO_PUBKEY)"
FIX_PHASE="pre-apt"
FIX_CONTEXTS=debian
FIX_NEEDS_ROOT=1
FIX_RISK=low

_apt_gpg_log() { printf '%s' "${FIX_APT_UPDATE_LOG:-${XDG_CACHE_HOME:-${HOME:-/root}/.cache}/koziolek-configuration/apt-update.log}"; }
_apt_gpg_keyrings() { printf '%s' "${FIX_APT_KEYRINGS_DIR:-/etc/apt/keyrings}"; }
_apt_gpg_keyserver() { printf '%s' "${FIX_APT_KEYSERVER:-hkps://keyserver.ubuntu.com}"; }

# _apt_gpg_log_fresh — 0 gdy log istnieje i ma <= 7 dni.
_apt_gpg_log_fresh() {
    local log
    log=$(_apt_gpg_log)
    [ -f "$log" ] || return 1
    [ -z "$(find "$log" -mtime +7 -print 2>/dev/null)" ]
}

# _apt_gpg_pairs — "<klucz> <url repo>" z logu apt-get update (posortowane, unikalne).
_apt_gpg_pairs() {
    _apt_gpg_log_fresh || return 0
    grep -E 'GPG error' "$(_apt_gpg_log)" 2>/dev/null \
        | grep -oE '[a-zA-Z]+://[^ ]+ .*NO_PUBKEY [0-9A-F]+' \
        | sed -E 's#^([a-zA-Z]+://[^ ]+) .*NO_PUBKEY ([0-9A-F]+).*#\2 \1#' \
        | sort -u
}

# _apt_gpg_dead — URL-e martwych repo (404 / brak pliku Release) z logu.
_apt_gpg_dead() {
    _apt_gpg_log_fresh || return 0
    grep -E '404|nie ma pliku Release|does not have a Release file' "$(_apt_gpg_log)" 2>/dev/null \
        | grep -oE 'https?://[^[:space:]]+' | sort -u
}

# _apt_gpg_key_expired <plik> — czy keyring zawiera wygasły klucz. Własny GNUPGHOME, żeby `gpg` nie
# zakładał ~/.gnupg w trakcie samego wykrywania.
_apt_gpg_key_expired() {
    local home rc=1
    home=$(mktemp -d) || return 1
    # --with-colons: pole 2 rekordu pub to `e` dla wygasłego klucza (czytelne dla maszyny, niezależne od
    # języka; ludzki zapis to `[expired: data]`, nie `[expired]`).
    gpg --homedir "$home" --show-keys --with-colons "$1" 2>/dev/null | awk -F: '$1 == "pub" && $2 == "e" {f=1} END {exit !f}' && rc=0
    rm -rf "$home"
    return $rc
}

# _apt_gpg_expired — nazwy plików imported-*.gpg z wygasłymi kluczami.
_apt_gpg_expired() {
    local keyfile dir
    dir=$(_apt_gpg_keyrings)
    for keyfile in "$dir"/imported-*.gpg; do
        [ -f "$keyfile" ] || continue
        _apt_gpg_key_expired "$keyfile" && basename "$keyfile"
    done
    return 0
}

# _apt_gpg_problems — 0 gdy jest dodatni dowód problemu (szczegół przez fix_detail), 1 gdy zdrowo,
# 3 gdy brak danych (nie ma świeżego logu ani wygasłych kluczy).
_apt_gpg_problems() {
    local pairs expired keys detail='' have_log=0 u
    _apt_gpg_log_fresh && have_log=1
    pairs=$(_apt_gpg_pairs)
    expired=$(_apt_gpg_expired | tr '\n' ' ')
    expired="${expired% }"
    while IFS= read -r u; do
        [ -n "$u" ] && fix_note_dead_repo "$u"
    done < <(_apt_gpg_dead)

    keys=$(printf '%s\n' "$pairs" | awk 'NF {print $1}' | tr '\n' ' ')
    keys="${keys% }"
    [ -n "$keys" ] && detail="NO_PUBKEY: $keys"
    [ -n "$expired" ] && detail="${detail:+$detail; }wygasłe: $expired"
    if [ -n "$detail" ]; then
        fix_detail "$detail"
        return 0
    fi
    [ "$have_log" = 1 ] || return 3
    return 1
}

fix_detect() {
    command -v gpg >/dev/null 2>&1 || return 3
    _apt_gpg_problems
}

fix_apply() {
    local keyring_dir keyserver keyfile removed=0 rc=0 log pairs
    keyring_dir=$(_apt_gpg_keyrings)
    keyserver=$(_apt_gpg_keyserver)
    log=$(_apt_gpg_log)
    mkdir -p "$(dirname "$log")" 2>/dev/null || true
    $SUDO mkdir -p "$keyring_dir" || return 1

    # Wygasłe klucze usuwamy, żeby pobrać je od nowa; wtedy log jest nieaktualny — odśwież go.
    for keyfile in "$keyring_dir"/imported-*.gpg; do
        [ -f "$keyfile" ] || continue
        if _apt_gpg_key_expired "$keyfile"; then
            fix_log "usuwam wygasły klucz %s" "$(basename "$keyfile")"
            $SUDO rm -f "$keyfile"
            removed=$((removed + 1))
        fi
    done
    [ "$removed" -gt 0 ] && { $SUDO apt-get update >"$log" 2>&1 || true; }

    pairs=$(_apt_gpg_pairs)
    local key repo_url fixed=0 unbound=0 tmp_keyring keyring_file host bound src_file
    while read -r key repo_url; do
        [ -n "$key" ] || continue
        fix_log "pobieram klucz %s z %s" "$key" "$keyserver"
        tmp_keyring=$(mktemp) || { rc=1; continue; }
        if ! gpg --no-default-keyring --keyring "$tmp_keyring" --keyserver "$keyserver" --recv-keys "$key" >/dev/null 2>&1; then
            fix_log "klucz %s: nie udało się pobrać z keyservera" "$key"
            rm -f "$tmp_keyring" "${tmp_keyring}~"
            rc=1
            continue
        fi
        fix_log "fingerprint klucza %s (repo: %s):" "$key" "$repo_url"
        gpg --no-default-keyring --keyring "$tmp_keyring" --fingerprint >&2

        keyring_file="$keyring_dir/imported-${key}.gpg"
        gpg --no-default-keyring --keyring "$tmp_keyring" --export "$key" | $SUDO tee "$keyring_file" >/dev/null
        $SUDO chmod 644 "$keyring_file"
        rm -f "$tmp_keyring" "${tmp_keyring}~"

        # Dowiąż klucz do konkretnego pliku źródła przez signed-by= zamiast zaufania globalnego.
        bound=0
        host=$(printf '%s' "$repo_url" | sed -E 's#^[a-zA-Z]+://([^/]+).*#\1#')
        for src_file in "${FIX_APT_SOURCES_LIST:-/etc/apt/sources.list}" "${FIX_APT_SOURCES_DIR:-/etc/apt/sources.list.d}"/*.list; do
            [ -f "$src_file" ] || continue
            grep -q "$host" "$src_file" || continue
            grep -q 'signed-by=' "$src_file" && continue
            $SUDO sed -i -E \
                -e "s#^(deb(-src)?)([[:space:]]+)\[#\1\3[signed-by=${keyring_file} #" \
                -e "t" \
                -e "s#^(deb(-src)?)([[:space:]]+)(https?://)#\1\3[signed-by=${keyring_file}] \4#" \
                "$src_file"
            fix_log "klucz %s przypięty do %s (signed-by=%s)" "$key" "$src_file" "$keyring_file"
            bound=1
            break
        done
        if [ "$bound" -eq 0 ]; then
            fix_log "nie znaleziono pliku źródła dla %s — klucz zapisany w %s, ale NIE dowiązany do repo" "$repo_url" "$keyring_file"
            unbound=$((unbound + 1))
        fi
        fixed=$((fixed + 1))
    done <<<"$pairs"

    if [ "$fixed" -gt 0 ] || [ "$removed" -gt 0 ]; then
        fix_log "apt-get update po naprawie kluczy..."
        $SUDO apt-get update >"$log" 2>&1 || true
    fi

    if [ "$unbound" -gt 0 ]; then
        fix_detail "$unbound klucz(e) nie dowiązano automatycznie — apt nadal będzie zgłaszał NO_PUBKEY"
        rc=1
    fi
    return $rc
}

fix_verify() {
    ! _apt_gpg_problems
}
