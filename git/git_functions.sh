#!/usr/bin/env bash

##
# Functions for git alias usage only. Should not be exported or exposed to normal shell.
# This file is sourced via git alias.fun
##

# Function to get the current Git branch name
function git_current_branch() {
  # Check if the current directory is a git repository
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    # Get the branch name using git symbolic-ref
    home_branch_name=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    echo $home_branch_name
  fi
}

# Return project name
function git_project_name() {
  local name=$(git config project.name)
  echo $name
}

# Deletes remote branches already merged into the default branch
function git_delete_merged_remote() {
  local default_branch
  default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
  if [ -z "$default_branch" ]; then
    default_branch="master"
    log_warn git.default_branch_not_detected_using "$default_branch"
  fi
  for branch in $(git branch -r --merged "$default_branch" | grep -v "/$default_branch" | sed 's/origin\///g'); do
    git push -d origin "$branch"
  done
}

# Remove merged branches
function git_exterminatus() {
  local project_name=$(git_project_name)
  log_exterminatus "project of ${project_name}"
  git_delete_merged_remote
  git p
  gone_branches=$(LANG=en_GB git br -vv | grep ': gone]' | awk '{print $1}')
  if [ -n "$gone_branches" ]; then
    echo "$gone_branches" | xargs git br -D
  fi
}

# Git go home.
function git_home() {
  local home_branch_name=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
  log_info git.go_home_at "${home_branch_name}"
  git co "${home_branch_name}" && git pull
}

# Installs multi-hook dispatcher for all standard git hook types in the current repo
function git_init_multi_hooks() {
  find .git/hooks -maxdepth 1 -type f ! -name '*.sample' -delete
  hooks=(
    "applypatch-msg"
    "commit-msg"
    "fsmonitor-watchman"
    "post-checkout"
    "post-commit"
    "post-merge"
    "post-update"
    "pre-applypatch"
    "pre-commit"
    "prepare-commit-msg"
    "pre-push"
    "pre-rebase"
    "pre-receive"
    "update"
  )
  for hook in "${hooks[@]}"; do
    cat "${GIT_CONFIGURATION_DIR}/hook/multihooks-template.sh" >"./.git/hooks/${hook}"
    mkdir -p "./.git/hooks/${hook}.d"
    chmod +x "./.git/hooks/${hook}"
  done
}

# Initialize repository in current dir like git init, and then setup additional stuff
function git_init() {
  log_info git.initialisation_of_repository

  read -p "${C_LBLUE}Enter project name:${C_NC} " project_name
  if [ -z "$project_name" ]; then
    log_warn git.an_empty_project_name_may_cause
    local ars=$(are_you_sure 'n')
    if [ "$ars" == 'n' ]; then
      return 1
    fi
  fi

  log_man git.would_you_like_to_use_multi "${C_LBLUE}" "${C_NC}"
  local use_hooks=$(yes_or_no 'y')
  git init .
  git config project.name "$project_name"

  if [[ "${use_hooks}" =~ ^(y|yes)$ ]]; then
    git_init_multi_hooks
  fi
}

# Creates a typed branch (feature/fix/version/experimental), prepends project key if set, pushes to remote
function git_new_branch() {
  local type="feature"
  case "$1" in
  feature | version | fix | experimental)
    type="$1"
    shift
    ;;
  *)
    type="feature"
    ;;
  esac

  local branch_name=$(to_ascii "$*")
  branch_name=$(remove_special "$branch_name")
  branch_name=$(to_kebab_case "$branch_name")

  if [ -z "$branch_name" ]; then
    log_error git.branch_need_a_name
    return 1
  fi

  local project_name=$(git_project_name)
  if [ -n "$project_name" ]; then
    branch_name="${project_name}-${branch_name}"
  fi
  branch_name="${type}/${branch_name}"

  git pull
  git co -b "${branch_name}"
  git push -u origin "${branch_name}"
}

# Wrapper: git_new_branch with type=feature
function git_new_feature_branch() {
  git_new_branch feature $*
}
# Wrapper: git_new_branch with type=version
function git_new_version_branch() {
  git_new_branch version $*
}
# Wrapper: git_new_branch with type=fix
function git_new_fix_branch() {
  git_new_branch fix $*
}
# Wrapper: git_new_branch with type=experimental
function git_new_experimental_branch() {
  git_new_branch experimental $*
}

