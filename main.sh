# This is a main point of whole configuration.
export OS_TYPE="$(uname -s)"
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
    _dir="$( cd -P -- "$( dirname -- "$_src" )" && pwd -P )"
    _link="$(readlink -- "$_src")"
    case "$_link" in
        /*) _src="$_link" ;;
        *)  _src="$_dir/$_link" ;;
    esac
done
export MAIN_CONFIGURATION_DIR="$( cd -- "$( dirname -- "$_src" )" && pwd -P )"
unset _src _dir _link
export BASH_CONFIGURATION_DIR="$MAIN_CONFIGURATION_DIR/bash"
export GIT_CONFIGURATION_DIR="$MAIN_CONFIGURATION_DIR/git"
export SERVICES_CONFIGURATION_DIR="$MAIN_CONFIGURATION_DIR/services"
export TMUX_CONFIGURATION_DIR="$MAIN_CONFIGURATION_DIR/tmux"
export CONTEXTS_DIR="$BASH_CONFIGURATION_DIR/contexts"

# Kontekst środowiska (patrz bash/contexts/detect.sh). Ustawiane tu — przed
# podsystemami — żeby $CONFIG_CONTEXT/context_is były dostępne też w git/services/tmux,
# gdyby któryś z tych podsystemów kiedyś tego potrzebował. Na razie żaden z nich z tego
# nie korzysta — całe różnicowanie per-system mieszka w bash/contexts/*.sh. Pliki
# per-kontekst ładuje load_contexts() z bash/main.sh (potrzebuje helperów z bash_functions.sh).
if [ -r "$CONTEXTS_DIR/detect.sh" ]; then
    . "$CONTEXTS_DIR/detect.sh"
    export CONFIG_CONTEXT="$(detect_context)"
fi

. "$BASH_CONFIGURATION_DIR/main.sh"
. "$GIT_CONFIGURATION_DIR/main.sh"
. "$SERVICES_CONFIGURATION_DIR/main.sh"
. "$TMUX_CONFIGURATION_DIR/main.sh"

verify_configuration