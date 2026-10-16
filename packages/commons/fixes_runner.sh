#!/usr/bin/env bash
# Runner napraw systemowych (rejestr packages/commons/fixes.d/). Sourcowane, nie wykonywane.
#
# 1 fix = 1 plik `NNN_nazwa.sh` w katalogu rejestru; plik niczego nie wykonuje przy source'owaniu,
# tylko deklaruje metadane i funkcje (kontrakt: packages/commons/fixes.d/README.md).
# Wołający (update_*, cron) dostaje jedno polecenie:
#
#     run_fixes <faza|all> [--check] [--only id,id] [--format text|tsv|json] [--allow-high] [--strict]
#
# Każda funkcja fixa leci w OSOBNYM procesie `bash` (stdin z /dev/null, `timeout`, bez dziedziczenia
# `set -e`/`-u`/`trap ERR` wołającego), więc jeden fix nie przerywa reszty pod `set -Eeuo pipefail`.
# Stany: ok / na / detected / fixed / failed / skipped / unknown. `detected` i `failed` tylko
# z dodatniego dowodu; brak danych (timeout, nieznany kod, zła metadana) = `unknown`.
# Kody `run_fixes`: 0 / 10 (--check: wykryto) / 11 (apply: nieudane) / 12 (tylko unknown/skipped).
# Bez `--check` i bez `--strict` funkcja ZAWSZE zwraca 0 (nie przerywa skryptu pod `set -e`);
# stan każdego fixa jest wtedy tylko w raporcie.
#
# Zmienne: FIXES_DIRS (katalogi rejestru, rozdzielone `:`; domyślnie fixes.d obok runnera),
# FIXES_CONTEXT (nadpisanie kontekstu; domyślnie $CONFIG_CONTEXT), FIXES_TIMEOUT (s na wywołanie,
# domyślnie 120), FIXES_SUDO (nadpisanie prefiksu roota: '' = już root, `none` = brak roota;
# domyślnie wykrywane: root albo `sudo -n`).

_FIXES_SELF="${BASH_SOURCE[0]}"
_FIXES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Helpery dostępne wewnątrz fixa (child źródłuje ten plik) ───────────────────

# fix_log <format printf> [argumenty…] — komunikat na stderr, z prefiksem fix_id.
fix_log() {
    local fmt="$1"
    shift || true
    # shellcheck disable=SC2059
    printf "[%s] ${fmt}\n" "${FIX_ID:-?}" "$@" >&2
}
# fix_detail <tekst> — jednolinijkowy szczegół do raportu (liczy się ostatnie wywołanie).
fix_detail() { [ -n "${FIX_DETAIL_FILE:-}" ] && printf '%s\n' "$*" > "$FIX_DETAIL_FILE"; return 0; }
# fix_note_dead_repo <repo> — zgłoszenie martwego repo apt do podsumowania runnera.
fix_note_dead_repo() { [ -n "${FIX_DEAD_REPOS_FILE:-}" ] && printf '%s\n' "$1" >> "$FIX_DEAD_REPOS_FILE"; return 0; }
# fix_denied — podstawiane za $SUDO tam, gdzie root jest zabroniony (detect, --check, brak uprawnień).
fix_denied() { echo "fix_denied: root niedozwolony w tym kontekście: $*" >&2; return 126; }

# ── Wnętrze runnera ────────────────────────────────────────────────────────────

# _fixes_child <plik-fixa|-> <komenda…> — uruchom komendę w świeżym bashu po źródłowaniu
# runnera (helpery) i fixa, z timeoutem i bez stdin. Kod: wynik komendy; 124 = timeout.
_fixes_child() {
    local file="$1"
    shift
    local -a pre=()
    command -v timeout >/dev/null 2>&1 && pre=(timeout --kill-after=5 "${FIXES_TIMEOUT:-120}")
    ${pre[@]+"${pre[@]}"} bash -c '. "$1" || exit 90; if [ "$2" != - ]; then . "$2" || exit 91; fi
        shift 2; set +e +u; "$@"' _ "$_FIXES_SELF" "$file" "$@" </dev/null
}

# _fixes_dump_meta — wołane w child po źródłowaniu fixa: metadane jako linie klucz=wartość.
_fixes_dump_meta() {
    printf 'id=%s\ndesc=%s\nphase=%s\ncontexts=%s\nroot=%s\nrisk=%s\n' \
        "${FIX_ID-}" "${FIX_DESC-}" "${FIX_PHASE-}" "${FIX_CONTEXTS-}" "${FIX_NEEDS_ROOT-}" "${FIX_RISK-}"
    local f
    for f in detect apply verify; do
        declare -F "fix_$f" >/dev/null && printf 'has_%s=1\n' "$f"
    done
    return 0
}

