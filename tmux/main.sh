export TMUX_CONFIGURATION_DIR="$MAIN_CONFIGURATION_DIR/tmux"

if [ ! -L "$HOME/.tmux.conf" ] || [ "$TMUX_CONFIGURATION_DIR/tmux.conf" -nt "$HOME/.tmux.conf" ]; then
    ln -sf "$TMUX_CONFIGURATION_DIR/tmux.conf" "$HOME/.tmux.conf"
fi
