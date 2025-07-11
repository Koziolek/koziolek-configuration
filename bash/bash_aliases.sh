# Lista aliasów do różnych poleceń
alias g=git
alias git='hub'
alias gst='git status'
alias time="$(which time) -f '\t%E real,\t%U user,\t%S sys,\t%K avg_mem,\t%M max_mem,\t%%I IO_ins\t%O IO_outs'"
alias cozy="flatpak run com.github.geigi.cozy"
alias workspace="cd ~/workspace"
alias ll='ls -al'
alias la='ls -alt'
alias l='ls -CF'
alias in-window='xdg-open'
alias ..="cd .."
alias cd..="cd .."
alias iotop="sudo iotop"
alias alert='notify-send --urgency=critical -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias dir='dir --color=auto'
    alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Aliases if you need other fluff
alias order66="exterminatus"
alias omega-protocol="exterminatus"