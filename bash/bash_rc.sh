# this is my personal configuration of bashrc.
# this is bash, but I use some POSIX stuff.

# lets define our "home"
export BASH_CONFIGURATION_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )";
# Load helper function
. "${BASH_CONFIGURATION_DIR}/bash_functions.sh"
source_if_exists "bash_history"
source_if_exists "bash_misc"
source_if_exists "bash_colors"
source_if_exists "bash_aliases"
source_if_exists "bash_exports"
source_if_exists "bash_completion"
source_if_exists "bash_start_window"
