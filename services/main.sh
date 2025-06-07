# Personal bashrc configuration
# This is Bash, though some POSIX features may be used.

# Define and export our configuration directory

# Load the primary helper functions
if [ -f "${BASH_CONFIGURATION_DIR}/bash_functions.sh" ]; then
    # shellcheck source=/dev/null
    . "${BASH_CONFIGURATION_DIR}/bash_functions.sh"

    # Source additional files via the helper function
    for conf_file in \
      services_functions
    do
        source_if_exists "$conf_file" "${SERVICES_CONFIGURATION_DIR}"
    done


else
    echo "Error: 'bash_functions.sh' not found in '${BASH_CONFIGURATION_DIR}'."
fi
