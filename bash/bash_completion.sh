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

if [ -f /usr/share/bash-completion/completions/git ]; then
    . /usr/share/bash-completion/completions/git
fi

if command -v asdf &> /dev/null; then
    . <(asdf completion bash)
fi

if declare -f __git_wrap__git_main &> /dev/null; then
    complete -o bashdefault -o default -o nospace -F __git_wrap__git_main g 2>/dev/null \
      || complete -o default -o nospace -F __git_wrap__git_main g
fi

if ! command -v mvn &> /dev/null; then
    sdk i maven
fi
if [ -f "$HOME/.maven-bash-completion/bash_completion.bash" ]; then
    . "$HOME/.maven-bash-completion/bash_completion.bash"
fi

if ! command -v mvnd &> /dev/null; then
    sdk i mvnd
    export MVND_HOME="${HOME}/.sdkman/candidates/mvnd/current/"
fi
if [ -n "$MVND_HOME" ] && [ -f "$MVND_HOME/bin/mvnd-bash-completion.bash" ]; then
    . "$MVND_HOME/bin/mvnd-bash-completion.bash"
fi