# _fixes_call <plik> <funkcja> <sudo> — funkcja fixa w child; kontekst przez zmienne tylko dla child
# (nic nie wycieka do powłoki wołającej, w tym jej własny $SUDO). Wyjście fixa idzie na stderr.
_fixes_call() {
    FIX_ID="$M_ID" FIX_MODE="$_FIXES_MODE" FIX_DETAIL_FILE="$_FIXES_TMP/detail" \
        FIX_DEAD_REPOS_FILE="$_FIXES_TMP/dead" SUDO="$3" _fixes_child "$1" "$2" >&2
}

# _fixes_meta <plik> — wypełnia M_* z metadanych fixa; M_ERR != '' = plik niepoprawny.
_fixes_meta() {
    local file="$1" out line k v
    M_ID='' M_DESC='' M_PHASE='' M_CONTEXTS='' M_ROOT='' M_RISK='' M_ERR=''
    M_DETECT=0 M_APPLY=0 M_VERIFY=0
    out=$(_fixes_child "$file" _fixes_dump_meta 2>/dev/null) \
        || { M_ERR="nie da się załadować pliku"; M_ID="$(basename "$file" .sh)"; return 0; }
    while IFS= read -r line; do
        k="${line%%=*}"; v="${line#*=}"
        case "$k" in
            id) M_ID="$v" ;; desc) M_DESC="$v" ;; phase) M_PHASE="$v" ;; contexts) M_CONTEXTS="$v" ;;
            root) M_ROOT="$v" ;; risk) M_RISK="$v" ;;
            has_detect) M_DETECT=1 ;; has_apply) M_APPLY=1 ;; has_verify) M_VERIFY=1 ;;
        esac
    done <<< "$out"
    local w
    [[ "$M_ID" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { M_ERR="FIX_ID pusty lub z niedozwolonymi znakami"; M_ID="$(basename "$file" .sh)"; return 0; }
    [ -n "$M_DESC" ] || M_ERR="brak FIX_DESC"
    [ -n "$M_PHASE" ] || M_ERR="brak FIX_PHASE"
    for w in $M_PHASE; do
        case "$w" in pre-apt|post-update|post-apt) ;; *) M_ERR="nieznana faza '$w'" ;; esac
    done
    [ -n "$M_CONTEXTS" ] || M_ERR="brak FIX_CONTEXTS"
    case "$M_ROOT" in 0|1) ;; *) M_ERR="FIX_NEEDS_ROOT musi być 0 lub 1" ;; esac
    case "$M_RISK" in low|high) ;; *) M_ERR="FIX_RISK musi być low lub high" ;; esac
    [ "$M_DETECT" = 1 ] || M_ERR="brak funkcji fix_detect"
    [ "$M_APPLY" = 1 ] || M_ERR="brak funkcji fix_apply"
    return 0
}

# _fixes_files — ścieżki plików rejestru, posortowane po nazwie (numer NNN rządzi kolejnością).
_fixes_files() {
    local dirs="${FIXES_DIRS:-$_FIXES_DIR/fixes.d}" d f
    local IFS=:
    for d in $dirs; do
        for f in "$d"/[0-9][0-9][0-9]_*.sh; do
            [ -f "$f" ] && printf '%s\t%s\n' "$(basename "$f")" "$f"
        done
    done | LC_ALL=C sort -t$'\t' -k1,1 | cut -f2
}

# _fixes_ctx_match <FIX_CONTEXTS> — czy fix dotyczy bieżącego kontekstu (liść lub dowolne ogniwo łańcucha).
_fixes_ctx_match() {
    local want="$1" ctx="${FIXES_CONTEXT:-${CONFIG_CONTEXT:-}}" chain w c
    [ -z "$ctx" ] && return 0
    case " $want " in *" all "*) return 0 ;; esac
    if ! declare -F context_chain >/dev/null 2>&1 && [ -r "$_FIXES_DIR/../../bash/contexts/detect.sh" ]; then
        # shellcheck source=bash/contexts/detect.sh
        . "$_FIXES_DIR/../../bash/contexts/detect.sh"
    fi
    chain="$ctx"
    declare -F context_chain >/dev/null 2>&1 && chain="$(context_chain "$ctx" 2>/dev/null)"
    for w in $want; do
        for c in $chain; do [ "$w" = "$c" ] && return 0; done
    done
    return 1
}

