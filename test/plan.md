# Plan testów — git-configuration

## Założenia

### Środowisko wykonania

Wszystkie testy uruchamiane są wewnątrz kontenera Docker, żeby nie naruszać środowiska hosta. Kontener dostaje projekt
zamontowany jako read-only volume; wyniki zapisywane są do osobnego wolumenu (`test/results/`), który jest odczytywany
przez hosta po zakończeniu kontenera.

```
host
├── docker run --rm \
│     -v $(pwd):/project:ro \
│     -v $(pwd)/test/results:/results \
│     test-koziolek-unit
└── cat test/results/results.log
```

Komunikacja kontener ↔ host:

- **pliki** — wyniki testów i logi trafiają do `/results/` (volume)
- **exit code** — `docker run` zwraca kod wyjścia procesu testów; runner sprawdza `$?`
- **logi kontenera** — `docker logs` jako fallback gdy volume jest niedostępny

### Frameworki i narzędzia

- **shunit2** — `$WORKSPACE_TOOLS/shunit2/shunit2.sh` (zainstalowany przez `install_lib`)
- **bats-core** — opcjonalnie do testów integracyjnych (prostszy składniowo)
- **Docker** — izolacja środowiska

### Podział testów

| Kategoria                     | Co testuje                                            | Kontener                                   |
|-------------------------------|-------------------------------------------------------|--------------------------------------------|
| Jednostkowe (`unit/`)         | Izolowane funkcje bash, bez zależności systemowych    | lekki (bash + git + shunit2)               |
| Integracyjne (`integration/`) | Ładowanie pełnej konfiguracji, współpraca podsystemów | ubuntu:24.04 z zainstalowanymi narzędziami |
| E2E (`e2e/`)                  | Pełna instalacja przez `initial_packages.sh`          | ubuntu:24.04 czyste                        |

---

## Struktura katalogów

```
test/
├── plan.md                        ← ten plik
├── run.sh                         ← główny runner (buduje obraz, uruchamia, zbiera wyniki)
├── Dockerfile-unit                ← lekki obraz dla testów jednostkowych
├── fixtures/
│   ├── fake_git_repo/             ← fake repo z różnymi plikami build (pom.xml, build.gradle…)
│   ├── fake_workspace_tools/      ← mock $WORKSPACE_TOOLS z fake katalogami
│   └── git_context_config         ← przykładowy ~/.config/git-context
├── unit/
│   ├── test_log_functions.sh
│   ├── test_install_lib.sh
│   ├── test_get_and_build.sh
│   ├── test_git_context.sh
│   ├── test_misc_functions.sh
│   └── test_source_helpers.sh
├── integration/
│   ├── test_bash_loads.sh
│   ├── test_exports.sh
│   ├── test_completion_stubs.sh
│   └── test_git_aliases.sh
├── e2e/
│   └── test_initial_packages.sh
└── results/                       ← generowany; wyniki testów (gitignore)
```

---

## Testy jednostkowe (`unit/`)

Każdy plik sourcuje tylko testowaną funkcję + shunit2, bez ładowania całej konfiguracji bash.
`WORKSPACE_TOOLS` i podobne zmienne ustawiane są ręcznie w `oneTimeSetUp()`.

---

### `test_log_functions.sh`

Sourcuje: `bash/functions.d/010_function_log.sh`

| Test                       | Sprawdza                                                   |
|----------------------------|------------------------------------------------------------|
| `testLogInfoOutputFormat`  | wyjście `log_info` zawiera tag `[INFO]` i przekazany tekst |
| `testLogErrorOutputFormat` | wyjście `log_error` zawiera tag `[ERROR]`                  |
| `testLogWarnOutputFormat`  | wyjście `log_warn` zawiera tag `[WARN]`                    |
| `testLogManOutputFormat`   | wyjście `log_man` zawiera tag `[MAN]` lub `[USAGE]`        |
| `testLogErrorExitCode`     | `log_error` nie wychodzi z kodem niezerowym samodzielnie   |

