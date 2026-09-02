# koziolek-configuration

Osobista konfiguracja środowiska powłoki. Ładowana z `~/.bashrc` przez wskazanie na `main.sh` tego repozytorium.
Obsługuje Ubuntu/Debian, macOS, Vanilla OS 2 i WSL — różnice per-system w `bash/contexts/` (patrz niżej).

(Stara nazwa repo: `git-configuration` — działa przez przekierowania GitHuba.)

## Instalacja

```bash
git clone git@github.com:Koziolek/koziolek-configuration.git ~/.koziolek-configuration
```

W `~/.bashrc` dodaj:

```bash
if [ -d $HOME/.koziolek-configuration/ ]; then
  . $HOME/.koziolek-configuration/main.sh
fi
```

Następnie skonfiguruj hooki w repozytorium projektu:

```bash
git i # odpowiednik: git fun git_init
```

Sekrety (klucze API, hasła) trafiają do `~/.senv` — plik tworzony automatycznie przy pierwszym załadowaniu z
uprawnieniami 400. Wzorzec zmiennych: `.senv.template`.

### Bootstrap pakietów (per system)

Instalacja narzędzi i aktualizacje mają osobny skrypt na każdy system. Wspólne listy pakietów:
`packages/apt_packages.sh` (Debian/Ubuntu/Vanilla) i `packages/brew_packages.sh` (macOS).

| System | Instalacja | Aktualizacja | Menedżer |
|---|---|---|---|
| Ubuntu / Debian | `initial_packages.sh` | `update_packages.sh` | apt + Docker |
| macOS | `initial_packages_mac.sh` | `update_packages_mac.sh` | Homebrew |
| **Vanilla OS 2** | **`initial_packages_vanilla.sh`** | **`update_packages_vanilla.sh`** | apt (w subsystemie `apx`) + podman |

Wersja Vanilla musi lecieć **wewnątrz subsystemu** (`vso shell` / `apx enter`) — host jest immutable.
Używa `podman` + `podman-compose` zamiast Dockera, pomija `add-apt-repository universe` (baza to Debian
sid) i po `git clone` uruchamia `git/migrate_gitconfig.sh`.

`install_rust_and_difft` / `update_difft` instalują difftastic przez **`cargo install --locked difftastic`**.
Bez `--locked` cargo dobiera najnowsze zależności semver (`tree-sitter-language`), a te wymuszają nowszego
`rustc` niż daje asdf → `rustc X is not supported by the following packages`.

## Architektura

```
main.sh
├── bash/contexts/detect.sh → wykrycie kontekstu (przed podsystemami)
├── bash/main.sh        → konfiguracja powłoki (+ load_contexts na końcu)
├── git/main.sh         → aliasy i funkcje git
├── services/main.sh    → konfiguracje serwisów (Docker, Nginx, Postgres…)
└── tmux/main.sh        → konfiguracja tmux
```

`main.sh` eksportuje zmienne środowiskowe: `MAIN_CONFIGURATION_DIR`, `BASH_CONFIGURATION_DIR`,
`GIT_CONFIGURATION_DIR`, `SERVICES_CONFIGURATION_DIR`, `TMUX_CONFIGURATION_DIR`, `CONTEXTS_DIR`
oraz `CONFIG_CONTEXT` (patrz niżej).

## Konteksty (`bash/contexts/`)

`$OS_TYPE` (uname -s) rozróżnia tylko Darwin/Linux — za mało dla różnic między Ubuntu,
Debianem, Vanilla OS i WSL. `bash/contexts/detect.sh` dokłada warstwę:

- **`detect_context()`** → jedno słowo: `darwin` / `ubuntu` / `debian` / `vanilla` / `wsl` / `linux`
  (na podstawie `uname`, `/etc/os-release` `ID`/`ID_LIKE`, `/proc/version`, `$WSL_DISTRO_NAME`).
  Wynik eksportowany z `main.sh` jako **`$CONFIG_CONTEXT`**. Wymuszenie: `CONFIG_CONTEXT_FORCE=…`.
