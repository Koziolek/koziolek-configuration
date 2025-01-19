# Personal bashrc configuration
# This is Bash, though some POSIX features may be used.

# Define and export our configuration directory
export BASH_CONFIGURATION_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )"

# Load the primary helper functions
if [ -f "${BASH_CONFIGURATION_DIR}/bash_functions.sh" ]; then
    # shellcheck source=/dev/null
    . "${BASH_CONFIGURATION_DIR}/bash_functions.sh"

    # Source additional files via the helper function
    for conf_file in \
        bash_history \
        bash_misc \
        bash_colors \
        bash_aliases \
        bash_exports \
        bash_completion \
        bash_start_window \
        bash_chat
    do
        source_if_exists "$conf_file"
    done
else
    echo "Error: 'bash_functions.sh' not found in '${BASH_CONFIGURATION_DIR}'."
fi