Technika: przekierowanie stderr/stdout do zmiennej przez `$( )`, `assertContains`.

---

### `test_install_lib.sh`

Sourcuje: `bash/functions.d/010_function_log.sh`, `bash/functions.d/095_function_misc.sh`  
Fixture: `fixtures/fake_workspace_tools/` z katalogami `shunit2/`, `BashMan/` (symulują zainstalowane biblioteki)

| Test                                  | Sprawdza                                                |
|---------------------------------------|---------------------------------------------------------|
| `testFastPathSkipsCloneWhenDirExists` | wywołanie z istniejącym `-t` nie uruchamia `git clone`  |
| `testFastPathSourcesFileWhenXFlagSet` | gdy katalog istnieje i jest `-x`, plik jest sourcowany  |
| `testFastPathNoSourceWithoutXFlag`    | gdy katalog istnieje bez `-x`, plik nie jest sourcowany |
| `testReturnsErrorWithoutRepoUrl`      | brak `-r` → exit code 1                                 |
| `testClonesWhenDirAbsent`             | gdy katalogu nie ma, wywołuje `git clone` (mock git)    |
| `testTargetDirDerivedFromRepoName`    | bez `-t` katalog to `basename <url> .git`               |

Technika: mock `git` przez nadpisanie w PATH z `fixtures/bin/git` zwracającym 0 i logującym wywołania do pliku.
`assertNull` na pliku logu gdy fast-path działa.

---

### `test_get_and_build.sh`

Sourcuje: `bash/functions.d/010_function_log.sh`, `bash/functions.d/100_get_and_build.sh`  
Fixture: `fixtures/fake_git_repo/` z różnymi kombinacjami plików build

| Test                                 | Sprawdza                                                         |
|--------------------------------------|------------------------------------------------------------------|
| `testDetectsMaven`                   | repo z `pom.xml` → wykrywa Maven                                 |
| `testDetectsGradle`                  | repo z `build.gradle` → wykrywa Gradle                           |
| `testDetectsMix`                     | repo z `mix.exs` → wykrywa Mix                                   |
| `testDetectsNpm`                     | repo z `package.json` → wykrywa npm                              |
| `testDetectsCargo`                   | repo z `Cargo.toml` → wykrywa Cargo                              |
| `testMavenWinsOverGradle`            | repo z `pom.xml` i `build.gradle` → wygrywa Maven (niższy numer) |
| `testDryRunDoesNotBuild`             | flaga `-d` → nie uruchamia komendy budowania                     |
| `testSkipPullSkipsGit`               | flaga `-s` → nie wywołuje `git pull`                             |
| `testListShowsAllPlugins`            | flaga `-l` → wylistowuje wszystkie pluginy                       |
| `testUnknownBuildSystemReturnsError` | brak pliku build → exit code 1                                   |
| `testCustomPluginDirIsUsed`          | flaga `-p <dir>` → ładuje pluginy z podanego katalogu            |

Technika: dla testów detekcji — `dry_run`, sprawdzenie exit code i output. Mock `git pull` przez fake binary.

---

### `test_git_context.sh`

Sourcuje: `bash/functions.d/110_git-context.sh`  
Fixture: `fixtures/git_context_config` (plik INI z dwoma kontekstami), `fixtures/fake_git_repo/` (z `.git/`)

| Test                           | Sprawdza                                                                |
|--------------------------------|-------------------------------------------------------------------------|
| `testListsAvailableContexts`   | wyświetla dostępne konteksty z pliku config                             |
| `testSetsUserNameAndEmail`     | po wyborze kontekstu `git config user.name` i `user.email` są ustawione |
| `testHandlesMissingConfigFile` | brak `~/.config/git-context` → czytelny komunikat błędu                 |
| `testHandlesInvalidContext`    | nieistniejący kontekst → exit code 1                                    |
| `testDoesNotRunOutsideGitRepo` | wywołanie poza repo git → exit code 1                                   |

---

### `test_misc_functions.sh`

