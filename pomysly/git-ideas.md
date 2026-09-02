# plik z commit message

Zmiana vomit i bleeh tak żeby sprawdzały czy istnieje plik commit-message. Plik może być generowany przez AI na etapie
robienia zadania.

---

## Plan implementacji (punkt 2)

Plik: `commit-message.txt` w katalogu roboczym wywołania (CWD, spójnie z `git add .`).
Jest już w `git/ignores` (globalny `core.excludesfile`) → `git add .` go nie zastage'uje.

### Założenia (uzgodnione)

1. Plik nie może być pusty (po odcięciu białych znaków). Pusty i nie podano argumentów w dotychczasowy sposób → błąd,
   przerwanie.
2. Pierwsza linia zawiera prefiks. Jeśli go nie ma — prefiks z brancha
   (`git_commit_message_prefix`) zostaje doklejony do pierwszej linii.
3. Po operacji plik jest czyszczony do zera bajtów (`: > plik`), ale pozostaje na dysku.
4. `git_bleeh`: treść pliku **nadpisuje** historię wiadomości squashowanych commitów
   (brak konkatenacji starych `%s`).
5. Jeśli podano parametry do funkcji → są sklejane z prefiksem i **wstawiane jako pierwsza
   linia pliku**. Dzięki temu plik jest ZAWSZE źródłem wiadomości (jedna ścieżka kodu).
6. Jeśli nie podano parametrów → przed finalnym `git ci` użytkownik dostaje zawartość pliku
   na konsolę i potwierdza `[T/n]` (domyślnie T). Tryb nieinteraktywny: `-y`/`--yes` jako
   pierwszy argument lub `GIT_ASSUME_YES=1` — auto-akceptacja dla skryptów.
   **UWAGA:** `git/main.sh` ustawia `GIT_ASSUME_YES` domyślnie na `1` (patrz sekcja niżej),
   więc podgląd + `[T/n]` jest *opt-in* — użytkownik chcący potwierdzenia ustawia
   `GIT_ASSUME_YES=0` (globalnie w `~/.senv`/`bash_customs` albo per-wywołanie).

### Detekcja prefiksu (założenie 2)

Znane typy z `git_commit_message_prefix`: `feat:`, `fix:`, `ver:`, `exp:`.
Pierwsza linia "ma prefiks" gdy pasuje do `^(feat|fix|ver|exp):`.
Jeśli nie pasuje i prefiks z brancha niepusty → pierwsza linia = `"${prefix} ${pierwsza_linia}"`.
Jeśli prefiks z brancha pusty (branch nietypowany) → linia bez zmian.

### Nowy helper (nie eksportowany)

`__git_prepare_commit_file` w `git/git_functions.sh`:

```
# Argumenty: [-y|--yes] [słowa wiadomości...]
# Wynik (stdout): ścieżka do pliku gotowego do `git ci -F`
# Kod wyjścia !=0 → wołający przerywa (brak commita/pusha)
__git_prepare_commit_file() {
  local file="commit-message.txt"
  local assume_yes=0
  [ "${GIT_ASSUME_YES:-0}" = "1" ] && assume_yes=1
  case "$1" in -y|--yes) assume_yes=1; shift ;; esac

  local msg_words="$*"
  if [ -n "${msg_words// /}" ]; then
    # --- ścieżka z parametrami: wstaw nową pierwszą linię z prefiksem ---
    local line new
    line=$(__git_build_commit_msg "$msg_words")
    new=$(mktemp)
    printf '%s\n' "$line" > "$new"
    [ -f "$file" ] && cat "$file" >> "$new"
    mv "$new" "$file"
  else
    # --- ścieżka bez parametrów ---
    [ -f "$file" ]              || { log_error "Brak $file i brak parametrów"; return 1; }
    [ -n "$(tr -d '[:space:]' < "$file")" ] || { log_error "$file jest pusty"; return 1; }

    # założenie 2: prefiks do pierwszej linii, jeśli brak
    local first prefix
    first=$(head -n1 "$file")
    if ! [[ "$first" =~ ^(feat|fix|ver|exp): ]]; then
      prefix=$(git_commit_message_prefix)
      if [ -n "$prefix" ]; then
        local rest tmp
        rest=$(tail -n +2 "$file")
        tmp=$(mktemp)
        printf '%s %s\n' "$prefix" "$first" > "$tmp"
        [ -n "$rest" ] && printf '%s\n' "$rest" >> "$tmp"
        mv "$tmp" "$file"
      fi
    fi

    # założenie 6: podgląd + potwierdzenie
    if [ "$assume_yes" -ne 1 ]; then
      log_info "Treść commita ($file):"
      log_info "----"
      while IFS= read -r l; do log_info "  $l"; done < "$file"
      log_info "----"
      if [ ! -t 0 ]; then
        log_error "Tryb nieinteraktywny bez -y/--yes ani GIT_ASSUME_YES=1 — przerwano"
        return 1
      fi
      local ans
      read -r -p "Kontynuować? [T/n] " ans
      case "$ans" in n|N|nie|no) log_warn "Przerwano przez użytkownika"; return 1 ;; esac
    fi
  fi

  printf '%s' "$file"
}
```

### Zmiana `git_vomit`

```
function git_vomit() {
  local file
  file=$(__git_prepare_commit_file "$@") || return 1
  git add .
  git ci -a -F "$file"
  : > "$file"                 # założenie 3
  __git_push_branch
}
```

