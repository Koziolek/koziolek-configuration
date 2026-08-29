#!/usr/bin/env bash
# Wspólna lista pakietów apt dla initial_packages.sh i update_packages.sh.
# Sourcowane, nie wykonywane — tylko deklaracje tablic.
#
# Celowo NIE ma tu curl/wget: to minimalny bootstrap, który musi zostać
# zainstalowany bezpośrednio w każdym skrypcie (tablica `minimal_tools`)
# przed czymkolwiek innym, niezależnie od tej wspólnej listy.

system_tools=(
  git vim unzip zip tree tmux htop thefuck neofetch hub xdotool lsb-release iproute2
  postgresql-client-common postgresql-client-16
)

security_tools=(
  gnupg gnupg2 apt-transport-https ca-certificates
)

graphics_libs=(
  libatomic1 libgl1-mesa-dri libglx-mesa0 libegl1-mesa libgles2-mesa
  mesa-utils mesa-utils-extra libglvnd0 libglx0 libegl1 libgles2 libvulkan1
)

gui_libs=(
  gconf2-common gconf-service libgconf-2-4 libgdk-pixbuf2.0-0 libxcb-xtest0 libxcb-xinerama0
)

image_tools=(
  libheif-examples
)

diag_tools=(
  memtester stress-ng dmidecode pciutils lm-sensors smartmontools nvme-cli gdb
  libinput-tools rocminfo
)