Sourcuje: `bash/functions.d/010_function_log.sh`, `bash/functions.d/095_function_misc.sh`

| Test                                 | Sprawdza                             |
|--------------------------------------|--------------------------------------|
| `testGenerateMonthDirsCreates12Dirs` | tworzy dokładnie 12 katalogów        |
| `testGenerateMonthDirsNamingFormat`  | nazwy w formacie `MM-nazwamiesiaca`  |
| `testGenerateMonthDirsSkipsExisting` | nie błęduje gdy katalog już istnieje |
| `testWeatherRequiresCityArg`         | brak argumentu → exit code 1         |

---

### `test_source_helpers.sh`

Sourcuje: `bash/bash_functions.sh`

| Test                                  | Sprawdza                                                      |
|---------------------------------------|---------------------------------------------------------------|
| `testSourceIfExistsLoadsExistingFile` | plik istnieje → jest sourcowany (sprawdź zmienną z pliku)     |
| `testSourceIfExistsSkipsMissingFile`  | plik nie istnieje → brak błędu                                |
| `testSourceDirectoryLoadsInOrder`     | pliki numerowane ładowane w kolejności alfabetycznej          |
| `testSuppressSourceingPreventsReload` | `SUPPRESS_SOURCING=1` → `bash/main.sh` wraca przed ładowaniem |

---

## Testy integracyjne (`integration/`)

Uruchamiane w kontenerze ubuntu:24.04 z zainstalowanymi: `bash`, `git`, `curl`, `tmux`, `asdf`.
Konfiguracja nie jest w pełni zainstalowana; symulowane przez zmienne środowiskowe i symlinki.

---

### `test_bash_loads.sh`

Sprawdza, że sourcing całego `bash/main.sh` nie produkuje błędów i eksportuje oczekiwane zmienne/funkcje.

| Test                                  | Sprawdza                                           |
|---------------------------------------|----------------------------------------------------|
| `testBashMainSourcesWithoutErrors`    | `bash -c '. bash/main.sh; echo OK'` → exit code 0  |
| `testLogFunctionsAvailableAfterLoad`  | po załadowaniu `declare -f log_info` → sukces      |
| `testGetAndBuildAvailableAfterLoad`   | po załadowaniu `declare -f get_and_build` → sukces |
| `testInstallLibAvailableAfterLoad`    | po załadowaniu `declare -f install_lib` → sukces   |
| `testPromptCommandContainsSdkmanInit` | `$PROMPT_COMMAND` zawiera `_sdkman_init`           |

---

### `test_exports.sh`

| Test                                         | Sprawdza                                                 |
|----------------------------------------------|----------------------------------------------------------|
| `testWorkspaceExported`                      | `$WORKSPACE` ustawiony                                   |
| `testWorkspaceToolsExported`                 | `$WORKSPACE_TOOLS` ustawiony                             |
| `testDockerComposeExportedWhenDockerPresent` | `$DOCKER_COMPOSE` = `docker compose` gdy docker dostępny |
| `testDockerComposeEmptyWhenDockerAbsent`     | `$DOCKER_COMPOSE` = `""` gdy docker niedostępny          |
| `testClaudeSkillConfigExported`              | `$CLAUDE_SKILL_CONFIG` ustawiony                         |
| `testSdkmanDirExported`                      | `$SDKMAN_DIR` ustawiony gdy katalog istnieje             |
| `testPathContainsSdkmanCandidates`           | `$PATH` zawiera sdkman candidates gdy zainstalowane      |
| `testPathHasNoSdkmanDuplicates`              | sdkman candidates w PATH tylko raz                       |

---

### `test_completion_stubs.sh`

| Test                                           | Sprawdza                                                          |
|------------------------------------------------|-------------------------------------------------------------------|
| `testLazyCompletionRegistered`                 | `complete -p` po załadowaniu zawiera handler default              |
| `testGitLazyCompletionRegisteredForG`          | `complete -p g` wskazuje na `_git_lazy`                           |
| `testAsdfCompletionCacheCreated`               | po pierwszym załadowaniu `~/.cache/asdf_bash_completion` istnieje |
| `testAsdfCompletionCacheNotRegeneratedIfFresh` | drugi source nie wywołuje `asdf completion bash`                  |

