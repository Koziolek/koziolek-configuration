# Set prompt. Depends of pwd - home > 20 then dirtrim=1 else =3
#PROMPT_COMMAND="set_dirtrim_by_path_length${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
PROMPT_DIRTRIM=3
export PS1='${C_GREEN}⛧ 𓃵  ⛧[at]𖠿:${C_LBLUE}\w${C_CYAN}$(parse_git_branch)${C_NC} \$ '

# printer name because cups sucks
export PRINTER='L6170'

export WORKSPACE=~/workspace
export WORKSPACE_TOOLS=$WORKSPACE/tools

export ASDF_DATA_DIR="$HOME/.asdf"
export DOCKER_COMPOSE=$(check_docker_compose_availability)

export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
export PATH=~/.local/bin:$PATH


# Export „secrets”
if [ -f ~/.senv ]; then
  . ~/.senv
else
  echo 'Secret file ~/.senv not exist yet. Creating…'
  echo > ~/.senv
  chmod 400 ~/.senv
  echo 'Secret file ~/.senv has been created. It is user readonly file!'
fi
#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="~/.sdkman"
[ -s "~/.sdkman/bin/sdkman-init.sh" ] && . "~/.sdkman/bin/sdkman-init.sh"
