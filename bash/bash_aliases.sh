# Lista aliasów do różnych poleceń
alias g=git
alias git='hub'
alias gst='git status'

if [[ "$OS_TYPE" == "Darwin" ]]; then
    command -v gtime >/dev/null 2>&1 && alias time="gtime -f '\t%E real,\t%U user,\t%S sys,\t%K avg_mem,\t%M max_mem,\t%%I IO_ins\t%O IO_outs'"
else
    alias time="$(which time) -f '\t%E real,\t%U user,\t%S sys,\t%K avg_mem,\t%M max_mem,\t%%I IO_ins\t%O IO_outs'"
fi

[[ "$OS_TYPE" != "Darwin" ]] && alias cozy="flatpak run com.github.geigi.cozy"

alias workspace="cd $HOME/workspace"
alias ll='ls -al'
alias la='ls -alt'
alias l='ls -CF'

if [[ "$OS_TYPE" == "Darwin" ]]; then
    alias in-window='open'
else
    alias in-window='xdg-open'
fi

alias ..="cd .."
alias cd..="cd .."

[[ "$OS_TYPE" != "Darwin" ]] && alias iotop="sudo iotop"

if [[ "$OS_TYPE" == "Darwin" ]]; then
    alias alert='osascript -e "display notification \"$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')\""'
else
    alias alert='notify-send --urgency=critical -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
fi

[[ "$OS_TYPE" != "Darwin" ]] && alias fix-net='sudo umount /etc/resolv.conf && sudo mount --rbind -o rslave /run/host/etc/resolv.conf /etc/resolv.conf'

alias pack-repo='rm p p.zip; zip -r p.zip .; base64 p.zip > p; md5sum p p.zip'

if [[ "$OS_TYPE" != "Darwin" ]] && command -v fdfind >/dev/null 2>&1; then
    alias fd='fdfind'
fi
alias unpack-repo='base64 --decode p > p.zip; unzip -u p.zip; fd _remot | xargs rm'

if [[ "$OS_TYPE" == "Darwin" ]]; then
    alias ls='ls -G'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
elif [ -x /usr/bin/dircolors ]; then
    test -r $HOME/.dircolors && eval "$(dircolors -b $HOME/.dircolors)" || eval "$(dircolors -b)"
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
alias claude-local='ANTHROPIC_BASE_URL="http://localhost:11434" ANTHROPIC_API_KEY="ollama" claude --model qwen3-coder'
