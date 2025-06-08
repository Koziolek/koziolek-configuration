#!/usr/bin/env bash

# This is non-interactive shell! We need source functions manually
if [ -n "$BASH_CONFIGURATION_DIR" ] && [ -d "$BASH_CONFIGURATION_DIR" ]; then
    source "${BASH_CONFIGURATION_DIR}/bash_functions.sh"
fi

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

function git_delete_merged_remote() {
  for branch in $(git branch -r --merged master | grep -v /master | sed 's/origin\///g'); do
    git push -d origin $branch
  done
}

# Remove merged branches
function git_exterminatus() {
  local project_name=$(git_project_name);
  log_man \
  "In fealty to the God-Emperor, our undying Lord,
      and by the grace of the Golden Throne,
      I declare Exterminatus upon the project of ${project_name}"
  git_delete_merged_remote
  git p
  gone_branches=$(LANG=en_GB git br -vv | grep ': gone]' | awk '{print $1}')
  if [ -n "$gone_branches" ]; then
    echo "$gone_branches" | xargs git br -D
  fi
}

# Git go home.
function git_home(){
  local home_branch_name=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@');
  log_info "Git go home at ${home_branch_name}"
  git co ${home_branch_name};
}

# Merging pull request in github repo
function hub_merge_pr() {
  local pr="$1"

  if [ -z "$pr" ]; then
    log_man "Usage: merge_pr NUMBER
      NUMBER - number of existing, open pull request in github repository
    "
    return 1;
  fi

  local to_merge=$(hub pr list -f %U%n | grep /$pr)

  if [ -z "$to_merge"]; then
    log_error "Pull request with number ${pr} does not exists. Existing pull requests:"
    hub pr list -f %U%n
    return 1;
  fi

  log_info "Merging pull request ${to_merge}"
  git home
  hub merge $to_merge
  git push
}

function git_init_multi_hooks(){
  rm .git/hooks/*
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
    cat "${GIT_CONFIGURATION_DIR}/hook/multihooks-template.sh" > "./.git/hooks/${hook}"
    mkdir  "./.git/hooks/${hook}.d"
    chmod +x ./.git/hooks/*
  done
}

# Initialize repository in current dir like git init, and then setup additional stuff
function git_init(){
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

function git_new_branch(){
  local type="feature"
  case "$1" in
    feature|version|fix|experimental)
      type="$1"
      shift
      ;;
    *)
      type="feature"
      ;;
  esac

  local branch_name=$(to_ascii "$*" | sed 's/[^a-zA-Z0-9 _-]//g')
  branch_name=$(to_kebab_case "$branch_name")

  if [ -z $branch_name ]; then
    log_error "Branch need a name"
    return 1
  fi

  local project_name=$(git_project_name)
  if [ -n $project_name ]; then
    branch_name="${project_name}-${branch_name}"
  fi
  branch_name="${type}/${branch_name}"

  git pull
  git co -b "${branch_name}"
  git push -u origin "${branch_name}"
}

function git_new_feature_branch(){
  git_new_branch "feature $*"
}
function git_new_version_branch(){
  git_new_branch "version $*"
}
function git_new_fix_branch(){
  git_new_branch "fix $*"
}
function git_new_experimental_branch(){
  git_new_branch "experimental $*"
}

function git_vomit(){
  local branch_name=$(git_current_branch)
  git add .
  git ci -a -m "$*"
  git push -u origin $branch_name
}

# Dispatcher
if declare -f "$1" > /dev/null; then
  "$@"
else
  log_error "Function '$1' not found.
    Available functions: push_upstream, single_push, branch_create, merge_with, go_to_branch, commit_and_push, merge_feature, remove_gone_branches"
  exit 1
fi
