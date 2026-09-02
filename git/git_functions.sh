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
    log_warn "Nie wykryto gałęzi domyślnej, używam: $default_branch"
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
  log_info "Git go home at ${home_branch_name}"
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
  log_info "Initialisation of repository"

  read -p "${C_LBLUE}Enter project name:${C_NC} " project_name
  if [ -z "$project_name" ]; then
    log_warn "An empty project name may cause heretical behavior."
    local ars=$(are_you_sure 'n')
    if [ "$ars" == 'n' ]; then
      return 1
    fi
  fi

  log_man "${C_LBLUE}Would you like to use multi-hooks?${C_NC} "
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
    log_error "Branch need a name"
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
    [ -f "$file" ] || { log_error "Brak $file i brak parametrów"; return 1; }
    [ -n "$(tr -d '[:space:]' < "$file")" ] || { log_error "$file jest pusty"; return 1; }

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
      log_info "Treść commita ($file):"
      log_info "----"
      while IFS= read -r l; do log_info "  $l"; done < "$file"
      log_info "----"
      if [ ! -t 0 ]; then
        log_error "Tryb nieinteraktywny bez -y/--yes ani GIT_ASSUME_YES=1 — przerwano"
        return 1
      fi
      local ans
      read -r -p "Kontynuować? [T/n] " ans
      case "$ans" in
      n | N | nie | no) log_warn "Przerwano przez użytkownika"; return 1 ;;
      esac
    fi
  fi

  __GIT_COMMIT_FILE="$file"
}

# Stage all, commit with message from commit-message.txt, push to remote
function git_vomit() {
  __git_prepare_commit_file "$@" || return 1
  git add .
  git ci -a -F "$__GIT_COMMIT_FILE"
  : > "$__GIT_COMMIT_FILE"
  __git_push_branch
}

# Stage all, squash all branch commits into one (message from commit-message.txt), force-push
function git_bleeh() {
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

. ${GIT_CONFIGURATION_DIR}/hub_functions.sh

## Dispatcher — tylko zadeklarowane funkcje z tego pliku (git_*) i hub_functions.sh (hub_*)
## mogą być wywołane przez `git fun <nazwa>`. Bez tego "$@" uruchamiałoby DOWOLNE
## polecenie systemowe podane po `git fun`.
## Uruchamia się tylko, gdy plik jest wykonywany bezpośrednio (jak robi to alias `fun`),
## nie gdy jest sourcowany (np. przez testy jednostkowe, które chcą tylko definicji funkcji).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [ $# -eq 0 ]; then
    log_error "git fun: brak nazwy funkcji"
    exit 1
  fi

  if declare -f "$1" > /dev/null && [[ "$1" == git_* || "$1" == hub_* ]]; then
    "$@"
  else
    log_error "Nieznana funkcja: '$1'
      Dostępne funkcje: $(declare -F | awk '{print $3}' | grep -E '^(git|hub)_' | tr '\n' ' ')"
    exit 1
  fi
fi