_fixes_clean() { local s="$1"; s="${s//$'\t'/ }"; s="${s//$'\n'/ }"; s="${s//$'\r'/ }"; printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037'; }
_fixes_json() { local s; s="$(_fixes_clean "$1")"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf '"%s"' "$s"; }

# _fixes_emit <format> <id> <state> <phase> <risk> <desc> <detail>
_fixes_emit() {
    local fmt="$1" id="$2" state="$3" phase="$4" risk="$5" desc="$6" detail="$7"
    case "$fmt" in
        tsv) printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$state" "$phase" "$risk" "$(_fixes_clean "$detail")" ;;
        json) printf '{"v":1,"fix_id":%s,"state":%s,"phase":%s,"risk":%s,"detail":%s}\n' \
                "$(_fixes_json "$id")" "$(_fixes_json "$state")" "$(_fixes_json "$phase")" \
                "$(_fixes_json "$risk")" "$(_fixes_json "$detail")" ;;
        *) printf '[%s] %s — %s%s\n' "$state" "$id" "$desc" "${detail:+ ($(_fixes_clean "$detail"))}" ;;
    esac
}

# _fixes_root_prefix — prefiks roota dla apply: '' (jesteśmy rootem), 'sudo -n' (działa bez hasła)
# albo kod 1 (brak). FIXES_SUDO nadpisuje (testy).
_fixes_root_prefix() {
    if [ "${FIXES_SUDO+x}" = x ]; then
        [ "$FIXES_SUDO" = none ] && return 1
        printf '%s' "$FIXES_SUDO"; return 0
    fi
    if [ "$(id -u)" = 0 ]; then return 0; fi
    if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then printf 'sudo -n'; return 0; fi
    return 1
}

# fixes_lint [katalog…] — walidacja rejestru: metadane, unikalne FIX_ID, fix_detect tylko czyta.
# Wypisuje problemy, zwraca 1 przy jakimkolwiek.
fixes_lint() {
    local dirs rc=0 f seen=' ' body
    dirs="$(IFS=:; echo "$*")"
    for f in $(FIXES_DIRS="${dirs:-${FIXES_DIRS:-$_FIXES_DIR/fixes.d}}" _fixes_files); do
        _fixes_meta "$f"
        if [ -n "$M_ERR" ]; then echo "$f: $M_ERR"; rc=1; continue; fi
        case "$seen" in *" $M_ID "*) echo "$f: zduplikowane FIX_ID '$M_ID'"; rc=1 ;; esac
        seen="$seen$M_ID "
        # heurystyka: fix_detect nie woła roota, sieci ani nie modyfikuje stanu
        body="$(awk '/^fix_detect\(\)/{p=1} p{print} p&&/^}/{exit}' "$f" | grep -v '^[[:space:]]*#')"
        if grep -Eq '\$SUDO|\bsudo\b|\bcurl\b|\bwget\b|apt-get|\bapt\b|dpkg -i|dpkg --configure|git clone|systemctl (start|stop|restart|enable)|\brm -|\bmv |\btee\b' <<< "$body"; then
            echo "$f: fix_detect wygląda na modyfikujący/sieciowy/rootowy (wolno tylko czytać)"
            rc=1
        fi
    done
    return $rc
}

# run_fixes <faza|all> [opcje] — patrz nagłówek pliku. Implementacja woła się w kontekście `||`,
# więc `set -e`/`trap ERR` wołającego nie przerwie jej na pierwszym niezerowym kodzie fixa.
run_fixes() {
    local rc=0
    _fixes_run_impl "$@" || rc=$?
    return $rc
}

