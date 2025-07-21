# This is a main point of whole configuration.
export MAIN_CONFIGURATION_DIR="$( cd -- "$( dirname -- $( realpath "${BASH_SOURCE[0]}") )" && pwd )"
export BASH_CONFIGURATION_DIR="$MAIN_CONFIGURATION_DIR/bash"
export GIT_CONFIGURATION_DIR="$MAIN_CONFIGURATION_DIR/git"
export SERVICES_CONFIGURATION_DIR="$MAIN_CONFIGURATION_DIR/services"

. "$BASH_CONFIGURATION_DIR/main.sh"
. "$GIT_CONFIGURATION_DIR/main.sh"
. "$SERVICES_CONFIGURATION_DIR/main.sh"

verify_configuration