# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

. /usr/share/bash-completion/completions/git
. <(asdf completion bash)

# alias g=git support
complete -o bashdefault -o default -o nospace -F __git_wrap__git_main g 2>/dev/null \
  || complete -o default -o nospace -F __git_wrap__git_main g

#. $HOME/.asdf/asdf.sh
#. $HOME/.asdf/completions/asdf.bash
. $HOME/.maven-bash-completion/bash_completion.bash
. $MVND_HOME/bin/mvnd-bash-completion.bash