_fixes_run_impl() {
    local phase="${1:-}" mode=apply format=text only='' allow_high=0 strict=0
    shift || true
    case "$phase" in pre-apt|post-update|post-apt|all) ;; *) echo "run_fixes: nieznana faza '$phase'" >&2; return 2 ;; esac
    while [ $# -gt 0 ]; do
        case "$1" in
            --check) mode=check ;;
            --only) only="$2"; shift ;;
            --only=*) only="${1#*=}" ;;
            --format) format="$2"; shift ;;
            --format=*) format="${1#*=}" ;;
            --allow-high) allow_high=1 ;;
            --strict) strict=1 ;;
            *) echo "run_fixes: nieznana opcja '$1'" >&2; return 2 ;;
        esac
        shift
    done
    case "$format" in text|tsv|json) ;; *) echo "run_fixes: nieznany format '$format'" >&2; return 2 ;; esac

    local tmp states=' ' f rc state detail root_prefix sudo_apply can_root dead
    tmp="$(mktemp -d)" || return 2
    local _FIXES_TMP="$tmp" _FIXES_MODE="$mode"
    : > "$tmp/dead"
    [ "$format" = tsv ] && printf '#fixes-report v1\tmode=%s\tphase=%s\n' "$mode" "$phase"
    [ "$format" = json ] && printf '{"v":1,"report":"fixes-report","mode":"%s","phase":"%s"}\n' "$mode" "$phase"

    if [ "$mode" = apply ] && root_prefix="$(_fixes_root_prefix)"; then can_root=1; else can_root=0; root_prefix=''; fi

    for f in $(_fixes_files); do
        _fixes_meta "$f"
        if [ -n "$M_ERR" ]; then
            _fixes_emit "$format" "$M_ID" unknown "$phase" low "$M_ID" "niepoprawny plik fixa: $M_ERR"
            states="${states}unknown "; continue
        fi
        [ "$phase" = all ] || case " $M_PHASE " in *" $phase "*) ;; *) continue ;; esac
        _fixes_ctx_match "$M_CONTEXTS" || continue
        if [ -n "$only" ]; then case ",$only," in *",$M_ID,"*) ;; *) continue ;; esac; fi

        : > "$tmp/detail"
        _fixes_call "$f" fix_detect fix_denied; rc=$?
        detail="$(head -n1 "$tmp/detail" 2>/dev/null)"
        case "$rc" in
            0) state=detected ;;
            1) state=ok ;;
            2) state=na ;;
            124|137) state=unknown; detail="${detail:-timeout fix_detect}" ;;
            *) state=unknown; detail="${detail:-fix_detect zwrócił kod $rc}" ;;
        esac

        if [ "$state" = detected ] && [ "$mode" = apply ]; then
            if [ "$M_RISK" = high ] && [ "$allow_high" = 0 ]; then
                state=skipped; detail="ryzyko high wymaga --allow-high"
            elif [ "$M_ROOT" = 1 ] && [ "$can_root" = 0 ]; then
                state=skipped; detail="wymaga roota (brak uprawnień lub sudo -n)"
            else
                if [ "$M_ROOT" = 1 ]; then sudo_apply="$root_prefix"; else sudo_apply=fix_denied; fi
                : > "$tmp/detail"
                local fail_msg=''
                if _fixes_call "$f" fix_apply "$sudo_apply"; then
                    state=fixed
                    if [ "$M_VERIFY" = 1 ] && ! _fixes_call "$f" fix_verify "$sudo_apply"; then
                        state=failed; fail_msg="fix_verify nie potwierdził naprawy"
                    fi
                else
                    state=failed; fail_msg="fix_apply zakończył się błędem"
                fi
                # Szczegół zgłoszony przez sam fix (fix_detail) ma pierwszeństwo przed ogólnym komunikatem.
                detail="$(head -n1 "$tmp/detail" 2>/dev/null)"
                [ "$state" = failed ] && [ -z "$detail" ] && detail="$fail_msg"
            fi
        fi
        _fixes_emit "$format" "$M_ID" "$state" "$phase" "$M_RISK" "$M_DESC" "$detail"
        states="${states}${state} "
    done

    dead="$(sort -u "$tmp/dead" 2>/dev/null)"
    if [ -n "$dead" ]; then
        while IFS= read -r f; do
            case "$format" in
                tsv) printf '#dead_repo\t%s\n' "$(_fixes_clean "$f")" ;;
                json) printf '{"v":1,"dead_repo":%s}\n' "$(_fixes_json "$f")" ;;
                *) printf '[dead_repo] %s\n' "$(_fixes_clean "$f")" ;;
            esac
        done <<< "$dead"
    fi
    rm -rf "$tmp"

    rc=0
    case "$states" in
        *" failed "*) [ "$mode" = apply ] && rc=11 ;;
    esac
    if [ "$rc" = 0 ]; then case "$states" in
        *" detected "*) [ "$mode" = check ] && rc=10 ;;
        *" unknown "*|*" skipped "*) rc=12 ;;
    esac; fi
    if [ "$mode" = apply ] && [ "$strict" = 0 ]; then return 0; fi
    return $rc
}
