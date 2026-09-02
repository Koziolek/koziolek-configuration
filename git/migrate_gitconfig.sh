#!/usr/bin/env bash
# Migracja ~/.gitconfig ze starego modelu (pełna regeneracja jednego pliku z
# szablonu przy każdym starcie powłoki) na nowy model include (patrz B6 w
# code-review/CR.md): $HOME/.gitconfig to stały "stub" z [include], właściwa
# treść z repo ląduje w $HOME/.gitconfig.generated, który wolno swobodnie
# nadpisywać. Dzięki temu ręczne `git config --global ...` użytkownika
# przeżywają aktualizacje repo.
#
# Bezpieczna do wielokrotnego uruchomienia:
#   - jeśli stub już istnieje i wskazuje na .gitconfig.generated — nic nie robi,
#   - jeśli ~/.gitconfig nie istniał wcześniej — po prostu go tworzy,
#   - jeśli ~/.gitconfig istniał w starym formacie — robi kopię zapasową,
#     wykrywa klucze różniące się od świeżo wyrenderowanego szablonu (czyli
#     ręczne dopiski/zmiany użytkownika) i przenosi je do nowego stuba przez
#     `git config --file`, więc trafiają do poprawnych sekcji, nie jako
#     surowy tekst wklejony na oślep.
#
# Użycie:
#   bash git/migrate_gitconfig.sh

set -euo pipefail

GIT_CONFIGURATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$GIT_CONFIGURATION_DIR/templates/git_config.template"
GENERATED="$HOME/.gitconfig.generated"
STUB="$HOME/.gitconfig"

if [ ! -f "$TEMPLATE" ]; then
    echo "Błąd: brak szablonu $TEMPLATE" >&2
    exit 1
fi

if [ -f "$STUB" ] && grep -qF "path = $GENERATED" "$STUB"; then
    echo "✓ $STUB już używa nowego modelu (include -> $GENERATED). Nic do zrobienia."
    exit 0
fi

echo "Migracja $STUB na model include..."

# 1. Wyrenderuj świeżą wersję zarządzaną przez repo (ta sama logika co git/main.sh).
envsubst '$GIT_CONFIGURATION_DIR' < "$TEMPLATE" > "$GENERATED"
echo "✓ Wygenerowano $GENERATED"

if [ ! -f "$STUB" ]; then
    printf '[include]\n\tpath = %s\n' "$GENERATED" > "$STUB"
    echo "✓ Utworzono nowy $STUB (plik nie istniał wcześniej)"
    exit 0
fi

# 2. Zabezpiecz oryginał, zanim cokolwiek ruszymy.
backup="$STUB.pre-migration-$(date +%Y%m%d%H%M%S)"
cp "$STUB" "$backup"
echo "✓ Kopia zapasowa starego pliku: $backup"

# 3. Znajdź klucze z oryginału, których wartość różni się od świeżo
#    wyrenderowanego szablonu — to ręczne zmiany/dopiski użytkownika warte
#    zachowania. Porównanie przez `git config -l --file` (nie surowy tekst),
#    żeby nie zależeć od formatowania/wcięć i poprawnie obsłużyć sekcje.
old_pairs=$(git config --includes -l --file "$backup" 2>/dev/null | sort -u || true)
new_pairs=$(git config --includes -l --file "$GENERATED" 2>/dev/null | sort -u || true)
extra_pairs=$(comm -23 <(echo "$old_pairs") <(echo "$new_pairs") || true)

printf '[include]\n\tpath = %s\n' "$GENERATED" > "$STUB"
echo "✓ Nowy $STUB zapisany (tylko [include])"

if [ -z "$extra_pairs" ]; then
    echo "  Brak ręcznych zmian względem szablonu — stary plik był z nim identyczny."
    exit 0
fi

echo "⚠️ Wykryto ustawienia różniące się od szablonu repo — przenoszę do $STUB:"
preserved=0
while IFS='=' read -r key value; do
    [[ -z "$key" ]] && continue
    echo "  - $key = $value"
    git config --file "$STUB" "$key" "$value"
    (( preserved++ )) || true
done <<<"$extra_pairs"

echo "✓ Przeniesiono $preserved ustawień do $STUB (jako bezpośrednie override nad include)."
echo "  Oryginał zachowany w: $backup"
