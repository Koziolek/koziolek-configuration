#!/usr/bin/env bash
# Kontekst: linux — bazowy dla debian/ubuntu/vanilla/wsl.
# Ładowany PIERWSZY w łańcuchu; bardziej szczegółowe konteksty go nadpisują.
#
# Funkcje z functions.d/ są już w wersji Linux (bez guardów uname) — macOS
# cieniuje je w contexts/darwin.sh. Tu nic z tego nie trzeba.

# make less more friendly for non-text input files, see lesspipe(1)
# (przeniesione z bash_misc.sh — na macOS lesspipe idzie inną drogą / brak)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# --- Aliasy swoiste dla Linuksa (przeniesione z bash_aliases.sh) -----------
alias cozy="flatpak run com.github.geigi.cozy"
alias iotop="sudo iotop"
alias in-window='xdg-open'
alias alert='notify-send --urgency=critical -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

command -v fdfind >/dev/null 2>&1 && alias fd='fdfind'

if command -v time >/dev/null 2>&1; then
    alias time="$(command -v time) -f '\t%E real,\t%U user,\t%S sys,\t%K avg_mem,\t%M max_mem,\t%%I IO_ins\t%O IO_outs'"
fi

if [ -x /usr/bin/dircolors ]; then
    if test -r "$HOME/.dircolors"; then eval "$(dircolors -b "$HOME/.dircolors")"; else eval "$(dircolors -b)"; fi
    alias ls='ls --color=auto'
    alias dir='dir --color=auto'
    alias vdir='vdir --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi
