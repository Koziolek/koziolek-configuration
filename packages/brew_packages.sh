#!/usr/bin/env bash
# Wspólna lista pakietów brew dla initial_packages_mac.sh i update_packages_mac.sh.
# Sourcowane, nie wykonywane — tylko deklaracje tablic.
#
# Celowo NIE ma tu curl/wget: to minimalny bootstrap, który musi zostać
# zainstalowany bezpośrednio w każdym skrypcie (tablica `minimal_tools`)
# przed czymkolwiek innym, niezależnie od tej wspólnej listy (analogicznie
# do packages/apt_packages.sh dla Linuksa).

system_tools=(
  git vim unzip zip tree tmux htop neofetch hub
  libpq
  kubernetes-cli
)

shell_tools=(
  bash
  thefuck
  fd
  gnu-time
  gnu-sed
  coreutils
)

image_tools=(
  libheif
  imagemagick
)

diag_tools=(
  smartmontools
  gdb
)
