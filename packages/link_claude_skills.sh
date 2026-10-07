#!/usr/bin/env bash
# Wspólna funkcja link_claude_skills dla initial_packages_{ubuntu,mac,redhat,vanilla}.sh.
# Sourcowane, nie wykonywane — tylko definicja funkcji.
#
# Podlinkowuje każdy katalog z <klaudyna>/skills/ do ~/.claude/skills/<nazwa>, dzięki
# czemu skille z prywatnego repo `klaudyna` są wspólne dla wszystkich maszyn.
# Wołać PO install_claude i PO sklonowaniu repo (funkcja sama klonuje, gdy brak).
#
# Idempotentne: istniejący symlink jest odświeżany, istniejący prawdziwy katalog/plik
# (np. ~/.claude/skills/synced) zostaje nietknięty. Brak dostępu do repo prywatnego =
# ostrzeżenie i `return 0`, nie błąd (nie przerywa `set -e`).
#
# Zmienne: KLAUDYNA_DIR (domyślnie ~/workspace/tools/klaudyna — to samo miejsce, w które
# klonuje `install_lib` z bash_customs.sh), KLAUDYNA_URL, CLAUDE_SKILLS_DIR.

link_claude_skills() {
    local repo_dir="${KLAUDYNA_DIR:-$HOME/workspace/tools/klaudyna}"
    local repo_url="${KLAUDYNA_URL:-git@github.com:Koziolek/klaudyna.git}"
    local skills_dir="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
    local skill name linked=0

    if [ ! -d "$repo_dir" ]; then
        # Bez promptu o hasło/klucz — świeża maszyna może nie mieć dostępu do repo prywatnego.
        if ! GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" \
                git ls-remote "$repo_url" >/dev/null 2>&1; then
            echo "⚠️  Brak dostępu do $repo_url — pomijam linkowanie skilli Claude Code"
            return 0
        fi
        mkdir -p "$(dirname "$repo_dir")"
        if ! GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" \
                git clone "$repo_url" "$repo_dir"; then
            echo "⚠️  Nie udało się sklonować $repo_url — pomijam linkowanie skilli"
            return 0
        fi
    fi

    if [ ! -d "$repo_dir/skills" ]; then
        echo "⚠️  Brak katalogu $repo_dir/skills — pomijam linkowanie skilli"
        return 0
    fi

    mkdir -p "$skills_dir"
    for skill in "$repo_dir"/skills/*/; do
        [ -d "$skill" ] || continue
        name="$(basename "$skill")"
        if [ -e "$skills_dir/$name" ] && [ ! -L "$skills_dir/$name" ]; then
            echo "⚠️  $skills_dir/$name istnieje i nie jest symlinkiem — zostawiam"
            continue
        fi
        ln -sfn "${skill%/}" "$skills_dir/$name"
        linked=$((linked + 1))
    done

    echo "✓ Skille Claude Code podlinkowane ($linked): $skills_dir"
    return 0
}
