#!/bin/bash

set -euo pipefail
current=$(pwd)
is_git_init() {
  if [[ -d "$current/.git" ]]; then
    return 0
  else
    return 1
  fi
}

is_setup_done_before() {
  if [[ -f "$current/.gitsetup" ]]; then
    return 0
  else
    return 1
  fi
}

initial_check() {
  echo "Checking status…"

  set +e
  is_git_init
  is_init=$?
  set -e

  if [[ $is_init != 0 ]]; then
    echo "Project has no repository yet. Exiting"
    exit 0
  fi

  set +e
  is_setup_done_before
  is_setup=$?
  set -e

  if [[ $is_setup == 0 ]]; then
    echo "Project is ready. Exiting"
    exit 0
  fi

}

read_project_name() {
  echo "Please give me project Key. This value ahead ticket number in tracker e.g. TIG-111, TIG is key."
  echo "Key must match ([A-Z0-9]{1,10})|(#)"
  read -r project_name

  if [[ $project_name =~ [A-Z0-9]+ ]]; then
    return 0
  fi

  while :; do
    echo "Please give me VALID project Key."
    echo "Key must match ([A-Z0-9]{1,10})|(#)"
    read -r project_name

    if [[ $project_name =~ ([A-Z0-9]{1,10})|(#) ]]; then
      return 0
    fi
  done
}

initial_check

echo "Start setup"
read_project_name

git config project.name $project_name
git config core.hooksPath .hooks

#touch .gitsetup
ignored=`cat .gitignore | grep .gitsetup`
echo $ignored
echo .gitsetup >> .gitignore