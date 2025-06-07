# Set prompt. Depends of pwd - home > 20 then dirtrim=1 else =3
PROMPT_COMMAND="set_dirtrim_by_path_length${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
export PS1='${C_GREEN}⛧ 𓃵  ⛧[at]𖠿:${C_LBLUE}\w${C_CYAN}$(parse_git_branch)${C_NC}\$ '

# printer name because cups sucks
export PRINTER='L6170'
# Add the directory of Tizen .NET Command Line Tools to user path.
export PATH=$HOME/.bin:$PATH
export WORKSPACE=~/workspace
export WORKSPACE_TOOLS=$WORKSPACE/tools
export SERVICES_DATA=${WORKSPACE_TOOLS}/_data
export ARTIFACTORY_DATA=${WORKSPACE_TOOLS}/artifactory/artifactory_data
export POSTGRES_DATA=${WORKSPACE_TOOLS}/postgres_data
export ASDF_DATA_DIR="$HOME/.asdf"
export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
export PATH=/home/koziolek/.local/bin:$PATH

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
export SDKMAN_DIR="/home/koziolek/.sdkman"
[ -s "/home/koziolek/.sdkman/bin/sdkman-init.sh" ] && . "/home/koziolek/.sdkman/bin/sdkman-init.sh"