### Zmiana `git_bleeh` (założenie 4)

```
function git_bleeh() {
  local base_branch commit_count file
  base_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
  base_branch="${base_branch:-master}"
  commit_count=$(git log "${base_branch}..HEAD" --oneline 2>/dev/null | wc -l)

  file=$(__git_prepare_commit_file "$@") || return 1
  git add .
  [ "$commit_count" -gt 0 ] && git reset --soft "HEAD~${commit_count}"
  git ci -F "$file"           # treść pliku NADPISUJE historię, brak starych %s
  : > "$file"                 # założenie 3
  __git_push_branch --force-with-lease
}
```

Znika cała gałąź z `old_messages` / `--format=%s --reverse`.

### Zmiana w pliku `git/main.sh`

Dodać obok `export GIT_FUNCTIONS`:

```
export GIT_ASSUME_YES="${GIT_ASSUME_YES:-1}"
```

- Musi być `export` — `git_functions.sh` ładowany jest z `SUPPRESS_SOURCING=1` w podprocesie
  (alias `fun`), samo przypisanie by nie doszło.
- `${GIT_ASSUME_YES:-1}` — domyślnie `1` (auto-akceptacja), ale wartość ustawiona wcześniej
  (np. `GIT_ASSUME_YES=0` w `~/.senv` lub `bash_customs`, albo per-wywołanie) wygrywa.
- Skutek: domyślnie zachowanie jak stary `git_vomit`/`git_bleeh` (bez pytania); podgląd +
  `[T/n]` włącza się przez `GIT_ASSUME_YES=0`.
- W helperze `__git_prepare_commit_file` odczyt bez zmian: `[ "${GIT_ASSUME_YES:-0}" = "1" ]`
  (fallback `0` zostaje na wypadek uruchomienia poza środowiskiem repo, np. w testach).

### Kolejność czyszczenia pliku

Plik czyszczony **po udanym `git ci`**, przed `push`. Jeśli push padnie — commit istnieje
lokalnie, ponowny `git_vomit`/`git_bleeh` bez parametrów trafi na pusty plik → błąd
(świadome: użytkownik robi `git push` ręcznie albo wypełnia plik ponownie).
Alternatywa do rozważenia: czyścić dopiero po udanym push (`git ci ... && git push ... && : > file`).

### Przypadki brzegowe

| Sytuacja                           | Zachowanie                                                                                                  |
|------------------------------------|-------------------------------------------------------------------------------------------------------------|
| brak pliku + brak parametrów       | błąd, przerwanie                                                                                            |
| brak pliku + parametry             | plik tworzony z jedną linią (prefiks + parametry)                                                           |
| pusty plik + brak parametrów       | błąd (założenie 1)                                                                                          |
| pusty plik + parametry             | plik dostaje pierwszą linię, działa                                                                         |
| plik wieloliniowy                  | `git ci -F` zachowa subject + body                                                                          |
| `hub_amen` → `git_vomit "$*"`      | gdy `$*` puste → jak brak parametrów; przy domyślnym `GIT_ASSUME_YES=1` bez pytania                          |
| stdin nie-tty, `GIT_ASSUME_YES=0`  | przerwanie z komunikatem (bezpieczny default dla wymuszonej interaktywności)                                 |
| branch nietypowany (prefiks pusty) | pierwsza linia bez zmian                                                                                    |

### Tryb nieinteraktywny — podsumowanie

- Domyślnie (`GIT_ASSUME_YES=1` z `main.sh`) — brak pytania, zachowanie jak stare funkcje.
- `GIT_ASSUME_YES=0 git vomit` — wymusza podgląd + `[T/n]`.
- `git vomit -y "wiadomość"` — flaga zjadana, reszta = słowa wiadomości (nadpisuje env).
- Przy podanych parametrach potwierdzenie i tak nie jest wymagane (założenie 5).

### Testy do dodania (`test/unit/test_git_functions.sh`)

Użyć realnych plików tymczasowych w katalogu testowym (mock `git` zostaje).
Test sourcuje `git_functions.sh` bezpośrednio (nie `main.sh`) → `GIT_ASSUME_YES` nieustawione
→ fallback `0` → ścieżka interaktywna testowalna bez dodatkowych zabiegów. Dla przypadków
auto-akceptacji ustawić `GIT_ASSUME_YES=1` w danym teście.

1. plik użyty jako źródło wiadomości; po operacji zero bajtów, plik istnieje.
2. pusty plik + brak parametrów → funkcja zwraca !=0, brak `git ci`.
3. brak pliku + brak parametrów → !=0.
4. pierwsza linia bez prefiksu → prefiks z brancha doklejony.
5. pierwsza linia z `feat:` → bez zmian.
6. parametry → wstawione jako pierwsza linia z prefiksem, plik zawsze użyty.
7. `git_bleeh` z plikiem → `_CAPTURED_COMMIT_MSG` == treść pliku (bez starych `%s`).
8. `-y` pomija prompt; `printf 'n\n' |` → przerwanie.
9. `GIT_ASSUME_YES=1` pomija prompt.

### Dokumentacja

- `CLAUDE.md`: dopisać w sekcji podsystemu git akapit o `commit-message.txt` i `GIT_ASSUME_YES`.
- `git/aliases`: bez zmian (aliasy `vomit`/`bleeh` nadal `fun git_vomit`/`fun git_bleeh`).
