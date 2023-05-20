#!/bin/bash

set -euo pipefail

cd ~/ || return

SUDO=''
if (($EUID != 0)); then
  SUDO='sudo'
fi

declare -a languages=('nodejs' 'erlang' 'elixir' 'python' 'golang' 'rust')

install_basics() {
  $SUDO apt update
  $SUDO apt-get install -y vim thefuck xdotool neofetch tmux hub curl gnupg2 apt-transport-https ca-certificates \
    software-properties-common libatomic1 libgconf-2-4 libgdk-pixbuf2.0-0 libgl1-mesa-glx libegl1-mesa \
    libxcb-xtest0 libxcb-xinerama0 htop build-essential unzip

  return $?
}

workspace() {
  [ -d ~/workspace/ ] || mkdir workspace
  cd ~/workspace
  return $?
}

asdf() {
  workspace

  git clone https://github.com/asdf-vm/asdf.git
  cd asdf || return
  git tag -l --sort=committerdate | tail -1 | xargs git checkout -d

  ln -s ~/workspace/asdf ~/.asdf
}

install_asdf_plugins() {
  echo "INSTALLING asdf"

  chmod a+x ~/.asdf/asdf.sh

  for i in "${languages[@]}"; do
    ~/.asdf/bin/asdf plugin add $i
  done

}

install_asdf_shims() {
  echo "INSTALLING shims"
  for i in "${languages[@]}"; do
    echo " - $i"
    ~/.asdf/bin/asdf install $i latest
  done

}

verify_asdf() {
  echo "VERFING asdf"
  ~/.asdf/bin/asdf list

  cat ~/.bashrc
}

execute() {
 install_basics && asdf && install_asdf_plugins && install_asdf_shims && verify_asdf
}

execute
