#!/usr/bin/env bash
# Wspólna lista pakietów apt dla initial_packages_ubuntu.sh i update_packages_ubuntu.sh.
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
  gnupg gnupg2 apt-transport-https ca-certificates libpam-u2f fido2-tools
  scdaemon pcscd openssh-client opensc
)

graphics_libs=(
  libatomic1 libgl1-mesa-dri libglx-mesa0
  mesa-utils mesa-utils-extra libglvnd0 libglx0 libegl1 libgles2 libvulkan1
)

# GConf (GNOME 2) zniknął z Debiana/Ubuntu lata temu — usunięty stąd
# (był bezużyteczny, tylko "not found, skipping" w każdym logu). libgdk-pixbuf2.0-0
# zostaje mimo że na Debian sid akurat nie ma kandydata (trwająca transformacja
# nazwy pakietu) — na Ubuntu wciąż jest realny; safe_apt_install (patrz
# initial_packages_ubuntu.sh/initial_packages_vanilla.sh) poprawnie go pomija
# z ostrzeżeniem zamiast wywalać całą instalację, patrz #124.
gui_libs=(
  libgdk-pixbuf2.0-0 libxcb-xtest0 libxcb-xinerama0
)

image_tools=(
  libheif-examples
)

diag_tools=(
  memtester stress-ng dmidecode pciutils lm-sensors smartmontools nvme-cli gdb
  libinput-tools rocminfo
)

boxes_vm=(
  gnome-boxes qemu-kvm libvirt-daemon-system
)
