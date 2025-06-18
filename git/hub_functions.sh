#!/usr/bin/env bash

function hub_amen() {
  log_info "Vomiting and creating PR in GH"
  git_vomit "$*";
  hub pull-request -m "$*"
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