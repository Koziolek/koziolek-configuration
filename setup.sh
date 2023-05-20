#!/bin/bash

set -euo pipefail

cd ~/ || return

SUDO=''
if (( $EUID != 0 )); then
    SUDO='sudo'
fi


check_git() {

  if ! command -v git &> /dev/null
  then
      echo "git could not be found. Installing";
      $SUDO apt update
      $SUDO apt install -y git;
      return $?;
  fi
  return $?;
}

init() {

  git clone https://github.com/Koziolek/git-configuration.git ~/.git-configuration

  cd ~/.git-configuration/

  echo 'In config'

  git checkout --track origin/feature/-split

  echo 'On branch'
  echo `git rev-parse --abbrev-ref HEAD`

  ./install.sh

}

check_git && init