---

### `test_git_aliases.sh`

Wymaga działającego `git` w kontenerze. Weryfikuje obecność aliasów przez `git la` lub `git config --get-regexp alias`.

| Test                              | Sprawdza                                           |
|-----------------------------------|----------------------------------------------------|
| `testAliasFunDefined`             | alias `fun` istnieje w git config                  |
| `testAliasStDefined`              | alias `st` = `status`                              |
| `testAliasCiDefined`              | alias `ci` = `commit`                              |
| `testAliasNbDefined`              | alias `nb` wywołuje `fun git_new_feature_branch`   |
| `testAliasFuckDefined`            | alias `fuck` = `reset --soft HEAD~`                |
| `testGitConfigCopiedFromTemplate` | `~/.gitconfig` istnieje i zawiera sekcję `[alias]` |

---

## Testy e2e (`e2e/`)

Budowane na bazie istniejącego `Dockerfile-test`. Kontener uruchamia `initial_packages.sh`, wyniki odczytywane z logów.

| Test                           | Sprawdza                                                 |
|--------------------------------|----------------------------------------------------------|
| `testInitialPackagesExitsZero` | `docker run` → exit code 0                               |
| `testWorkspaceCreated`         | log kontenera zawiera sukces `prepare_workspace`         |
| `testAsdfInstalled`            | po instalacji `asdf --version` zwraca coś sensownego     |
| `testBashrcPrepared`           | `~/.bashrc` w kontenerze zawiera referencję do `main.sh` |
| `testNoErrorLines`             | logi nie zawierają linii z `❌`                           |

Technika: `docker run --rm ... 2>&1 | tee test/results/e2e.log`, grep na kluczowe frazy.

---

## Co jest wykluczone z testów

| Element                 | Powód                                 |
|-------------------------|---------------------------------------|
| `resize_to_full`        | wymaga X11/Wayland i aktywnego okna   |
| `run_tmux`              | wymaga działającego serwera tmux      |
| `print_logo` / neofetch | wymaga terminala i narzędzia neofetch |
| `dżepetto` / bash_chat  | wymaga klucza API OpenAI              |
| `install_apps`          | wymaga pobierania z internetu i GUI   |
| `install_docker`        | wymaga uprawnień root i systemd       |
| `maybe_restart`         | interaktywne; wywołuje reboot         |

---

## Szacunek pracochłonności i ryzyka

**Łącznie: ~35–48h (5–7 person-days)**

| Element                                                       | Szacunek | Trudność      | Kluczowe ryzyko                                                                                                                                                      |
|---------------------------------------------------------------|----------|---------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Infrastruktura (`Dockerfile-unit`, `run.sh`, `fixtures/bin/`) | 5–7h     | Średnia       | Volume mount, exit code propagation przez Docker                                                                                                                     |
| `test_log_functions.sh` (9 testów)                            | 1–2h     | Niska         | Zmienne kolorów `$C_*` — zerowane przed sourcowaniem                                                                                                                 |
| `test_misc_functions.sh` (9 testów)                           | 1–2h     | Niska         | `generate_month_dirs` operuje na CWD — wymaga `mktemp` w `setUp`                                                                                                     |
| `test_install_lib.sh` (6 testów)                              | 2–3h     | Średnia       | Mock `git clone` przez fake binary w PATH                                                                                                                            |
| `test_source_helpers.sh` (4 testy)                            | 2–3h     | Średnia       | Edge case `SUPPRESS_SOURCING`                                                                                                                                        |
| `test_exports.sh` (8 testów)                                  | 2–3h     | Średnia       | Mock `docker` przez fake binary                                                                                                                                      |
| `test_git_aliases.sh` (6 testów)                              | 1–2h     | Niska         | Proste grep na `git config --get-regexp alias`                                                                                                                       |
| `test_initial_packages.sh` (5 testów)                         | 2–3h     | Niska         | Wrapper na istniejący `Dockerfile-e2e`                                                                                                                               |
| `test_get_and_build.sh` (11 testów)                           | 4–6h     | Wysoka        | Największy plik; mock `git pull` i komend build; detekcja przez `--dry-run`                                                                                          |
| `test_completion_stubs.sh` (4 testy)                          | 3–4h     | Wysoka        | `complete` działa tylko w bash interaktywnym (`bash -i`), co komplikuje asercje                                                                                      |
| `test_bash_loads.sh` (5 testów)                               | 4–6h     | Bardzo wysoka | Ładowanie konfiguracji wywołuje `resize_to_full` (xdotool), `run_tmux`, `print_logo` (neofetch) — wszystkie muszą być zamockowane lub pominięte w kontenerze bez X11 |
| `test_git_context.sh` (5 testów)                              | 4–5h     | Bardzo wysoka | Funkcja jest w pełni interaktywna (`read -rp` w pętli) — wymaga `printf "1\n" \| git_context` lub testowania wewnętrznych `_gc_*` bezpośrednio                       |

