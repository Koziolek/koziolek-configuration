if ! shopt -oq posix; then
    _lazy_completion() {
        unset -f _lazy_completion
        if [ -f /usr/share/bash-completion/bash_completion ]; then
            . /usr/share/bash-completion/bash_completion
        elif [ -f /etc/bash_completion ]; then
            . /etc/bash_completion
        fi
        if declare -f __git_wrap__git_main &>/dev/null; then
            complete -o bashdefault -o default -o nospace -F __git_wrap__git_main g 2>/dev/null \
                || complete -o default -o nospace -F __git_wrap__git_main g
        fi
        _completion_loader "$@"
    }
    complete -D -F _lazy_completion
fi

_git_lazy() {
    [ -f /usr/share/bash-completion/completions/git ] && . /usr/share/bash-completion/completions/git
    if declare -f __git_wrap__git_main &>/dev/null; then
        complete -o bashdefault -o default -o nospace -F __git_wrap__git_main g 2>/dev/null \
            || complete -o default -o nospace -F __git_wrap__git_main g
    fi
    unset -f _git_lazy
    declare -f __git_wrap__git_main &>/dev/null && __git_wrap__git_main "$@"
}
complete -o bashdefault -o default -o nospace -F _git_lazy g

_ASDF_BIN="$HOME/.local/bin/asdf"
_ASDF_COMP="$HOME/.cache/asdf_bash_completion"
if command -v asdf &>/dev/null; then
    if [ ! -f "$_ASDF_COMP" ] || [ "$_ASDF_BIN" -nt "$_ASDF_COMP" ]; then
        mkdir -p "$(dirname "$_ASDF_COMP")"
        asdf completion bash >"$_ASDF_COMP" 2>/dev/null
    fi
    [ -f "$_ASDF_COMP" ] && . "$_ASDF_COMP"
fi
unset _ASDF_BIN _ASDF_COMP

if ! command -v mvn &>/dev/null; then sdk i maven; fi
if [ -f "$HOME/.maven-bash-completion/bash_completion.bash" ]; then
    . "$HOME/.maven-bash-completion/bash_completion.bash"
fi

if ! command -v mvnd &>/dev/null; then
    sdk i mvnd
    export MVND_HOME="${HOME}/.sdkman/candidates/mvnd/current/"
fi
if [ -n "$MVND_HOME" ] && [ -f "$MVND_HOME/bin/mvnd-bash-completion.bash" ]; then
    . "$MVND_HOME/bin/mvnd-bash-completion.bash"
fi
