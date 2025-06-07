if supports_colors; then
  export C_RED=$'\033[0;31m'
  export C_GREEN=$'\033[0;32m'
  export C_YELLOW=$'\033[1;33m'
  export C_BLUE=$'\033[0;34m'
  export C_LBLUE=$'\033[0;94m'
  export C_PURPLE=$'\033[0;35m'
  export C_CYAN=$'\033[0;36m'
  export C_WHITE=$'\033[1;37m'
  export C_BOLD=$'\033[1m'
  export C_NC=$'\033[0m'  # No Color
else
  export C_RED=''
  export C_GREEN=''
  export C_YELLOW=''
  export C_BLUE=''
  export C_LBLUE=''
  export C_PURPLE=''
  export C_CYAN=''
  export C_WHITE=''
  export C_BOLD=''
  export C_NC=''
fi