# Derives conventional commit prefix (type + ticket ref) from branch name; empty string if branch type unknown
function git_commit_message_prefix() {
  local branch
  branch=$(git_current_branch 2>/dev/null)
  if [ -z "$branch" ]; then
    return 1
  fi

  if [[ "$branch" != */* ]]; then
    echo ""
    return 0
  fi

  local type_raw="${branch%%/*}"
  local rest="${branch#*/}"

  local type_prefix
  case "$type_raw" in
  feature)      type_prefix="feat:" ;;
  fix)          type_prefix="fix:" ;;
  version)      type_prefix="ver:" ;;
  experimental) type_prefix="exp:" ;;
  *)            echo ""; return 0 ;;
  esac

  local ticket=""
  if [[ "$rest" =~ ^([A-Z]+-[0-9]+)(-|$) ]]; then
    ticket="${BASH_REMATCH[1]}"
  fi

  if [ -n "$ticket" ]; then
    echo "${type_prefix} ${ticket}"
  else
    echo "${type_prefix}"
  fi
}

# Build commit message: derived prefix + given text. Not exported (no git_/hub_ name).
function __git_build_commit_msg() {
  local prefix
  prefix=$(git_commit_message_prefix)
  printf '%s' "${prefix:+${prefix} }$*"
}

# Push current branch to origin, tracking. Extra args passed through (e.g. --force-with-lease).
function __git_push_branch() {
  git push -u origin "$(git_current_branch)" "$@"
}

# Przygotowuje commit-message.txt (w CWD) jako źródło wiadomości commita.
# Argumenty: [-y|--yes] [słowa wiadomości...]
# Wynik: ustawia $__GIT_COMMIT_FILE na ścieżkę pliku gotowego dla `git ci -F`.
# Kod wyjścia !=0 → wołający przerywa (bez commita/pusha).
function __git_prepare_commit_file() {
  __GIT_COMMIT_FILE=""
  local file="commit-message.txt"
  local assume_yes=0
  [ "${GIT_ASSUME_YES:-0}" = "1" ] && assume_yes=1
  case "${1:-}" in
  -y | --yes) assume_yes=1; shift ;;
  esac

  local msg_words="$*"
  if [ -n "${msg_words// /}" ]; then
    # --- ścieżka z parametrami: wstaw nową pierwszą linię z prefiksem ---
    local line new
    line=$(__git_build_commit_msg "$msg_words")
    new=$(mktemp)
    printf '%s\n' "$line" > "$new"
    [ -f "$file" ] && cat "$file" >> "$new"
    mv "$new" "$file"
  else
    # --- ścieżka bez parametrów ---
    [ -f "$file" ] || { log_error git.no_and_no_parameters "$file"; return 1; }
    [ -n "$(tr -d '[:space:]' < "$file")" ] || { log_error git.is_empty "$file"; return 1; }

    # założenie 2: prefiks do pierwszej linii, jeśli brak
    local first
    first=$(head -n1 "$file")
    if ! [[ "$first" =~ ^(feat|fix|ver|exp): ]]; then
      local prefix
      prefix=$(git_commit_message_prefix)
      if [ -n "$prefix" ]; then
        local rest tmp
        rest=$(tail -n +2 "$file")
        tmp=$(mktemp)
        printf '%s %s\n' "$prefix" "$first" > "$tmp"
        [ -n "$rest" ] && printf '%s\n' "$rest" >> "$tmp"
        mv "$tmp" "$file"
      fi
    fi

    # założenie 6: podgląd + potwierdzenie
    if [ "$assume_yes" -ne 1 ]; then
      local l
      log_info git.commit_message "$file"
      log_info "----"
      while IFS= read -r l; do log_info "  $l"; done < "$file"
      log_info "----"
      if [ ! -t 0 ]; then
        log_error git.non_interactive_mode_without_y_yes
        return 1
      fi
      local ans
      read -r -p "Kontynuować? [T/n] " ans
      case "$ans" in
      n | N | nie | no) log_warn git.aborted_by_user; return 1 ;;
      esac
    fi
  fi

  __GIT_COMMIT_FILE="$file"
}

