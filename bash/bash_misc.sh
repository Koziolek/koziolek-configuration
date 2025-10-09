# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# sometimes we misspell spell…
command -v thefuck >/dev/null 2>&1 && eval "$(thefuck --alias)"

# jebana konfiguracja spotify 
command -v pactl >/dev/null 2>&1 && pactl set-default-sink alsa_output.usb-Razer_Razer_Kraken_Kitty_Edition_00000000-00.analog-stereo

