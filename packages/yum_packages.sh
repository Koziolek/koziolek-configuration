# Wspólna lista pakietów yum dla initial_packages_redhat.sh i update_packages_redhat.sh.
# Sourcowane, nie wykonywane — tylko deklaracje tablic. Mirror packages/apt_packages.sh
# (te same nazwy tablic, nazwy pakietów przemapowane na Fedora/RHEL/CentOS).
#
# Część pakietów (np. neofetch, thefuck, nvme-cli) wymaga EPEL na RHEL/CentOS —
# obsługuje to `install_initial_packages` w initial_packages_redhat.sh
# (best-effort `yum install -y epel-release`, brakujące pakiety pomijane przez
# `safe_yum_install`). Celowo NIE ma tu curl/wget — jak w apt_packages.sh, to
# minimalny bootstrap instalowany osobno w każdym skrypcie (`minimal_tools`).

system_tools=(
  git vim unzip zip tree tmux htop thefuck neofetch hub xdotool util-linux iproute postgresql
)

security_tools=(
  gnupg2 ca-certificates
)

graphics_libs=(
  libatomic mesa-dri-drivers mesa-libGL mesa-libGLU mesa-libEGL mesa-libgbm
  mesa-vulkan-drivers vulkan-loader
)

gui_libs=(
  GConf2 gdk-pixbuf2 libxcb
)

image_tools=(
  libheif-tools
)

diag_tools=(
  memtester stress-ng dmidecode pciutils lm_sensors smartmontools nvme-cli gdb
  libinput-utils
)

boxes_vm=(
  gnome-boxes qemu-kvm libvirt-daemon libvirt-daemon-config-network
)