# Pre-check dla git_vomit/git_bleeh: czy jest cokolwiek do zacommitowania (staged, unstaged, untracked).
# Zwraca 0 gdy są zmiany. Gdy ich nie ma: loguje "Brak zmian", pushuje tylko jeśli są niewypchnięte
# commity i zwraca 1 — wołający kończy wtedy normalnie (kod wyjścia pusha, 0 gdy nic do pushowania).
function __git_has_changes_or_push() {
  [ -n "$(git status --porcelain)" ] && return 0
  log_info git.no_changes
  __GIT_PRECHECK_RC=0
  if __git_has_unpushed; then
    __git_push_branch
    __GIT_PRECHECK_RC=$?
  fi
  return 1
}

# Czy HEAD ma commity niewypchnięte do upstreamu. Brak upstreamu (gałąź jeszcze niepushowana) = tak.
function __git_has_unpushed() {
  local n
  n=$(git rev-list --count '@{u}..HEAD' 2>/dev/null) || return 0
  [ "${n:-0}" -gt 0 ]
}

# Stage all, commit with message from commit-message.txt, push to remote
function git_vomit() {
  __git_has_changes_or_push || return "$__GIT_PRECHECK_RC"
  __git_prepare_commit_file "$@" || return 1
  git add .
  git ci -a -F "$__GIT_COMMIT_FILE"
  : > "$__GIT_COMMIT_FILE"
  __git_push_branch
}

# Stage all, squash all branch commits into one (message from commit-message.txt), force-push
function git_bleeh() {
  __git_has_changes_or_push || return "$__GIT_PRECHECK_RC"

  local base_branch
  base_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
  base_branch="${base_branch:-master}"

  local commit_count
  commit_count=$(git log "${base_branch}..HEAD" --oneline 2>/dev/null | wc -l)

  __git_prepare_commit_file "$@" || return 1

  git add .

  if [ "$commit_count" -gt 0 ]; then
    git reset --soft "HEAD~${commit_count}"
  fi
  git ci -F "$__GIT_COMMIT_FILE"
  : > "$__GIT_COMMIT_FILE"

  __git_push_branch --force-with-lease
}

