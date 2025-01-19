#!/bin/bash

# Ensure GIT_SCRIPTS_DIR is set
if [ -z "$GIT_SCRIPTS_DIR" ]; then
  echo "Error: GIT_SCRIPTS_DIR is not set. Please export it in your shell configuration."
  exit 1
fi

# Function definitions

push_upstream() {
  local branch_name
  branch_name=$(git rev-parse --abbrev-ref HEAD)
  git push -u origin "$branch_name"
}

single_push() {
  local branch_name
  branch_name=$(git rev-parse --abbrev-ref HEAD)
  git push origin "$branch_name"
}

branch_create() {
  local type=$1
  local branch_name=$2
  local project_name
  project_name=$(git config project.name)
  if [ -z "$type" ] || [ -z "$branch_name" ]; then
    echo "Usage: branch_create <type> <branch-name>"
    return 1
  fi
  git pull
  git checkout -b "${type}/${project_name}-${branch_name}"
  git push -u origin "${type}/${project_name}-${branch_name}"
}

merge_with() {
  local branch_name=$1
  if [ -z "$branch_name" ]; then
    echo "Usage: merge_with <branch-name>"
    return 1
  fi
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  git checkout "$branch_name"
  git pull
  git checkout "$current_branch"
  git merge "$branch_name"
}

go_to_branch() {
  local branch_type=$1
  local branch_id=$2
  local project_name
  project_name=$(git config project.name)
  if [ -z "$branch_type" ] || [ -z "$branch_id" ]; then
    echo "Usage: go_to_branch <branch-type> <branch-id>"
    return 1
  fi
  git checkout "${branch_type}/${project_name}-${branch_id}"
}

commit_and_push() {
  local commit_message=$1
  if [ -z "$commit_message" ]; then
    echo "Usage: commit_and_push <commit-message>"
    return 1
  fi
  local branch_name
  branch_name=$(git rev-parse --abbrev-ref HEAD)
  git commit -a -m "$commit_message"
  git push -u origin "$branch_name"
}

merge_feature() {
  local feature_id=$1
  local project_name
  project_name=$(git config project.name)
  if [ -z "$feature_id" ]; then
    echo "Usage: merge_feature <feature-id>"
    return 1
  fi
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  git checkout "feature/${project_name}-${feature_id}"
  git merge --no-edit "$current_branch"
}

remove_gone_branches() {
  LANG=en_GB
  git branch -vv | grep ': gone]' | awk '{print $1}' | xargs git branch -D
}

# Export functions for use in subshells
export -f push_upstream
export -f single_push
export -f branch_create
export -f merge_with
export -f go_to_branch
export -f commit_and_push
export -f merge_feature
export -f remove_gone_branches

# Dispatcher (optional for CLI testing)
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  return 0
fi

if declare -f "$1" > /dev/null; then
  "$@"
else
  echo "Error: Function '$1' not found."
  echo "Available functions: push_upstream, single_push, branch_create, merge_with, go_to_branch, commit_and_push, merge_feature, remove_gone_branches"
  exit 1
fi
