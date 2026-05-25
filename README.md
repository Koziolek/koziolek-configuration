# git-configuration

Osobista konfiguracja środowiska powłoki. Ładowana z `~/.bashrc` przez wskazanie na `main.sh` tego repozytorium.

## Instalacja

```bash
git clone <repo> ~/.koziolek-configuration
```

W `~/.bashrc` dodaj:

```bash
if [ -d $HOME/.koziolek-configuration/ ]; then
    . $HOME/.koziolek-configuration/main.sh
fi
```

Następnie skonfiguruj hooki w repozytorium projektu:

```bash
git i   # odpowiednik: git fun git_init
```

Sekrety (klucze API, hasła) trafiają do `~/.senv` — plik tworzony automatycznie przy pierwszym załadowaniu z uprawnieniami 400. Wzorzec zmiennych: `.senv.template`.

## Architektura

```
main.sh
├── bash/main.sh        → konfiguracja powłoki
├── git/main.sh         → aliasy i funkcje git
└── services/main.sh    → konfiguracje serwisów (Docker, Nginx, Postgres…)
```

`main.sh` eksportuje trzy zmienne środowiskowe: `MAIN_CONFIGURATION_DIR`, `BASH_CONFIGURATION_DIR`, `GIT_CONFIGURATION_DIR`, `SERVICES_CONFIGURATION_DIR`.

## Podsystem bash (`bash/`)

### Funkcje (`functions.d/`)

Każdy plik `[0-9][0-9][0-9]_*.sh` jest ładowany automatycznie w kolejności alfabetycznej przez `source_directory()`.

| Plik | Odpowiedzialność |
|------|-----------------|
| `000_functions_startup.sh` | inicjalizacja, tmux, fullscreen, neofetch |
| `010_function_log.sh` | `log_info`, `log_error`, `log_warn`, `log_man` |
| `015_function_prompt.sh` | PS1, `parse_git_branch` |
| `020_function_process.sh` | helpery procesów |
| `030_function_java.sh` | helpery JVM |
| `040_function_docker.sh` | helpery Docker |
| `085_function_text.sh` | manipulacja tekstem |
| `090_function_image.sh` | operacje na obrazach |
| `095_function_misc.sh` | `install_lib`, `weather`, `generate_month_dirs` |
| `100_get_and_build.sh` | system `get_and_build` (patrz niżej) |
| `110_git-context.sh` | `git_context` (patrz niżej) |
| `120_net_diag.sh` | diagnostyka sieci |

### Kluczowe funkcje

#### `install_lib`

Klonuje repozytorium narzędzia do `$WORKSPACE_TOOLS/<nazwa>` jeśli jeszcze nie istnieje, opcjonalnie sourcuje wskazany plik.

```bash
install_lib -r <repo_url> [-t <katalog>] [-e <plik>] [-x]
# -x  sourcuje plik wskazany przez -e
```

Kolejne wywołania przy istniejącym katalogu są pomijane (fast-path bez parsowania getopts).

#### `resize_to_full`

Przy starcie okna sprawdza, czy terminal jest fullscreen; jeśli nie — wysyła F11. Obsługuje X11 i Wayland (GNOME/Sway). Wynik `xrandr` jest cachowany w `~/.cache/display_max_size_<display>` — usuń plik po zmianie monitora lub rozdzielczości.

#### `get_and_build` / `gab`

System pluginów: `git pull` → wykryj system budowania → zbuduj.

```bash
get_and_build [opcje] [katalog]
  -s, --skip-pull   pomiń git pull
  -d, --dry-run     tylko wykryj system, nie buduj
  -l, --list        wylistuj dostępne pluginy
  -p, --plugin DIR  użyj innego katalogu pluginów
```

Pluginy w `bash/functions.d/gab_plugins/` — każdy definiuje trzy zmienne:

```bash
PLUGIN_NAME="maven"
PLUGIN_DETECT="pom.xml"
PLUGIN_CMD="mvn clean verify"
```

Dostępne pluginy: Maven (`pom.xml`), Gradle (`build.gradle`), Mix (`mix.exs`), npm (`package.json`), Cargo (`Cargo.toml`). Pierwszy pasujący wygrywa (kolejność numeryczna).