- **`context_chain()`** rozwija liść w łańcuch ogólny → szczegółowy:
  `vanilla → linux debian vanilla`, `ubuntu → linux debian ubuntu`,
  `wsl → linux debian wsl`, `darwin → darwin`, …
- **`load_contexts()`** (wołane z `bash/main.sh`, po wspólnej konfiguracji, przed `bash_customs`)
  sourcuje `contexts/<c>.sh` dla każdego ogniwa — plik szczegółowy nadpisuje ogólniejszy.
- **`context_is <name>`** — czy `<name>` jest w łańcuchu (`context_is debian` jest prawdą
  dla `ubuntu`, `vanilla` i `wsl`).

Pliki `contexts/{linux,debian,ubuntu,vanilla,wsl,darwin}.sh` trzymają **tylko** nadpisania
swojej warstwy; wspólne rzeczy zostają w `bash_aliases.sh` / `bash_exports.sh` / funkcjach.
Co gdzie mieszka:

| Warstwa | Zawartość |
|---|---|
| `linux`   | aliasy `cozy`/`iotop`/`in-window`/`alert`/`fd`/`time`, `ls --color`/dircolors, `lesspipe` |
| `debian`  | instalacja `hub` przez apt (wspólne dla `ubuntu`, `vanilla`, `wsl`) |
| `ubuntu`  | — (Ubuntu = `linux` + `debian`) |
| `vanilla` | `DOCKER_CLI="podman"`, `DOCKER_COMPOSE="podman-compose"` + `DOCKER_HOST` (socket podmana), alias `fix-net` (montaż `resolv.conf` hosta) |
| `wsl`     | `in-window` → `wslview`/`explorer.exe`, aliasy `clip`/`paste` (mostki `.exe`); dziedziczy apt/`hub` z `debian` |
| `darwin`  | Homebrew (`HOMEBREW_*` + PATH), `DOCKER_COMPOSE="docker compose"`, instalacja `hub` przez brew, aliasy `in-window=open`/`alert=osascript`/`ls -G`/`time=gtime`; **redefinicja funkcji** `reswap`/`who_use_swap`/`turn_async_profiler_{on,off}`/`start_x`/`netconf_diag`/`refresh_apt_gpg_keys`/`_listening_socket_pairs` (`lsof`) / `detect_display_env` (`→ darwin`) |

Zasady:

- **Maksymalizuj wspólne.** Co dzielone przez kilka liści → wyżej w łańcuchu (`debian`, `linux`),
  nie kopiowane. Funkcje zostają w `functions.d/` z pośrednictwem zmiennej
  (np. `${DOCKER_CLI:-docker}`), a nie duplikowane per-kontekst.
- Funkcje w `functions.d/` trzymają **wersję Linux** (bez guardów `if [[ "$(uname -s)" == "Darwin" ]]`).
  `contexts/darwin.sh` ładuje się po `functions.d/`, więc jego redefinicje wygrywają.
- `bash_exports.sh` nie woła `log_error` przy braku Dockera — `DOCKER_CLI` (`docker`›`podman`) i
  `DOCKER_COMPOSE` (`docker compose`›`podman-compose`›`docker-compose`›pusty) ustala probe, kontekst nadpisuje.
- Rozgałęzienia po `$DISPLAY` są zdradliwe pod Wayland (Xwayland ustawia `$DISPLAY=:0`) — używaj
  `detect_display_env()` z `functions.d/130_function_screen.sh` (wersja Linux; `darwin` daje cień).
- W `functions.d/` nie ma już żadnego `if [[ "$(uname -s)" == "Darwin" ]]`. Jedyne `uname` to
  `detect_context` (detektor) i `update_asdf` (wyliczenie URL-a — musi działać wszędzie).

## Podsystem bash (`bash/`)

### Funkcje (`functions.d/`)

