# This is a main point of whole configuration.
export OS_TYPE="$(uname -s)"
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do _src="$(readlink "$_src")"; done
export MAIN_CONFIGURATION_DIR="$( cd -- "$( dirname -- "$_src" )" && pwd -P )"
unset _src
export BASH_CONFIGURATION_DIR="$MAIN_CONFIGURATION_DIR/bash"
export GIT_CONFIGURATION_DIR="$MAIN_CONFIGURATION_DIR/git"
export SERVICES_CONFIGURATION_DIR="$MAIN_CONFIGURATION_DIR/services"
export TMUX_CONFIGURATION_DIR="$MAIN_CONFIGURATION_DIR/tmux"

. "$BASH_CONFIGURATION_DIR/main.sh"
. "$GIT_CONFIGURATION_DIR/main.sh"
. "$SERVICES_CONFIGURATION_DIR/main.sh"
. "$TMUX_CONFIGURATION_DIR/main.sh"

verify_configuration