### Trzy największe ryzyka

**1. `test_bash_loads.sh` — środowisko integracyjne**
Bash config przy ładowaniu bezwarunkowo wywołuje `run_tmux`, `resize_to_full` i `print_logo`. W kontenerze bez X11 i
tmux te funkcje muszą albo dostać mocki, albo `bash/bash_start_window.sh` musi obsłużyć ich brak gracefully. Sprawdzenie
ile z tych warunków jest już obsługiwanych zajmie dodatkowy czas.

**2. `test_git_context.sh` — interaktywność**
`_gc_select_context` ma `while true; do read -rp ...` — nie da się tego wywołać normalnie w teście. Opcje:
`printf "1\n" | git_context` (pipe na stdin), albo testowanie wewnętrznych `_gc_*` funkcji bezpośrednio (wymagają bycia
widocznymi poza funkcją `git_context`).

**3. `test_completion_stubs.sh` — bash `complete` w nieinteraktywnej powłoce**
`complete -p g` w `bash --norc` nie zadziała bo `complete` w powłoce nieinteraktywnej jest no-op. Wymaga
`bash -i -c '...'` z pułapkami (pojawia się PS1, PROMPT_COMMAND itp.).

### Rekomendowana kolejność implementacji

1. Infrastruktura + `test_log_functions.sh` ✅ — fundament pod wszystko
2. `test_misc_functions.sh` ✅ — szybka wygrana
3. `test_get_and_build.sh` — duża liczba testów, logika izolowalna przez `--dry-run`
4. `test_install_lib.sh` + `test_source_helpers.sh` — mock git, SUPPRESS_SOURCING
5. `test_git_aliases.sh` + `test_initial_packages.sh` — proste, duża widoczność
6. `test_exports.sh` — testy integracyjne, mock docker
7. `test_bash_loads.sh` — po weryfikacji co działa w kontenerze bez X11
8. `test_completion_stubs.sh` + `test_git_context.sh` — na końcu, wymagają decyzji architektonicznych

---

## Runner (`test/run.sh`)

Scenariusz działania:

```
1. Zbuduj obraz unit (Dockerfile-unit) jeśli nie istnieje lub jest starszy od plików
2. Uruchom kontener z volumes:
     -v $(pwd):/project:ro
     -v $(pwd)/test/results:/results
3. Wewnątrz kontenera: uruchom wszystkie test/unit/test_*.sh i test/integration/test_*.sh
4. Zapisz wyniki do /results/results.log
5. Na hoście: sprawdź exit code; wydrukuj podsumowanie
6. Opcjonalnie uruchom e2e gdy przekazano flagę --e2e
```

Zmienne sterujące:

- `RUN_E2E=1` — włącz testy e2e (domyślnie: wyłączone)
- `TEST_FILTER=<pattern>` — uruchom tylko pliki pasujące do wzorca