Każdy plik `[0-9][0-9][0-9]_*.sh` jest ładowany automatycznie w kolejności alfabetycznej przez `source_directory()`.

| Plik                       | Odpowiedzialność                                |
|----------------------------|-------------------------------------------------|
| `000_functions_startup.sh` | inicjalizacja, tmux, fullscreen, neofetch       |
| `010_function_log.sh`      | `log_info`, `log_error`, `log_warn`, `log_man`  |
| `015_function_prompt.sh`   | PS1, `parse_git_branch`                         |
| `020_function_process.sh`  | helpery procesów                                |
| `030_function_java.sh`     | helpery JVM                                     |
| `040_function_docker.sh`   | helpery Docker                                  |
| `085_function_text.sh`     | manipulacja tekstem                             |
| `090_function_image.sh`    | operacje na obrazach                            |
| `095_function_misc.sh`     | `install_lib`, `weather`, `generate_month_dirs`, `start_x` |
| `096_apt_gpg.sh`           | odświeżanie kluczy GPG repozytoriów apt         |
| `100_get_and_build.sh`     | system `get_and_build` (patrz niżej)            |
| `110_git-context.sh`       | `git_context` (patrz niżej)                     |
| `120_net_diag.sh`          | `netconf_diag` — diagnostyka zrywania sieci     |
| `130_function_screen.sh`   | `detect_display_env` (patrz `resize_to_full`)   |

