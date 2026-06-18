#!/usr/bin/env bash
# Tworzy początkowy layout sesji "main". Wywoływany tylko raz — gdy sesja nie istnieje.
SESSION="main"
WIN_SERVER="SERVER"
WIN_STATE="STATE"
WIN_HOME="HOME"

create_window_server() {
    tmux new-session -d -s "$SESSION" -n "$WIN_SERVER" \
        -c "$HOME/workspace/java/ghost-track"
    tmux split-window -t "$SESSION:$WIN_SERVER" -v -l 70% \
        -c "$HOME/workspace/java/ghost-track"
    tmux send-keys -t "$SESSION:$WIN_SERVER" "ctop" Enter
    tmux select-pane -t "$SESSION:$WIN_SERVER" -U
    tmux split-window -t "$SESSION:$WIN_SERVER" -h \
        -c "$HOME/workspace/pansa/local-env-manager"
    tmux send-keys -t "$SESSION:$WIN_SERVER" "python3 jacoco_servery.py" Enter
    tmux select-pane -t "$SESSION:$WIN_SERVER" -L
    tmux send-keys -t "$SESSION:$WIN_SERVER" "./start.sh" Enter
}

create_window_state() {
    tmux new-window -t "$SESSION" -n "$WIN_STATE"
    tmux send-keys -t "$SESSION:$WIN_STATE" "htop" Enter
}

create_window_home() {
    tmux new-window -t "$SESSION" -n "$WIN_HOME" \
        -c "$HOME"
}

create_window_server
create_window_state
create_window_home
tmux select-window -t "$SESSION:$WIN_HOME"
