#!/usr/bin/env bash
# Tworzy początkowy layout sesji "main". Wywoływany tylko raz — gdy sesja nie istnieje.
SESSION="main"
WIN_SERVER="SERVER"
WIN_STATE="STATE"
WIN_HOME="HOME"

# Zwraca podany katalog, jeśli istnieje, w przeciwnym razie $HOME — podział okien
# i ich nazwy zostają zawsze takie same, zmienia się tylko katalog startowy panelu.
_dir_or_home() {
    if [ -d "$1" ]; then
        echo "$1"
    else
        echo "$HOME"
    fi
}

# Wysyła komendę do panelu tylko, gdy jej katalog roboczy istnieje — na maszynie
# bez tych osobistych projektów panel zostaje po prostu pustą powłoką zamiast
# odpalać zadanie w złym katalogu (albo z błędem "No such file or directory").
_run_if_dir() {
    local target="$1" dir="$2" cmd="$3"
    [ -d "$dir" ] && tmux send-keys -t "$target" "$cmd" Enter
    return 0
}

create_window_server() {
    local ghost_dir="$HOME/workspace/java/ghost-track"
    local pansa_dir="$HOME/workspace/pansa/local-env-manager"

    tmux new-session -d -s "$SESSION" -n "$WIN_SERVER" \
        -c "$(_dir_or_home "$ghost_dir")"
    tmux split-window -t "$SESSION:$WIN_SERVER" -v -l 70% \
        -c "$(_dir_or_home "$ghost_dir")"
    _run_if_dir "$SESSION:$WIN_SERVER" "$ghost_dir" "ctop"
    tmux select-pane -t "$SESSION:$WIN_SERVER" -U
    tmux split-window -t "$SESSION:$WIN_SERVER" -h \
        -c "$(_dir_or_home "$pansa_dir")"
    _run_if_dir "$SESSION:$WIN_SERVER" "$pansa_dir" "python3 jacoco_servery.py"
    tmux select-pane -t "$SESSION:$WIN_SERVER" -L
    _run_if_dir "$SESSION:$WIN_SERVER" "$ghost_dir" "./start.sh"
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
