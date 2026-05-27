#!/usr/bin/env bash
# Tworzy początkowy layout sesji "main". Wywoływany tylko raz — gdy sesja nie istnieje.
SESSION="main"

# ── Okno 0: ctop ─────────────────────────────────────────────────────────────
# Layout: [bash | python3] (góra ~30%) / [ctop] (dół ~70%)
tmux new-session -d -s "$SESSION" -n "ctop" \
    -c "$HOME/workspace/java/ghost-track"

# Podziel pionowo — dolny panel dostaje 70%
tmux split-window -t "$SESSION:ctop" -v -l 70% \
    -c "$HOME/workspace/java/ghost-track"
# Aktywny jest teraz dolny panel — uruchom ctop
tmux send-keys -t "$SESSION:ctop" "ctop" Enter

# Przejdź do górnego panelu i podziel poziomo
tmux select-pane -t "$SESSION:ctop" -U
tmux split-window -t "$SESSION:ctop" -h \
    -c "$HOME/workspace/pansa/local-env-manager"
# Aktywny jest teraz prawy górny panel — uruchom skrypt Python
tmux send-keys -t "$SESSION:ctop" "python3 jacoco_servery.py" Enter

# Wróć do lewego górnego panelu (bash)
tmux select-pane -t "$SESSION:ctop" -L

# ── Okno 1: htop ─────────────────────────────────────────────────────────────
tmux new-window -t "$SESSION" -n "htop"
tmux send-keys -t "$SESSION:htop" "htop" Enter

# Ustaw fokus na okno ctop
tmux select-window -t "$SESSION:ctop"
