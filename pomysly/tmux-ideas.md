# Pomysły — tmux

## Przechwycenie `/rename` i synchronizacja z oknem tmux

Gdy użytkownik wywołuje wbudowane `/rename` w Claude Code, automatycznie przemianować też bieżące okno tmux.

### Mechanizm

Jedyna wykonalna opcja to **override przez skill** — skill o nazwie `rename` zastępuje wbudowane `/rename`.
Skill musi:
1. Zapisać `{"type":"custom-title","customTitle":"<nazwa>","sessionId":"<id>"}` do pliku JSONL sesji
   (plik: `~/.claude/projects/<projekt>/<uuid>.jsonl`, pierwsza linia)
2. Wywołać `tmux set-window-option automatic-rename off && tmux rename-window "<nazwa>"`

### Ograniczenia

- Prawdziwy hook na invokację slash-komendy nie istnieje w Claude Code (`PreToolUse`/`PostToolUse` reagują
  tylko na narzędzia, nie na komendy)
- Skill całkowicie zastępuje wbudowane `/rename` — logikę zapisu JSONL trzeba zreplikować samodzielnie
- Wymaga znajomości ID bieżącej sesji w czasie wykonania skilla
