#!/usr/bin/env bash

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

# Dispatcher
if declare -f "$1" > /dev/null; then
  "$@"
else
  echo "Error: Function '$1' not found."
  echo "Available functions: push_upstream, single_push, branch_create, merge_with, go_to_branch, commit_and_push, merge_feature, remove_gone_branches"
  exit 1
fi