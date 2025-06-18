# Personal bashrc configuration
# This is Bash, though some POSIX features may be used.

# Define and export our configuration directory


function load_config() {
    for conf_file in services_functions; do
      source_if_exists "$conf_file" "${SERVICES_CONFIGURATION_DIR}"
    done
}

if [ -n "$BASH_FUNCTIONS_LOADED" ] && [ "$BASH_FUNCTIONS_LOADED" -eq 1 ]; then
  load_config
elif [ -f "${BASH_CONFIGURATION_DIR}/bash_functions.sh" ]; then
  . "${BASH_CONFIGURATION_DIR}/bash_functions.sh"
  load_config
else
    echo "Error: 'bash_functions.sh' not found in '${BASH_CONFIGURATION_DIR}'."
fi

