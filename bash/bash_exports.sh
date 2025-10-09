# Set prompt. Depends of pwd - home > 20 then dirtrim=1 else =3
#PROMPT_COMMAND="set_dirtrim_by_path_length${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
PROMPT_DIRTRIM=3
export PS1='${C_GREEN}⛧ 𓃵  ⛧[at]𖠿:${C_LBLUE}\w${C_CYAN}$(parse_git_branch)${C_NC} \$ '

# printer name because cups sucks
export PRINTER='L6170'

export WORKSPACE=$HOME/workspace
export WORKSPACE_TOOLS=$WORKSPACE/tools

export ASDF_DATA_DIR="$HOME/.asdf"
export DOCKER_COMPOSE=$(check_docker_compose_availability)

export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
export PATH=$HOME/.local/bin:$PATH


# Export „secrets”
if [ -f $HOME/.senv ]; then
  . $HOME/.senv
else
  echo 'Secret file $HOME/.senv not exist yet. Creating…'
  echo > $HOME/.senv
  chmod 400 $HOME/.senv
  echo 'Secret file $HOME/.senv has been created. It is user readonly file!'
fi
#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ] && . "$HOME/.sdkman/bin/sdkman-init.sh"
