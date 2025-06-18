# Personal bashrc configuration
# This is Bash, though some POSIX features may be used.

# Define and export our configuration directory

# Load the primary helper functions
if [ -f "${BASH_CONFIGURATION_DIR}/bash_functions.sh" ]; then
  # shellcheck source=/dev/null
  . "${BASH_CONFIGURATION_DIR}/bash_functions.sh"

  # if you need an interactive shell but without reloading (like in git)
  if [ "${SUPRESS_SOURCING}" = "1" ]; then
    export SUPRESS_SOURCING=0
    return 0
  fi

  export SUPRESS_SOURCING=0
  # Source additional files via the helper function
  for conf_file in \
    bash_history \
    bash_misc \
    bash_colors \
    bash_aliases \
    bash_exports \
    bash_completion \
    bash_start_window \
    bash_chat \
    bash_customs; do
    source_if_exists "$conf_file"
  done
else
  echo "Error: 'bash_functions.sh' not found in '${BASH_CONFIGURATION_DIR}'."
fi
