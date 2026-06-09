# Set prompt. Depends of pwd - home > 20 then dirtrim=1 else =3
#PROMPT_COMMAND="set_dirtrim_by_path_length${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
PROMPT_DIRTRIM=3
export PS1='${C_GREEN}⛧ 𓃵  ⛧[at]𖠿:${C_LBLUE}\w${C_CYAN}$(parse_git_branch)${C_NC} \$ '

# printer name because cups sucks
export PRINTER='L6170'

export WORKSPACE=$HOME/workspace
export WORKSPACE_TOOLS=$WORKSPACE/tools

export ASDF_DATA_DIR="$HOME/.asdf"
if command -v docker >/dev/null 2>&1; then
    export DOCKER_COMPOSE="docker compose"
else
    log_error "docker compose plugin nie jest dostępny. Zainstaluj docker-compose-plugin."
    export DOCKER_COMPOSE=""
fi

if [[ "$OS_TYPE" == "Darwin" ]]; then
    if [ -d /opt/homebrew ]; then
        export HOMEBREW_PREFIX="/opt/homebrew"
    elif [ -d /usr/local/Homebrew ]; then
        export HOMEBREW_PREFIX="/usr/local"
    fi
    if [ -n "$HOMEBREW_PREFIX" ]; then
        export PATH="$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:$PATH"
        export HOMEBREW_CELLAR="$HOMEBREW_PREFIX/Cellar"
        export HOMEBREW_REPOSITORY="$HOMEBREW_PREFIX/Homebrew"
        export INFOPATH="$HOMEBREW_PREFIX/share/info:${INFOPATH:-}"
        export MANPATH="$HOMEBREW_PREFIX/share/man:${MANPATH:-}"
    fi
fi

export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
export PATH=$HOME/.local/bin:$PATH

export CLAUDE_SKILL_CONFIG=$WORKSPACE/ai/claude/config.json

# Export „secrets”
if [ -f $HOME/.senv ]; then
  . $HOME/.senv
else
  echo 'Secret file $HOME/.senv not exist yet. Creating…'
  echo > $HOME/.senv
  chmod 400 $HOME/.senv
  echo 'Secret file $HOME/.senv has been created. It is user readonly file!'
fi
export SDKMAN_DIR="$HOME/.sdkman"

if [ -d "$SDKMAN_DIR/candidates" ]; then
    for _cdir in "$SDKMAN_DIR/candidates"/*/current; do
        [ -d "$_cdir/bin" ] && export PATH="$_cdir/bin:$PATH"
    done
    unset _cdir
    [ -d "$SDKMAN_DIR/candidates/java/current" ]   && export JAVA_HOME="$SDKMAN_DIR/candidates/java/current"
    [ -d "$SDKMAN_DIR/candidates/maven/current" ]  && export MAVEN_HOME="$SDKMAN_DIR/candidates/maven/current"
    [ -d "$SDKMAN_DIR/candidates/mvnd/current" ]   && export MVND_HOME="$SDKMAN_DIR/candidates/mvnd/current"
    [ -d "$SDKMAN_DIR/candidates/quarkus/current" ] && export QUARKUS_HOME="$SDKMAN_DIR/candidates/quarkus/current"
fi

_sdkman_init() {
    PROMPT_COMMAND="${PROMPT_COMMAND//_sdkman_init;/}"
    PROMPT_COMMAND="${PROMPT_COMMAND//_sdkman_init/}"
    unset -f _sdkman_init
    [ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ] && . "$SDKMAN_DIR/bin/sdkman-init.sh"
}
PROMPT_COMMAND="_sdkman_init${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