Funkcje w `functions.d/` są w wersji Linux; `bash/contexts/darwin.sh` redefiniuje te zależne
od `/proc`, `ss`, `swapoff`, `systemd`, `ip`/`iw`, `apt` oraz `detect_display_env` (patrz „Konteksty").

### Kluczowe funkcje

#### `install_lib`

Klonuje repozytorium narzędzia do `$WORKSPACE_TOOLS/<nazwa>` jeśli jeszcze nie istnieje, opcjonalnie sourcuje wskazany
plik.

```bash
install_lib -r <repo_url >[-t <katalog >] [-e <plik >] [-x]
# -x  sourcuje plik wskazany przez -e
```

Kolejne wywołania przy istniejącym katalogu są pomijane (fast-path bez parsowania getopts).

#### `resize_to_full`

Przy starcie okna sprawdza, czy terminal jest fullscreen; jeśli nie — próbuje przełączyć. Środowisko rozpoznaje
`detect_display_env()` (`130_function_screen.sh`): `gnome` → `gdbus` Eval, `sway` → `swaymsg`, `x11` → `xdotool` F11,
`wayland`/`wlroots`/`darwin`/`""` → no-op. Detekcja sprawdza `WAYLAND_DISPLAY`/`XDG_SESSION_TYPE` **przed** `$DISPLAY`
(który pod Wayland ustawia Xwayland). Na macOS wynik `darwin` daje cień z `contexts/darwin.sh`.

**Multi-monitor / X11.** Zależny od monitorów jest **tylko** wariant `x11` (`xrandr` + cache
`~/.cache/display_max_size_<display>`, gdzie `<display>` = `$DISPLAY`). Cache trzyma listę aktywnych trybów
wszystkich podłączonych wyjść i wygasa po 60 min. Po podpięciu/odpięciu monitora o innej natywnej rozdzielczości
przez ≤ 1 h `resize_to_full` może błędnie wcisnąć F11 (lub go pominąć) — natychmiastowy fix:
`rm ~/.cache/display_max_size_*`. Warianty `gnome`/`sway`/`wayland` są monitoro-agnostyczne — działają na oknie
z fokusem niezależnie od liczby ekranów. Na GNOME 46+ (Vanilla OS 2) `Shell.Eval` jest domyślnie zablokowany, więc
gałąź `gnome` to praktycznie no-op. Sam układ ekranów obsługuje kompozytor/Mutter, nie ta konfiguracja.

#### `get_and_build` / `gab`

System pluginów: `git pull` → wykryj system budowania → zbuduj.

```bash
get_and_build [opcje] [katalog]
-s, --skip-pull pomiń git pull
-d, --dry-run tylko wykryj system, nie buduj
-l, --list wylistuj dostępne pluginy
-p, --plugin DIR użyj innego katalogu pluginów
```

Pluginy w `bash/functions.d/gab_plugins/` — każdy definiuje trzy zmienne:

```bash
PLUGIN_NAME="maven"
PLUGIN_DETECT="pom.xml"
PLUGIN_CMD="mvn clean verify"
```

Dostępne pluginy: Maven (`pom.xml`), Gradle (`build.gradle`), Mix (`mix.exs`), npm (`package.json`), Cargo (
`Cargo.toml`). Pierwszy pasujący wygrywa (kolejność numeryczna).

#### `git_context`

Interaktywne przełączanie `user.name`/`user.email` git per-repozytorium. Konfiguracja w `~/.config/git-context` (format
INI):

```ini
[praca]
name = Jan Kowalski
email = jan@firma.pl

[prywatny]
name = Koziolek
email = koziolek@example.com
```

### Aliasy (`bash_aliases.sh` + `bash/contexts/`)

Wspólne — `bash_aliases.sh`:

| Alias                        | Polecenie                |
|------------------------------|--------------------------|
| `g` / `gst`                  | `git` (przez hub) / `git status` |
| `ll` / `la`                  | `ls -al` / `ls -alt`     |
| `workspace`                  | `cd $HOME/workspace`     |
| `..` / `cd..`                | `cd ..`                  |
| `pack-repo` / `unpack-repo`  | pakowanie repo do base64 |
| `order66` / `omega-protocol` | alias do `exterminatus`  |

Per-kontekst — `bash/contexts/*.sh` (patrz „Konteksty"):

| Alias        | `linux`   | `darwin`   | `vanilla` | `wsl` |
|--------------|-----------|------------|-----------|-------|
| `in-window`  | `xdg-open` | `open`    | (linux)   | `wslview` / `explorer.exe` |
| `alert`      | `notify-send` | `osascript` | (linux) | (linux) |
| `fix-net`    | —         | —          | montaż `resolv.conf` hosta | — |
| `cozy`/`iotop`/`fd` | ✓  | —          | (linux)   | (linux) |
| `clip`/`paste` | —       | —          | —         | mostki `.exe` |

„(linux)" = dziedziczone z `contexts/linux.sh` przez łańcuch.

### Wydajność startu

Konfiguracja stosuje lazy-loading tam, gdzie to możliwe:

- **bash-completion** — ładowana dopiero przy pierwszym naciśnięciu Tab (`complete -D`)
- **dopełnianie `g`** — stub `_git_lazy` ładuje prawdziwe dopełnianie git przy pierwszym użyciu
- **asdf completion** — cachowane w `~/.cache/asdf_bash_completion`, regenerowane tylko gdy plik binarny jest nowszy
- **SDKMAN** — `sdkman-init.sh` sourcowany przed pierwszym promptem przez `_sdkman_init` w `PROMPT_COMMAND`
- **neofetch** — uruchamiany asynchronicznie w tle, wynik wyświetlany przed pierwszym promptem

## Podsystem git (`git/`)

### Aliasy (`git/aliases`)

| Alias             | Działanie                            |
|-------------------|--------------------------------------|
| `g st`            | `git status`                         |
| `g ci`            | `git commit`                         |
| `g co`            | `git checkout`                       |
| `g br`            | `git branch`                         |
| `g df`            | `git diff`                           |
| `g lg`            | `git log -p`                         |
| `g nb`            | nowa gałąź feature                   |
| `g nv`            | nowa gałąź version                   |
| `g nf`            | nowa gałąź fix                       |
| `g ne`            | nowa gałąź experimental              |
| `g push-upstream` | push z ustawieniem upstream          |
| `g slow-merge`    | merge bez auto-commit i fast-forward |
| `g lsd`           | log z grafem gałęzi                  |
| `g p`             | `pull --prune`                       |
| `g fuck`          | `reset --soft HEAD~`                 |
| `g exterminatus`  | reset repo do stanu origin           |
| `g la`            | lista wszystkich aliasów             |
| `g mrg <branch>`  | merge podanej gałęzi do bieżącej     |
| `g compress`      | `gc --prune=now`                     |

Aliasy wymagające funkcji powłoki korzystają z wzorca `git fun <nazwa_funkcji>` (zmienna `$GIT_FUNCTIONS`,
`SUPPRESS_SOURCING=1`).

### Hooki (`git/hook/`)

`multihooks-template.sh` deleguje hooki do katalogów `<hookname>.d/`, umożliwiając wiele skryptów na jeden typ hooka.
Instalacja przez `git i` w katalogu projektu.

### Konfiguracja (`git/templates/git_config.template`)

Szablon globalnej konfiguracji git. Model include: szablon jest renderowany do `~/.gitconfig.generated`
(nadpisywany swobodnie, gdy szablon jest nowszy — nigdy nie edytuj go ręcznie), a `~/.gitconfig` to
stały "stub" z jednym wpisem `[include] path = ~/.gitconfig.generated`, tworzony tylko raz. Dzięki temu
ręczne `git config --global ...` lądują w stubie i przeżywają aktualizacje repo, zamiast być cicho
nadpisywane. Maszyny ze starym modelem (jeden w pełni generowany plik) migrują przez
`bash git/migrate_gitconfig.sh` — bezpieczne do wielokrotnego uruchomienia, robi kopię zapasową
i przenosi ręczne zmiany do nowego stuba.

## Podsystem serwisów (`services/`)

Funcje do uruchamiania serwisów przez Docker Compose. Dane serwisów w `$WORKSPACE_TOOLS/_data/`:

| Serwis     | Katalog danych        |
|------------|-----------------------|
| Nginx      | `_data/nginx_data`    |
| PostgreSQL | `_data/postgres_data` |
| Nexus      | `_data/nexus_data`    |

Zmienne środowiskowe: `SERVICES_DATA`, `NGINX_DATA`, `POSTGRES_DATA`, `NEXUS_DATA`, `DOCKER_CLI`, `DOCKER_COMPOSE`
(dwie ostatnie ustala `bash_exports.sh` / kontekst — patrz „Konteksty").

## Diagnostyka systemu

Diagnostykę sprzętu, logów i stanu systemu należy prowadzić przez dedykowany projekt **FIX**:

```bash
git clone git@github.com:Koziolek/fix-comp.git
```

Projekt zawiera skrypty diagnostyczne, raporty i narzędzia do analizy stanu stacji roboczej. Funkcja `120_net_diag.sh` w tej konfiguracji odpowiada wyłącznie za podstawową diagnostykę sieci w powłoce.

## Testowanie

```bash
./test/run.sh              # testy unit + integration (Docker na Linux)
./test/run.sh --native     # bezpośrednio na hoście, bez Dockera (wymagane na macOS)
./test/run.sh --e2e        # dodatkowo e2e: initial_packages.sh w Ubuntu 24.04
./test/run.sh --all        # wszystko
```

Testy jednostkowe/integracyjne (`shunit2`) w `test/unit/` i `test/integration/`, e2e w `test/e2e/`.
Warianty per-OS w podkatalogach `linux/` i `darwin/` (uruchamiane zależnie od `uname -s`). Konteksty:
mechanizm — `test/unit/test_context_detect.sh`; warstwy — `test/unit/linux/test_{debian,vanilla,wsl}_context.sh`,
`test_{vanilla,linux}_aliases.sh`, `test_resize_to_full.sh`; macOS — `test/unit/darwin/test_darwin_{screen,process_guards,aliases}.sh`.
Wyniki w `test/results/`. CI: `.github/workflows/test.yml`.
