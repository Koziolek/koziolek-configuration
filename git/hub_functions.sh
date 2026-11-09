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

    if ! command -v gh >/dev/null 2>&1; then
        log_error hub.gh_missing
        return 1
    fi

    # --json zwraca same numery (bez `#` z wyjścia tabelarycznego), jeden na linię.
    local numbers
    if ! numbers="$(gh pr list --state open --limit "${HUB_MASS_MERGE_LIMIT:-100}" --json number --jq '.[].number')"; then
        log_error hub.mass_merge_list_failed
        return 1
    fi

    local -a prs=()
    local n
    while IFS= read -r n; do
        [[ "$n" =~ ^[0-9]+$ ]] && prs+=("$n")
    done <<<"$numbers"

    if ((${#prs[@]} == 0)); then
        log_info hub.mass_merge_none
        return 0
    fi

    # Kolejność scalania = kolejność tworzenia PR (rosnąco po numerze): wcześniejsze zmiany
    # trafiają do mastera pierwsze, a późniejsze (często oparte na nich) dopiero po nich.
    mapfile -t prs < <(printf '%s\n' "${prs[@]}" | sort -n)

    if ((dry_run)); then
        log_info hub.mass_merge_dry_run "${prs[*]}"
        return 0
    fi

    local -a failed=()
    local merged=0
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
}
