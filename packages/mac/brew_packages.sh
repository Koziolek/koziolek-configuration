#!/usr/bin/env bash
# Wspólna lista pakietów brew dla mac/install.sh i mac/update.sh.
# Sourcowane, nie wykonywane — tylko deklaracje tablic.
#
# Celowo NIE ma tu curl/wget: to minimalny bootstrap, który musi zostać
# zainstalowany bezpośrednio w każdym skrypcie (tablica `minimal_tools`)
# przed czymkolwiek innym, niezależnie od tej wspólnej listy (analogicznie
# do packages/commons/apt_packages.sh dla Linuksa).

system_tools=(
    git vim unzip zip tree tmux htop neofetch hub nmap
    libpq
    kubernetes-cli
    pam-u2f
    libfido2
    gnupg
    pinentry-mac
    openssh
    opensc
    git-bug
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
    ddrescue
    pv
    testdisk
)