# Kasuje CAŁĄ historię gałęzi i zastępuje jednym commitem ze stanu working tree, force-push.
# Odpowiednik cleanup.sh (repo ai/claude), ale z walidacjami i lokalnym backupem.
# Argumenty: [-m "komunikat"] [-t] [-y]
#   -m  komunikat pierwszego commita (domyślnie "Initial commit")
#   -t  force-push także tagów
#   -y  pomiń potwierdzenie (jak GIT_ASSUME_YES=1)
function git_armageddon() {
  local commit_msg="Initial commit"
  local push_tags=0
  local assume_yes=0
  [ "${GIT_ASSUME_YES:-0}" = "1" ] && assume_yes=1
  local backup_branch="backup-old-history"
  local remote="origin"

  local OPTIND opt
  while getopts "m:ty" opt; do
    case "$opt" in
    m) commit_msg="$OPTARG" ;;
    t) push_tags=1 ;;
    y) assume_yes=1 ;;
    *) log_error git.usage_git_armageddon_m_msg_t; return 2 ;;
    esac
  done

  git rev-parse --is-inside-work-tree &>/dev/null || { log_error git.not_a_git_repository; return 1; }

  local toplevel
  toplevel=$(git rev-parse --show-toplevel)
  cd "$toplevel" || return 1

  git remote get-url "$remote" &>/dev/null || { log_error git.no_remote "$remote"; return 1; }

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)
  [ "$branch" != "HEAD" ] || { log_error git.detached_head_switch_to_a_branch; return 1; }

  if ! git diff --quiet || ! git diff --cached --quiet; then
    log_error git.working_tree_is_not_clean_commit
    return 1
  fi

  # git diff powyżej NIE widzi plików untracked — bez tej kontroli `git add -A`
  # zamiótłby je do nowej historii jako "czysty start" (np. przypadkowy sekret
  # leżący obok, nigdy niezacommitowany).
  local untracked
  untracked=$(git status --porcelain --untracked-files=normal | grep -c '^??' || true)
  if [ "${untracked:-0}" -gt 0 ]; then
    log_error git.working_tree_has_untracked_files_git
    git status --porcelain --untracked-files=normal | grep '^??' | sed 's/^/  /' >&2
    log_error git.add_them_deliberately_git_add_clean
    return 1
  fi

  if git show-ref --verify --quiet "refs/heads/$backup_branch"; then
    log_error git.branch_already_exists_delete_it_git "$backup_branch" "$backup_branch"
    return 1
  fi

  local old_commits remote_url
  old_commits=$(git rev-list --count HEAD)
  remote_url=$(git remote get-url "$remote")

  local existing_tags
  existing_tags=$(git tag -l)

  log_warn git.branch "$branch"
  log_warn git.remote "$remote" "$remote_url"
  log_warn git.commits_now_after_1 "$old_commits"
  log_warn git.message "$commit_msg"
  log_warn "Push tagów:       $([ "$push_tags" = 1 ] && echo tak || echo nie)"
  log_warn git.local_backup_not_pushed_to "$backup_branch" "$remote"
  if [ -n "$existing_tags" ]; then
    log_warn git.warning_repo_has_tags_the_commits "$(echo "$existing_tags" | tr '\n' ' ')"
    log_warn git.are_not_erased_and_remain_on "$remote"
    log_warn git.point_to_old_history_containing_secrets "$remote"
    if [ "$push_tags" = 1 ]; then
      log_warn git.with_t_the_force_push_will
      log_warn git.it_will_upload_again_the_history
    fi
  fi
  log_warn git.this_operation_is_irreversible_on_the "$remote"

  if [ "$assume_yes" -ne 1 ]; then
    if [ ! -t 0 ]; then
      log_error git.non_interactive_mode_without_y_or
      return 1
    fi
    local answer
    read -r -p "Wpisz \"tak\" aby kontynuować: " answer
    [ "$answer" = "tak" ] || { log_warn git.aborted; return 1; }
  fi

  log_info git.backup_of_the_old_history_local "$backup_branch"
  git branch "$backup_branch" || return 1

  log_info git.orphan_branch_with_the_current_working
  git checkout --orphan __armageddon__ || return 1
  git add -A || { log_error git.add_a_failed_history_of "$branch"; return 1; }
  git commit -m "$commit_msg" || return 1

  log_info git.replacing_with_the_new_history "$branch"
  if ! git branch -M __armageddon__ "$branch"; then
    log_error git.renaming_armageddon_failed_aborted_before_th "$branch"
    log_error git.history_on_untouched_head_is_now "$remote"
    log_error git.fix_manually_git_branch_m_armageddon "$branch" "$branch"
    return 1
  fi

  log_info git.force_push "$remote" "$branch"
  git push --force "$remote" "$branch" || return 1

  if [ "$push_tags" = 1 ]; then
    log_info git.force_push_of_tags
    git push --force --tags "$remote"
  fi

  log_info git.done_now_has_1_commit "$remote" "$branch"
  log_info git.old_history_local_branch_commits "$backup_branch" "$old_commits"
  log_info git.rollback_as_long_as_the_backup
  log_info "  git branch -M $backup_branch $branch"
  log_info "  git push --force $remote $branch"
  log_info git.once_you_confirm_everything_is_ok "$backup_branch"
}

. ${GIT_CONFIGURATION_DIR}/hub_functions.sh

## Dispatcher — tylko zadeklarowane funkcje z tego pliku (git_*) i hub_functions.sh (hub_*)
## mogą być wywołane przez `git fun <nazwa>`. Bez tego "$@" uruchamiałoby DOWOLNE
## polecenie systemowe podane po `git fun`.
## Uruchamia się tylko, gdy plik jest wykonywany bezpośrednio (jak robi to alias `fun`),
## nie gdy jest sourcowany (np. przez testy jednostkowe, które chcą tylko definicji funkcji).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [ $# -eq 0 ]; then
    log_error git.fun_missing_function_name
    exit 1
  fi

  if declare -f "$1" > /dev/null && [[ "$1" == git_* || "$1" == hub_* ]]; then
    "$@"
  else
    log_error git.unknown_function_n_available_functions "$1" "$(declare -F | awk '{print $3}' | grep -E '^(git|hub)_' | tr '\n' ' ')"
    exit 1
  fi
fi
