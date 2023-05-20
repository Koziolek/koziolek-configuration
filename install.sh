#!/bin/bash

set -euo pipefail

cd ~/ || return

SUDO=''
if (($EUID != 0)); then
  SUDO='sudo'
fi

languages=['nodejs', 'erlang', 'elixir', 'python', 'golang', 'rust']

install_basics() {
  $SUDO apt update
  $SUDO apt-get install -y vim thefuck xdotool neofetch tmux hub curl gnupg2 apt-transport-https ca-certificates \
    software-properties-common libatomic1 libgconf-2-4 libgdk-pixbuf2.0-0 libgl1-mesa-glx libegl1-mesa \
    libxcb-xtest0 libxcb-xinerama0 htop
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

  for i in $languages; do
    echo $i
  done

  asdf plugin-add 'nodejs'
  asdf plugin-add 'erlang'
  asdf plugin-add 'elixir'
  asdf plugin-add 'python'
  asdf plugin-add 'golang'
  asdf plugin-add 'rust'
}
