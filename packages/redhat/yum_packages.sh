# Wspólna lista pakietów yum dla redhat/install.sh i redhat/update.sh.
# Sourcowane, nie wykonywane — tylko deklaracje tablic. Mirror packages/commons/apt_packages.sh
# (te same nazwy tablic, nazwy pakietów przemapowane na Fedora/RHEL/CentOS).
#
# Część pakietów (np. neofetch, thefuck, nvme-cli) wymaga EPEL na RHEL/CentOS —
# obsługuje to `install_initial_packages` w redhat/install.sh
# (best-effort `yum install -y epel-release`, brakujące pakiety pomijane przez
# `safe_yum_install`). Celowo NIE ma tu curl/wget — jak w apt_packages.sh, to
# minimalny bootstrap instalowany osobno w każdym skrypcie (`minimal_tools`).
#
# Zweryfikowane e2e na rockylinux:9 (test/e2e/test_initial_packages_redhat.sh) —
# `hub` i `gnome-boxes` pozostają niedostępne bez repo CodeReady Builder (CRB),
# poza samym EPEL; `safe_yum_install` pomija je z ostrzeżeniem, nie przerywa.

system_tools=(
    git vim-enhanced unzip zip tree tmux htop thefuck neofetch hub xdotool util-linux iproute postgresql
)

security_tools=(
    gnupg2 ca-certificates pam-u2f fido2-tools pcsc-lite openssh-clients opensc
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
    ddrescue mdadm pv testdisk
)

# Kompilatory i biblioteki do budowania toolchainów z asdf (ghc z pluginu ghcup, cargo, cabal) — mirror
# build_libs z apt_packages.sh (#172).
build_libs=(
    gcc gcc-c++ make perl gmp-devel ncurses-devel libffi-devel pkgconf-pkg-config xz zlib-devel
)

boxes_vm=(
    gnome-boxes qemu-kvm libvirt-daemon libvirt-daemon-config-network
)
