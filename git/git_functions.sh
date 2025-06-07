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
    branch_name=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    echo $branch_name
  fi
}

function git_project_name() {
  git config project.name
}

function git_exterminatus() {
  git p
  gone_branches=$(LANG=en_GB git br -vv | grep ': gone]' | awk '{print $1}')
  if [ -n "$gone_branches" ]; then
    echo "$gone_branches" | xargs git br -D
  fi
}

function git_home(){
  local branch_name=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@');
  log_info "Git go home at ${branch_name}"
  git co ${branch_name};
}

function merge_pr() {
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
}


# Dispatcher
if declare -f "$1" > /dev/null; then
  "$@"
else
  echo "Error: Function '$1' not found."
  echo "Available functions: push_upstream, single_push, branch_create, merge_with, go_to_branch, commit_and_push, merge_feature, remove_gone_branches"
  exit 1
fi