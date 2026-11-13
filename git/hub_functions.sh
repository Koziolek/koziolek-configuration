#!/usr/bin/env bash

function hub_amen() {
    log_info hub.creating_pr
    git_vomit "$*"
    hub pull-request -m "$*"
}

# Merging pull request in github repo
function hub_merge_pr() {
    local pr="$1"

    if [ -z "$pr" ]; then
        log_man hub.merge_pr_usage
        return 1
    fi

    local to_merge=$(hub pr list -f %U%n | grep -E "/${pr}\$")

    if [ -z "$to_merge" ]; then
        log_error hub.pr_not_found "$pr"
        hub pr list -f %U%n
        return 1
    fi

    log_info hub.merging_pr "$to_merge"
    git home
    hub merge $to_merge
    git push
}

# Lista otwartych pull requestów (wspólna dla hub_mass_merge i hub_pr_status): numery bez `#`,
# rosnąco, czyli w kolejności tworzenia PR. Wynik trafia do tablicy o nazwie z $1 (nameref, nie
# stdout - log_* piszą na stdout). Kody: 0 (także gdy PR brak - tablica pusta), 1 = brak gh lub
# błąd `gh pr list` (błąd już zalogowany). Limit: HUB_MASS_MERGE_LIMIT (domyślnie 100; gh zwraca 30).
function _hub_open_prs() {
    local -n _hub_out="$1"
    _hub_out=()

    if ! command -v gh >/dev/null 2>&1; then
        log_error hub.gh_missing
        return 1
    fi

    # --json zwraca same numery (bez `#` z wyjścia tabelarycznego), jeden na linię.
    local _hub_numbers _hub_n
    if ! _hub_numbers="$(gh pr list --state open --limit "${HUB_MASS_MERGE_LIMIT:-100}" --json number --jq '.[].number')"; then
        log_error hub.mass_merge_list_failed
        return 1
    fi

    while IFS= read -r _hub_n; do
        [[ "$_hub_n" =~ ^[0-9]+$ ]] && _hub_out+=("$_hub_n")
    done <<<"$_hub_numbers"

    # Sortowanie po stronie basha (nie zależy od kolejności zwracanej przez gh).
    if ((${#_hub_out[@]} > 0)); then
        mapfile -t _hub_out < <(printf '%s\n' "${_hub_out[@]}" | sort -n)
    fi
}

# Hurtowy squash merge wszystkich otwartych pull requestów (gh pr merge NUMER -s),
# w kolejności tworzenia: od najmniejszego numeru do największego.
# Użycie: hub_mass_merge [-n|--dry-run] [-h|--help]
#   -n, --dry-run  tylko wypisz numery PR, niczego nie scalaj
# Limit listy: HUB_MASS_MERGE_LIMIT (domyślnie 100; gh domyślnie zwraca 30).
# Błąd scalenia jednego PR nie przerywa pozostałych; kod 1, gdy którykolwiek się nie udał.
function hub_mass_merge() {
    local dry_run=0 arg
    for arg in "$@"; do
        case "$arg" in
        -n | --dry-run) dry_run=1 ;;
        -h | --help)
            log_man hub.mass_merge_usage
            return 0
            ;;
        *)
            log_error hub.mass_merge_unknown_option "$arg"
            log_man hub.mass_merge_usage
            return 2
            ;;
        esac
    done

    local -a prs=()
    _hub_open_prs prs || return 1

    if ((${#prs[@]} == 0)); then
        log_info hub.mass_merge_none
        return 0
    fi

    if ((dry_run)); then
        log_info hub.mass_merge_dry_run "${prs[*]}"
        return 0
    fi

    # Kolejność scalania = kolejność tworzenia PR (rosnąco po numerze): wcześniejsze zmiany
    # trafiają do mastera pierwsze, a późniejsze (często oparte na nich) dopiero po nich.
    local -a failed=()
    local merged=0 n
    for n in "${prs[@]}"; do
        log_info hub.merging_pr "$n"
        if gh pr merge "$n" -s; then
            merged=$((merged + 1))
        else
            log_error hub.mass_merge_failed "$n"
            failed+=("$n")
        fi
    done

    log_info hub.mass_merge_summary "$merged" "${#failed[@]}"
    if ((${#failed[@]} > 0)); then
        log_error hub.mass_merge_failed_list "${failed[*]}"
        return 1
    fi

    # na koniec pobieramy aktualny stan
    git pull;
}

# Stan checków (gh pr checks) każdego otwartego pull requesta, rosnąco po numerze.
# Użycie: hub_pr_status [-h|--help]
# Kod wyjścia gh: 0 = wszystkie przeszły, 8 = trwają, inny (1) = błąd checka albo brak checków.
# Kod 1, gdy którykolwiek PR ma kod inny niż 0/8; trwające checki nie są błędem.
function hub_pr_status() {
    local arg
    for arg in "$@"; do
        case "$arg" in
        -h | --help)
            log_man hub.pr_status_usage
            return 0
            ;;
        *)
            log_error hub.pr_status_unknown_option "$arg"
            log_man hub.pr_status_usage
            return 2
            ;;
        esac
    done

    local -a prs=()
    _hub_open_prs prs || return 1

    if ((${#prs[@]} == 0)); then
        log_info hub.pr_status_none
        return 0
    fi

    local n rc passed=0 pending=0 failed_count=0
    local -a failed_prs=()
    for n in "${prs[@]}"; do
        log_info hub.pr_status_header "$n"
        gh pr checks "$n"
        rc=$?
        case "$rc" in
        0) passed=$((passed + 1)) ;;
        8) pending=$((pending + 1)) ;;
        *)
            failed_count=$((failed_count + 1))
            failed_prs+=("$n")
            ;;
        esac
    done

    log_info hub.pr_status_summary "$passed" "$pending" "$failed_count"
    if ((failed_count > 0)); then
        log_error hub.pr_status_failed_list "${failed_prs[*]}"
        return 1
    fi
}