#### `git_context`

Interaktywne przełączanie `user.name`/`user.email` git per-repozytorium. Konfiguracja w `~/.config/git-context` (format INI):

```ini
[praca]
name = Jan Kowalski
email = jan@firma.pl

[prywatny]
name = Koziolek
email = koziolek@example.com
```

### Aliasy (`bash_aliases.sh`)

| Alias | Polecenie |
|-------|-----------|
| `g` | `git` (przez hub) |
| `gst` | `git status` |
| `ll` | `ls -al` |
| `la` | `ls -alt` |
| `workspace` | `cd $HOME/workspace` |
| `..` / `cd..` | `cd ..` |
| `in-window` | `xdg-open` |
| `fix-net` | naprawa DNS w kontenerach |
| `pack-repo` / `unpack-repo` | pakowanie repo do base64 |
| `order66` / `omega-protocol` | alias do `exterminatus` |

### Wydajność startu

Konfiguracja stosuje lazy-loading tam, gdzie to możliwe:

- **bash-completion** — ładowana dopiero przy pierwszym naciśnięciu Tab (`complete -D`)
- **dopełnianie `g`** — stub `_git_lazy` ładuje prawdziwe dopełnianie git przy pierwszym użyciu
- **asdf completion** — cachowane w `~/.cache/asdf_bash_completion`, regenerowane tylko gdy plik binarny jest nowszy
- **SDKMAN** — `sdkman-init.sh` sourcowany przed pierwszym promptem przez `_sdkman_init` w `PROMPT_COMMAND`
- **neofetch** — uruchamiany asynchronicznie w tle, wynik wyświetlany przed pierwszym promptem

## Podsystem git (`git/`)

### Aliasy (`git/aliases`)

| Alias | Działanie |
|-------|-----------|
| `g st` | `git status` |
| `g ci` | `git commit` |
| `g co` | `git checkout` |
| `g br` | `git branch` |
| `g df` | `git diff` |
| `g lg` | `git log -p` |
| `g nb` | nowa gałąź feature |
| `g nv` | nowa gałąź version |
| `g nf` | nowa gałąź fix |
| `g ne` | nowa gałąź experimental |
| `g push-upstream` | push z ustawieniem upstream |
| `g slow-merge` | merge bez auto-commit i fast-forward |
| `g lsd` | log z grafem gałęzi |
| `g p` | `pull --prune` |
| `g fuck` | `reset --soft HEAD~` |
| `g exterminatus` | reset repo do stanu origin |
| `g la` | lista wszystkich aliasów |
| `g mrg <branch>` | merge podanej gałęzi do bieżącej |
| `g compress` | `gc --prune=now` |

Aliasy wymagające funkcji powłoki korzystają z wzorca `git fun <nazwa_funkcji>` (zmienna `$GIT_FUNCTIONS`, `SUPPRESS_SOURCING=1`).

### Hooki (`git/hook/`)

`multihooks-template.sh` deleguje hooki do katalogów `<hookname>.d/`, umożliwiając wiele skryptów na jeden typ hooka. Instalacja przez `git i` w katalogu projektu.

### Konfiguracja (`git/git_config`)

Szablon globalnej konfiguracji git — kopiowany do `~/.gitconfig` jeśli plik nie istnieje lub szablon jest nowszy.

## Podsystem serwisów (`services/`)

Funcje do uruchamiania serwisów przez Docker Compose. Dane serwisów w `$WORKSPACE_TOOLS/_data/`:

| Serwis | Katalog danych |
|--------|---------------|
| Nginx | `_data/nginx_data` |
| PostgreSQL | `_data/postgres_data` |
| Nexus | `_data/nexus_data` |

Zmienne środowiskowe: `SERVICES_DATA`, `NGINX_DATA`, `POSTGRES_DATA`, `NEXUS_DATA`, `DOCKER_COMPOSE`.

## Testowanie

```bash
./test.sh
```

Buduje obraz Docker (Ubuntu 24.04, `Dockerfile-test`) i uruchamia kontener. Wyjście zapisywane do `output.log`. Jedyny mechanizm testowania — brak testów jednostkowych.
