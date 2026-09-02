# setup main configuration
#
# Model: szablon w repo (git/templates/git_config.template) jest renderowany do
# $HOME/.gitconfig.generated przy każdym starcie, jeśli szablon jest nowszy —
# ten plik nigdy nie jest edytowany ręcznie, więc wolno go swobodnie nadpisywać.
# $HOME/.gitconfig to mały "stub" z jednym wpisem [include] wskazującym na
# powyższy plik; tworzony tylko raz, gdy nie istnieje. Ręczne `git config
# --global ...` użytkownika lądują w stubie i przeżywają aktualizacje repo
# (w przeciwieństwie do poprzedniego modelu, który regenerował cały plik).
GIT_CONFIG_TEMPLATE="$GIT_CONFIGURATION_DIR/templates/git_config.template"
GIT_CONFIG_GENERATED="$HOME/.gitconfig.generated"
GIT_CONFIG_STUB="$HOME/.gitconfig"

if [ ! -e "$GIT_CONFIG_GENERATED" ] || [ "$GIT_CONFIG_TEMPLATE" -nt "$GIT_CONFIG_GENERATED" ]; then
  envsubst '$GIT_CONFIGURATION_DIR' < "$GIT_CONFIG_TEMPLATE" > "$GIT_CONFIG_GENERATED"
fi

if [ ! -e "$GIT_CONFIG_STUB" ]; then
  printf '[include]\n\tpath = %s\n' "$GIT_CONFIG_GENERATED" > "$GIT_CONFIG_STUB"
fi

unset GIT_CONFIG_TEMPLATE GIT_CONFIG_GENERATED GIT_CONFIG_STUB

export GIT_FUNCTIONS="${GIT_CONFIGURATION_DIR}/git_functions.sh"

# git_vomit/git_bleeh: domyślnie auto-akceptacja commit-message.txt (bez podglądu [T/n]).
# Ustaw GIT_ASSUME_YES=0 (np. w ~/.senv), aby wymusić potwierdzenie.
export GIT_ASSUME_YES="${GIT_ASSUME_YES:-0}"