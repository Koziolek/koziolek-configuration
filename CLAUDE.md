# CLAUDE.md

Ten plik zawiera wskazówki dla Claude Code (claude.ai/code) dotyczące pracy z tym repozytorium.

## Czym jest to repozytorium

Osobista konfiguracja środowiska powłoki — aliasy bash, funkcje, skróty git, hooki oraz konfiguracje usług (Docker,
Nginx, Postgres itp.). Ładowane z `~/.bashrc` przez wskazanie na `main.sh` tego repozytorium.

Repozytorium nazywa się **`koziolek-configuration`** (`git@github.com:Koziolek/koziolek-configuration.git`);
zmienna `PROJECT_NAME` w skryptach instalacyjnych. Stara nazwa `git-configuration` jest utrzymywana przez
przekierowania GitHuba — nowy kod używa nowej.

Obsługiwane systemy (patrz „Konteksty" niżej): **Ubuntu/Debian**, **macOS**, **Vanilla OS 2** (kontener `apx`),
**WSL**. Elementy swoiste dla systemu są wydzielone do `bash/contexts/<system>.sh`; nie dodawaj rozgałęzień
`if [[ "$(uname -s)" == "Darwin" ]]` w kodzie wspólnym.

## Testowanie

```bash
./test/run.sh              # testy unit + integration (Docker na Linux, wymagane --native na macOS)
./test/run.sh --native     # uruchom bezpośrednio na hoście, bez Dockera (macOS)
./test/run.sh --e2e        # dodatkowo e2e: initial_packages.sh w Ubuntu 24.04 (wolne)
./test/run.sh --e2e-local  # e2e z lokalnym projektem podpiętym jako volume
./test/run.sh --all        # unit + integration + oba e2e
./test/run.sh --filter <wzorzec>  # tylko pliki testowe pasujące do wzorca
```

Runner (`test/run.sh`) sprawdza/przygotowuje środowisko Docker (obrazy, sieć), buduje obrazy testowe z
`test/Dockerfile-unit` i `test/Dockerfile-e2e`, i deleguje do `test/run-inside.sh`, który odpala pliki
`test_*.sh` z `test/unit/`, `test/integration/` (oraz warianty `linux/`/`darwin/` zależnie od `uname -s`)
przez `shunit2`. Wyniki lądują w `test/results/`. Testy e2e (`test/e2e/`) budują obraz z lokalnym
`initial_packages.sh` (`COPY`, nie curl z GitHuba) — testują bieżące, niezacommitowane zmiany.
Uruchamiane też w CI: `.github/workflows/test.yml` (unit+integration na push/PR do `master`).

## Architektura

### Punkt wejścia

`main.sh` eksportuje zmienne katalogów (`MAIN_CONFIGURATION_DIR`, `BASH_CONFIGURATION_DIR`,
`GIT_CONFIGURATION_DIR`, `SERVICES_CONFIGURATION_DIR`, `TMUX_CONFIGURATION_DIR`, `CONTEXTS_DIR`),
sourcuje `bash/contexts/detect.sh` i eksportuje `CONFIG_CONTEXT` (patrz „Konteksty"), po czym
wczytuje cztery podsystemy:

```
main.sh
├── bash/main.sh        → ładuje wszystkie pliki konfiguracyjne bash
├── git/main.sh         → wczytuje aliasy git i funkcje (przez $GIT_FUNCTIONS)
├── services/main.sh    → ładuje konfiguracje usług (docker, nginx, postgres...)
└── tmux/main.sh        → konfiguracja tmux
```

### Podsystem bash (`bash/`)

`bash/main.sh` najpierw wczytuje `bash_functions.sh`, który wywołuje `source_directory()`, aby automatycznie załadować
każdy plik `bash/functions.d/[0-9][0-9][0-9]_*.sh` w kolejności alfabetycznej. Następnie `main.sh` wczytuje nazwane
pliki: `bash_history`, `bash_misc`, `bash_colors`, `bash_aliases`, `bash_exports`, `bash_completion`,
`bash_start_window`, `bash_chat`. Na końcu — **`load_contexts`** (nadpisania per-system), a potem `bash_customs`
(nadpisania per-maszyna).

Odpowiedzialność kluczowych plików funkcji:

- `functions.d/000_*` — uruchomienie/inicjalizacja (`resize_to_full` routuje przez `detect_display_env`)
- `functions.d/010_*` — logowanie (`log_info`, `log_error`, `log_warn`, `log_man`)
- `functions.d/015_*` — prompt PS1
- `functions.d/040_*` — helpery Docker
- `functions.d/100_get_and_build.sh` — funkcja `get_and_build` (patrz niżej)
- `functions.d/110_git-context.sh` — funkcja `git_context`
- `functions.d/130_function_screen.sh` — `detect_display_env()` (gnome/sway/wlroots/x11/wayland; `darwin` z cienia)

Funkcje w `functions.d/` trzymają **wersję Linux** (bez guardów `uname`). Rozbieżności per-system
rozwiązuj tak, by **jak najwięcej zostało wspólne**:

- pośrednictwo zmiennej: funkcja używa `${DOCKER_CLI:-docker}`, a `contexts/vanilla.sh` ustawia
  `DOCKER_CLI=podman` — funkcja się nie rozgałęzia i nie dubluje;
- dopiero gdy się nie da (`/proc`, `swapoff`, `systemd`, `apt`) — `contexts/darwin.sh`
  **redefiniuje** całą funkcję (`reswap`, `who_use_swap`, `turn_async_profiler_*`, `start_x`,
  `netconf_diag`, `refresh_apt_gpg_keys`, `_listening_socket_pairs`, `detect_display_env`);
- co wspólne dla rodziny → wyżej w łańcuchu: instalacja `hub` przez apt jest w `contexts/debian.sh`
  (widzą ją `ubuntu` i `vanilla`), nie w liściach.

### Konteksty (`bash/contexts/`)

`$OS_TYPE` (`uname -s`) rozróżnia tylko Darwin/Linux — za mało dla różnic Ubuntu / Debian /
Vanilla OS / WSL. `bash/contexts/detect.sh` dokłada warstwę:

- **`detect_context()`** → jedno słowo (liść): `darwin` / `ubuntu` / `debian` / `vanilla` / `wsl` / `linux`.
  Źródła: `uname`, `/etc/os-release` (`ID`/`ID_LIKE`), `/proc/version`, `$WSL_DISTRO_NAME`.
  Wynik w `$CONFIG_CONTEXT` (eksport z `main.sh`). Wymuszenie w testach: `CONFIG_CONTEXT_FORCE=…`,
  podmiana pliku: `OS_RELEASE_FILE=…`.
- **`context_chain()`** rozwija liść w łańcuch ogólny→szczegółowy: `vanilla → linux debian vanilla`,
  `ubuntu → linux debian ubuntu`, `wsl → linux debian wsl` (WSL jest w praktyce zawsze
  Ubuntu/Debian pod spodem — dziedziczy apt/hub z `debian.sh`), `darwin → darwin`.
- **`load_contexts()`** (z `bash/main.sh`, po wspólnej konfiguracji, przed `bash_customs`) sourcuje
  `contexts/<c>.sh` dla każdego ogniwa — plik szczegółowy nadpisuje ogólniejszy.
- **`context_is <name>`** — czy `<name>` jest w łańcuchu (`context_is debian` jest prawdą i dla
  `ubuntu`, i dla `vanilla`).

Pliki `contexts/{linux,debian,ubuntu,vanilla,wsl,darwin}.sh` trzymają **tylko** nadpisania swojej
warstwy (aliasy, `export`, redefinicje funkcji). Wspólne rzeczy zostają w `bash_*.sh` / `functions.d/`.
Stan: `linux` (aliasy), `debian` (hub/apt), `vanilla` (`DOCKER_CLI`/`DOCKER_COMPOSE`/`fix-net`),
`wsl` (`in-window`→`wslview`), `darwin` (Homebrew, hub/brew, redefinicje funkcji); `ubuntu` pusty.
Testy: `test/unit/test_context_detect.sh`, `test/unit/linux/test_{vanilla_aliases,vanilla_context,debian_context,wsl_context}.sh`.

### System pluginów `get_and_build` (gab)

`get_and_build` wykonuje: git pull → wykryj system budowania → zbuduj. Wykrywanie oparte jest na pluginach: każdy plik w
`bash/functions.d/gab_plugins/` definiuje `PLUGIN_NAME`, `PLUGIN_DETECT` (plik do wykrycia) i `PLUGIN_CMD`. Pluginy
ładowane są alfabetycznie; wygrywa pierwsze dopasowanie.

Aktualne pluginy: `10-maven.sh`, `20-gradle.sh`, `30-mix.sh`, `40-npm.sh`, `50-cargo.sh`.

Aby dodać nowy system budowania, wrzuć numerowany plik `.sh` do `gab_plugins/` z tymi trzema zmiennymi.

### Podsystem git (`git/`)

- `git/aliases` — aliasy git (dołączane przez `[include]` w `git_config.template`)
- `git/templates/git_config.template` — szablon globalnej konfiguracji git. Renderowany do
  `~/.gitconfig.generated` (swobodnie nadpisywany); `~/.gitconfig` to stały stub z `[include]`
  wskazującym na ten plik, tworzony tylko raz — ręczne `git config --global ...` przeżywają
  aktualizacje repo. Migracja ze starego (jednoplikowego) modelu: `git/migrate_gitconfig.sh`.
- `git/git_functions.sh` — funkcje wywoływane przez aliasy wzorcem `git fun <nazwa_funkcji>` (wczytywane z
  `SUPPRESS_SOURCING=1`, aby uniknąć ponownego ładowania konfiguracji bash)
- `git/hub_functions.sh` — funkcje integracji z GitHub/hub
- `git/hook/` — wielokrotnego użytku skrypty hooków; `multihooks-template.sh` deleguje do katalogów `<hookname>.d/`;
  `git i` (funkcja `git_init` w `git/git_functions.sh`) instaluje infrastrukturę multi-hook

### Funkcje `git_vomit` / `git_bleeh` i `commit-message.txt`

`git vomit` / `git bleeh` biorą treść commita z pliku `commit-message.txt` w katalogu roboczym
(jest w `git/ignores`). Z parametrami: `git vomit "tekst"` wstawia `<prefiks-brancha> tekst`
jako pierwszą linię pliku i commituje. Bez parametrów: używa istniejącej treści pliku (pusty →
błąd), dokleja prefiks do pierwszej linii jeśli go brak. Po udanym `git ci` plik jest czyszczony
do zera bajtów. `git_bleeh` robi dodatkowo `reset --soft` do bazy i nadpisuje historię wiadomości
treścią pliku. Potwierdzenie `[T/n]` (ścieżka bez parametrów) jest domyślnie wyłączone —
`git/main.sh` ustawia `GIT_ASSUME_YES=1`; ustaw `GIT_ASSUME_YES=0` (np. w `~/.senv`) aby wymusić
podgląd, lub użyj `git vomit -y` do jednorazowej auto-akceptacji.

### Funkcja `git_context`

Interaktywne narzędzie do przełączania `user.name`/`user.email` git per-repozytorium, sterowane plikiem
`~/.config/git-context` (format INI z sekcjami `[nazwa_kontekstu]`, kluczami `name =`, `email =`).

### Sekrety

Wrażliwe zmienne środowiskowe trafiają do `~/.senv` (tworzony automatycznie przy pierwszym załadowaniu, tryb 400). Nigdy
nie commituj tu danych uwierzytelniających. Plik `.senv.template` pokazuje oczekiwane zmienne.

## Bootstrap pakietów (per system)

Instalacja i aktualizacja narzędzi — osobny skrypt na system. Wspólne listy pakietów:
`packages/apt_packages.sh` (Debian/Ubuntu/Vanilla), `packages/brew_packages.sh` (macOS).

| System | Instalacja | Aktualizacja | Menedżer |
|---|---|---|---|
| Ubuntu / Debian | `initial_packages.sh` | `update_packages.sh` | apt + Docker |
| macOS | `initial_packages_mac.sh` | `update_packages_mac.sh` | Homebrew |
| Vanilla OS 2 | `initial_packages_vanilla.sh` | `update_packages_vanilla.sh` | apt (subsystem `apx`) + podman |

Wariant Vanilla: uruchamiany **wewnątrz subsystemu** (`vso shell` / `apx enter`), reużywa
`apt_packages.sh`, używa `podman` + `podman-compose` zamiast Dockera, pomija
`add-apt-repository universe` (baza = Debian sid), po `git clone` woła `git/migrate_gitconfig.sh`,
`update_packages_vanilla.sh` sprząta martwe źródła apt (`docker.list`).

difftastic instaluje się przez `cargo install --locked difftastic` (wszędzie: install + update,
linux/vanilla/mac). Bez `--locked` cargo dobiera najnowsze zależności semver, które co jakiś czas
podbijają wymóg `rustc` ponad to, co daje asdf → `rustc X is not supported by the following packages`.

## Konwencje

- Nowe funkcje bash trafiają do `bash/functions.d/` z trzycyfrowym prefiksem numerycznym (określa kolejność ładowania).
- **Różnice per-system nie idą przez `if [[ "$(uname -s)" == "Darwin" ]]`** — trafiają do `bash/contexts/<system>.sh`
  (alias/`export`) lub jako redefinicja funkcji cieniująca wersję z `functions.d/`. Wykrywanie: `context_is <name>`.
- Funkcje przeznaczone wyłącznie dla aliasów git trafiają do `git/git_functions.sh` — nie eksportuj ich do normalnej
  powłoki.
- Zmienna `$SUPPRESS_SOURCING=1` zapobiega rekurencyjnemu ładowaniu konfiguracji bash, gdy aliasy git wywołują funkcje
  powłoki.
- Zmienne kolorów (`$C_GREEN`, `$C_RED` itp.) zdefiniowane są w `bash_colors.sh` — używaj ich do wyjścia, nie surowych
  sekwencji escape.
- Loguj przez `log_info`/`log_error`/`log_warn`/`log_man`, a nie przez `echo`.
- Nowe zachowania kryj testami `shunit2` w `test/unit/` lub `test/integration/` (warianty `linux/`, `darwin/`).
