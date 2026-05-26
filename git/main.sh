# setup main configuration
if [ ! -e "$HOME/.gitconfig" ] || [ "$GIT_CONFIGURATION_DIR/git_config" -nt "$HOME/.gitconfig" ] ; then
  cat  "$GIT_CONFIGURATION_DIR/git_config" | envsubst > $HOME/.gitconfig
fi

export GIT_FUNCTIONS="${GIT_CONFIGURATION_DIR}/git_functions.sh"