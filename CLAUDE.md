# CLAUDE.md

Ten plik zawiera wskazówki dla Claude Code (claude.ai/code) dotyczące pracy z tym repozytorium.

## Czym jest to repozytorium

Osobista konfiguracja środowiska powłoki — aliasy bash, funkcje, skróty git, hooki oraz konfiguracje usług (Docker,
Nginx, Postgres itp.). Ładowane z `~/.bashrc` przez wskazanie na `main.sh` tego repozytorium.

Repozytorium nazywa się **`koziolek-configuration`** (`git@github.com:Koziolek/koziolek-configuration.git`);
zmienna `PROJECT_NAME` w skryptach instalacyjnych. Stara nazwa `git-configuration` jest utrzymywana przez
przekierowania GitHuba — nowy kod używa nowej.

Obsługiwane systemy (patrz „Konteksty" niżej): **Ubuntu/Debian**, **macOS**, **Vanilla OS 2** (kontener `apx`),
**WSL**, **RedHat/CentOS/Fedora** (rodzina yum). Elementy swoiste dla systemu są wydzielone do
`bash/contexts/<system>.sh`; nie dodawaj rozgałęzień `if [[ "$(uname -s)" == "Darwin" ]]` w kodzie wspólnym.

## Testowanie

```bash
./test/run.sh               # testy unit + integration (Docker na Linux, wymagane --native na macOS)
./test/run.sh --native      # uruchom bezpośrednio na hoście, bez Dockera (macOS)
./test/run.sh --e2e         # dodatkowo e2e: ubuntu/install.sh w Ubuntu 24.04 (wolne)
./test/run.sh --e2e-local   # e2e z lokalnym projektem podpiętym jako volume
./test/run.sh --e2e-redhat  # e2e: redhat/install.sh w rockylinux:9 (wolne)
./test/run.sh --e2e-vanilla # e2e: vanilla/install.sh w debian:sid (wolne)
./test/run.sh --e2e-certs   # e2e: prawdziwy JDK+openssl - prepare_cert + update_sdkman_jdk_certs (wolne)
./test/run.sh --all         # unit + integration + wszystkie e2e
./test/run.sh --filter <wzorzec>  # tylko pliki testowe pasujące do wzorca
```

### Lint skryptów powłoki (`tools/lint-shell.sh`)

`tools/lint-shell.sh [--check | --format] [--all | --base REF] [PLIK…]` sprawdza i formatuje skrypty przez **linthis** (ShellCheck + shfmt). Skrypt jest samodzielny
(nie sourcuje niczego z repo), więc nadaje się do skopiowania do innych projektów; konfigurację bierze z projektu: `.shellcheckrc` (dialekt `bash`, wstępna lista wyłączeń
z uzasadnieniami) i `.editorconfig` (shfmt: 4 spacje). Bez opcji robi format + check; **format zmienia pliki w miejscu**, a `--check` ich nie rusza. Zakres bez `PLIK…`:
pliki `*.sh`/`*.bash` zmienione względem merge-base z gałęzią domyślną origin (commity, working tree, nowe niezignorowane) — całe repo nie zostanie przeformatowane
przypadkiem; `--all` = wszystkie śledzone, `--base REF` = inny punkt odniesienia. Wywołuje `linthis --lang shell --checks lint --no-save-result` (+ `--check-only`/`--format-only`).
Kody wyjścia (od linthis): `error` ShellChecka → 1, `warning` → 2, `info`/`style` → 0 (wypisywane, ale nie wywalają); skrypt sam zwraca 64 za zły argument i 127 za brak narzędzia. Brak `linthis`/`shellcheck`/`shfmt`
w PATH = kod 127 z odesłaniem do instalacji (`packages/commons/lang_packages.sh`). Repo ma dziś wiele plików niezgodnych z 4 spacjami (stare mają 2) — nie formatujemy ich hurtem,
tylko przy okazji zmian. Test: `test/unit/test_lint_shell.sh` (atrapy narzędzi w hermetycznym PATH + prawdziwe repozytoria git; testy z prawdziwym linthis pomijają się, gdy go brak).

Runner (`test/run.sh`) sprawdza/przygotowuje środowisko Docker (obrazy, sieć), buduje obrazy testowe z
`test/Dockerfile-unit` i `test/Dockerfile-e2e`/`test/Dockerfile-e2e-redhat`/`test/Dockerfile-e2e-vanilla`/
`test/Dockerfile-e2e-certs`, i deleguje do `test/run-inside.sh`, który odpala pliki `test_*.sh` z `test/unit/`,
`test/integration/` (oraz warianty `linux/`/`darwin/` zależnie od `uname -s`) przez `shunit2`. Wyniki lądują w
`test/results/`. Testy e2e (`test/e2e/`) budują obraz z lokalnym `ubuntu/install.sh`/
`redhat/install.sh`/`vanilla/install.sh` (`COPY`, nie curl z GitHuba) — testują bieżące,
niezacommitowane zmiany; `entrypoint-test.sh` jest wspólny dla wszystkich trzech (skrypt docelowy przez
`INIT_SCRIPT`), zawężony do bezpiecznych funkcji (`install_initial_packages`, `prepare_workspace`,
`prepare_bashrc` — bez `install_docker`/`install_gh`/`install_kubectl`, zależnych od `systemctl`/sieci). Wariant
vanilla używa obrazu bazowego `debian:sid` (ta sama baza co realny subsystem `apx`) z `ENV container=oci` w
`Dockerfile-e2e-vanilla` — symuluje marker, którego `vanilla/install.sh` wymaga jako dowodu, że nie
leci na immutable hoście (Docker, w przeciwieństwie do Podmana, nie ustawia go sam). Wszystkie trzy warianty (ubuntu/redhat/vanilla) dodatkowo wołają w `entrypoint-test.sh` `install_git_bug` (sieć:
GitHub Releases) i weryfikują markerami w logu: binarkę w `~/.local/bin`, `man -w git-bug`/`git-bug-bug` bez `MANPATH`
(man-db sam dokłada `../share/man` dla katalogów z PATH), completion załadowane leniwie przez `bash-completion`
(`_completion_loader git-bug` + `complete -p`) oraz no-op przy drugim wywołaniu. Obrazy `Dockerfile-e2e*` mają w tym
celu `man-db` i `bash-completion` (tylko pod test; w minimalnym Ubuntu `man` to zaślepka — entrypoint woła `man.REAL`).
Nie testuje to realnego
Podmana/apx, tylko poprawność samego skryptu apt na debianowej bazie. Uruchamiane też w CI:
`.github/workflows/test.yml` (unit+integration na push/PR do
`master`; e2e pozostaje lokalne/manualne — wymaga Dockera i sieci).

Wariant `--e2e-certs` (`test/Dockerfile-e2e-certs`, obraz bazowy `eclipse-temurin:21-jdk` + `openssl`) stoi obok
`test/unit/test_services_functions.sh` (tam `keytool` jest mockiem, testuje samą logikę iteracji/warunków) —
tu nic nie jest mockowane: prawdziwy `openssl` generuje cert przez `prepare_cert`, prawdziwy `keytool` (przez
`update_sdkman_jdk_certs`) importuje go do kopii rzeczywistego `cacerts` obrazu, prawdziwy `openssl s_server`
serwuje TLS na tym certyfikacie, a klient JVM (`HttpsURLConnection`, skompilowany w locie z `TlsCheck.java`)
łączy się z nim przez realny handshake — weryfikując faktyczne zaufanie JVM, a nie tylko obecność wpisu w
keystore. Test (`test/integration/certs/test_sdkman_jdk_certs.sh`, `shunit2`) sprawdza: cert bez importu jest
odrzucany (`PKIX`/`SSLHandshakeException`), po imporcie połączenie się udaje, `keytool -list` widzi alias
`koziolek-nexus`, a powtórny import nie duplikuje aliasu. Bez zależności sieciowych w runtime kontenera (poza
jednorazowym pobraniem obrazu bazowego) — serwer i klient łączą się po `127.0.0.1`.

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

`bash_customs.sh` (nadpisania per-maszyna, ładowany ostatni) klonuje przez `install_lib` zewnętrzne repozytoria do
`$WORKSPACE_TOOLS`: `shunit2` (framework testów, `-e shunit2.sh`), `BashMan` (generator man z komentarzy funkcji, `-e bashman.sh -x`), `FossFLOW` (diagramy izometryczne),
`maven-bash-completion` (+ symlink `~/.maven-bash-completion`), `claude-bash-completion` (completion dla `claude`,
sourcowany w `bash_completion.sh` z `$WORKSPACE_TOOLS/claude-bash-completion/claude-completion.bash`; test:
`test/unit/test_claude_completion.sh`), `klaudyna` (**prywatny** warsztat skilli Claude Code:
`/prepare-commit`, `/create-skill`; skille rejestrowane symlinkami `~/.claude/skills/<nazwa>` → `skills/<nazwa>/`) oraz
`fix-comp` (**prywatne** skrypty diagnostyczne). Oba prywatne repo idą z `-p`: `install_lib -p` = bezpieczny klon, brak
dostępu to ostrzeżenie i pominięcie, nie błąd (bez `-p` `git clone` pyta o hasło).

Odpowiedzialność kluczowych plików funkcji:

- `functions.d/000_*` — uruchomienie/inicjalizacja (`resize_to_full` routuje przez `detect_display_env`)
- `functions.d/005_function_messages.sh` — komunikaty wielojęzyczne: `messages_lang`, `messages_load`,
  `messages_ensure_loaded` (patrz „Komunikaty (i18n)" niżej)
- `functions.d/010_*` — logowanie (`log_info`, `log_error`, `log_warn`, `log_man`, `log_debug`)
- `functions.d/015_*` — prompt PS1
- `functions.d/040_*` — helpery Docker
- `functions.d/096_function_apt_trust.sh` — `refresh_apt_gpg_keys` (naprawa `NO_PUBKEY`/martwych
  repo apt, kluczy przypina `signed-by=` do konkretnego repo, nigdy `trusted.gpg.d`). Domena
  zupełnie inna niż klaster `15X` niżej (zaufanie kluczy repo apt, nie tożsamość/podpis) —
  nazwa pliku celowo bez „gpg”, żeby nie sugerować przynależności do tamtej grupy.
- `functions.d/100_get_and_build.sh` — funkcja `get_and_build` (patrz niżej)
- `functions.d/110_git-context.sh` — funkcja `git_context`
- `functions.d/130_function_screen.sh` — `detect_display_env()` (gnome/sway/wlroots/x11/wayland; `darwin` z cienia)
- `functions.d/140_function_diagnostic.sh` — `hwinfo()` (zrzut CPU/płyta główna+BIOS/RAM/GPU;
  wersja Linux — dmidecode/lspci/proc; `darwin.sh` cieniuje `hwinfo_cpu`/`hwinfo_motherboard`/
  `hwinfo_ram`/`hwinfo_gpu`/`_hwinfo_check_deps` wersją system_profiler/sysctl) oraz
  `run_diagnostic()` — uruchamia `pre-analyze.sh` z prywatnego repo `fix-comp`
  (`$WORKSPACE_TOOLS/fix-comp`, klonowane przez `install_lib -p` w `bash_customs.sh`)
  z dowolnego katalogu roboczego; logi lądują w `fix-comp/logs` jak przy bezpośrednim
  uruchomieniu (skrypt liczy swoją lokalizację przez `${BASH_SOURCE[0]}`, nie `$PWD`)
- `functions.d/150_function_fido2.sh` — zarządzanie kluczami sprzętowymi FIDO2/U2F, per klucz /
  per sesja: `fido2_list_devices`, `fido2_info`, `fido2_set_pin`, `fido2_change_pin`,
  `fido2_enroll` (+ `_list`/`_name`/`_delete` — biometria), `fido2_register_sudo`
  (+ `_backup` — dopisanie kolejnego klucza bez nadpisania), `fido2_sudo_keys_list`.
  Wykrywanie klucza przez `fido2-token -L` (libfido2) — przenośne Linux/macOS, bez zależności
  od udev/hidraw, dowolna marka (Yubico, Titan, Nitrokey, SoloKeys, Feitian, Thetis). Każda
  funkcja przyjmuje opcjonalny `[DEV]`; bez niego — jeden wykryty klucz użyty wprost, kilka —
  interaktywne menu z wyborem po numerze (`_fido2_resolve_device`). PIN/enrollment interaktywnie
  (`fido2-token` pyta w terminalu — PIN nie przechodzi przez argumenty ani historię powłoki).
  Wpisy sudo lądują w `~/.config/Yubico/u2f_keys` (ścieżka zaszyta w `pam_u2f`, niezależna
  od marki). Konfiguracja **maszyny** (pakiety `fido2-tools`/`libpam-u2f`, linia `pam_u2f.so`
  w `/etc/pam.d/sudo`) to nie tu — `fix-comp/scripts/bezpieczenstwo/01-fido2-diagnostic.sh`
  (jednorazowo); `_fido2_check_deps` odsyła tam przy braku zależności.
- `functions.d/155_function_git_signing.sh` — podpisywanie **commitów git**, trzy alternatywne
  backendy w jednym pliku (ten sam cel, inny sprzęt albo brak sprzętu): sekcja GPG-karta, sekcja
  SSH-sk, sekcja GPG software. `gpg_git_setup`/`ssh_sk_git_setup`/`gpg_sw_git_setup` wzajemnie się
  nadpisują (`gpg.format`/`user.signingkey` w `~/.gitconfig`), aktywna jedna metoda naraz.
  **GPG-karta** (klucz prywatny tylko na karcie): `gpg_git_setup` (fingerprint slotu podpisu
  czytany z `gpg --card-status --with-colons`, import klucza publicznego: URL z karty →
  `$GPG_PUBKEY_URL` → keyserver, stuby + ultimate trust, `git config --global` do **stuba**
  `~/.gitconfig` — nie do `git_config.template`), `gpg_git_disable`, `gpg_card_status`,
  `gpg_card_import_pubkey`, `gpg_card_test`, `gpg_agent_restart`, `gpg_card_use_pcscd`. Pinentry:
  hook `_gpg_pinentry_setup` (Linux no-op, `contexts/darwin.sh` → `pinentry-mac`); `GPG_TTY`
  eksportowane w `bash_exports.sh`. Helpery zwracające dane przez stdout logują na stderr
  (`log_*` piszą na stdout).
  **SSH-sk** (klucz prywatny tylko w urządzeniu FIDO2 bez apletu OpenPGP, np. Thetis BioFP+):
  klucz **resident** z aplikacją `$SSH_SK_APPLICATION` (domyślnie `ssh:git-signing`) +
  `verify-required`, odtwarzany na każdej maszynie przez `ssh-keygen -K` (plik
  `id_ed25519_sk_rk_<aplikacja bez ssh:>[_<user>]`). `ssh_sk_key_create` (raz), `ssh_sk_git_setup`
  (per maszyna: stub, `allowed_signers` w `~/.config/git/`, `gpg.format=ssh` w stubie
  `~/.gitconfig`), `ssh_sk_key_load`, `ssh_sk_test`, `ssh_sk_github_upload`, `ssh_sk_git_disable`,
  `ssh_sk_use_existing` (istniejący klucz `-sk`, odmawia kluczy z dysku; aplikacja `ssh:` → plik
  bez segmentu, tylko `id_ed25519_sk_rk`). Binarka przez `${SSH_KEYGEN:-ssh-keygen}` —
  `contexts/darwin.sh` wskazuje `openssh` z brew (Apple ssh bez FIDO).
  **GPG software** (`gpg_sw_git_*`, klucz prywatny na dysku w `~/.gnupg`, chroniony tylko
  passphrase — dla sprzętu bez apletu OpenPGP i bez FIDO2): `gpg_sw_git_setup [keyid]` (bez
  argumentu czyta `KEYID` z `~/.config/git-configuration-signing/gpg-sw.cfg`, czyli klucz
  ostatnio wygenerowany przez `gpg_sw_generate` w 157 — sama konfiguracja `user.signingkey`/
  `gpg.format`/`commit.gpgsign` w `~/.gitconfig`, bez wymogu karty), `gpg_sw_git_disable`,
  `gpg_sw_test` (próbny `--clearsign`). Klucz **nie** przenosi się sam między maszynami (w
  przeciwieństwie do karty/FIDO2) — trzeba go wyeksportować/zaimportować ręcznie albo wygenerować
  osobno na każdej. Ścieżka configu zaszyta jako stała w 155 (nie wołamy prywatnych helperów z
  157 — 157 ładuje się PO 155 alfabetycznie, więc jego funkcje nie są jeszcze zdefiniowane).
  Test: `test/unit/test_git_signing.sh` (mock `gpg`/`gpgconf`/`ssh-keygen`/`gh`; dwa harnessy
  uruchamiania, `_run_gpg`/`_run_ssh`, sourcujące ten sam plik).
- `functions.d/157_function_maven_signing.sh` — podpisywanie **artefaktów Mavena**, trzy
  alternatywne backendy w jednym pliku (dzielą helpery manipulacji `~/.m2/settings.xml`, więc
  merge usuwa ukrytą zależność międzyplikową, którą wymuszała kolejność ładowania):
  **JAR/PKCS11**, **JAR software** i **GPG software**.
  **JAR/PKCS11** (`jar_*`): podpisywanie plików JAR kluczem sprzętowym przez PKCS11
  (`jarsigner -storetype PKCS11`, moduł OpenSC `opensc-pkcs11.so`, aplet **PIV** karty — X.509
  cert + klucz RSA/EC wygenerowany NA karcie; klucze czysto FIDO2 bez PIV, np. Thetis BioFP+,
  **nie obsłużą** tego). `jar_pkcs11_setup` (znajdź moduł, zweryfikuj cert na karcie, zapisz
  `~/.config/git-configuration-signing/pkcs11.cfg`), `jar_pkcs11_status`, `jar_pkcs11_test`
  (sign+verify tymczasowego jara), `jar_sign`/`jar_verify` (ręcznie, bez `-storepass` w argv;
  `-l`/`--list` wylistuj aliasy certów na karcie — `_jar_pkcs11_list_aliases`; `jar_sign`
  dodatkowo `-k`/`--key <alias>`, stary drugi argument pozycyjny nadal działa). `jar_maven_setup`/
  `jar_maven_disable` — profil `jar-hw-signing` w `~/.m2/settings.xml` (`jarsigner.*` property
  expressions czytane przez `maven-jarsigner-plugin`).
  **JAR software** (`jar_sw_*`, keystore JKS na dysku zamiast karty — dla maszyn bez apletu PIV;
  weryfikacja **niezależna od backendu**, `jar_verify` wyżej działa dla obu): `jar_sw_generate
  <alias> <CN>` (`keytool -genkeypair`, RSA 3072, self-signed, bez `-storepass`/`-keypass` w argv —
  interaktywny prompt jak w PKCS11; zapisuje `~/.config/git-configuration-signing/jar-sw.cfg` +
  keystore w `jar-sw-keystore.jks`, override `$JAR_SW_KEYSTORE`), `jar_sw_sign <plik.jar>
  [alias]` (auto-detekcja aliasu z configu, gdy pominięty), `jar_sw_maven_setup`/
  `jar_sw_maven_disable` — profil `jar-sw-signing` (`jarsigner.storetype=JKS`), współistnieje z
  `jar-hw-signing`/`gpg-sw-signing`.
  **GPG software** (`gpg_sw_*`/`gpg_maven_*`): podpisywanie artefaktów Mavena kluczem PGP
  **softwarowym** (`maven-gpg-plugin`, publikacja na Maven Central przez Sonatype Central —
  patrz `devtools-maven-extension/pom.xml`, profil `deployment`), dla maszyn/kluczy bez apletu
  OpenPGP/PIV na karcie (jeśli karta MA aplet OpenPGP, użyj zamiast tego `gpg_git_setup` z 155 —
  klucz wtedy nigdy nie opuszcza karty). Klucz prywatny leży w zwykłym keyringu `~/.gnupg`,
  chroniony tylko passphrase (przez zwykły pinentry gpg-agent — ten sam hook co 155's
  `_gpg_pinentry_setup`). Jedno polecenie na cały proces: `gpg_sw_setup` — generuje klucz
  (`gpg_sw_generate`, ed25519/sign-only/2y domyślnie, `gpg --quick-generate-key`), zapisuje
  fingerprint w `~/.config/git-configuration-signing/gpg-sw.cfg`, eksportuje na keyserver
  (`gpg_sw_export <keyid> ubuntu|openpgp|both` — `openpgp` przez VKS API
  `keys.openpgp.org/vks/v1/upload`, UID-y zostają niezweryfikowane dopóki nie potwierdzisz linku
  z maila), pyta czy dopiąć do Mavena. `gpg_maven_setup`/`gpg_maven_disable` — profil
  `gpg-sw-signing` w `~/.m2/settings.xml` (`<gpg.keyname>`). `gpg_sw_list_keys` — lista kluczy w
  keyringu. Kroki `gpg_sw_setup` pomijalne nieinteraktywnie przez `GPG_SW_NAME`/`GPG_SW_EMAIL`/
  `GPG_SW_EXPORT_TARGET`/`GPG_SW_MAVEN_CONFIRM` (ten sam wzorzec co `GIT_ASSUME_YES` w
  `git/git_functions.sh`).
  Eksport na `keys.openpgp.org` to helper `_gpg_sw_export_openpgp`: `POST /vks/v1/upload` z JSON-em
  `{"keytext": "<armored>"}` (surowy `PUT` binarium daje 404), potem `POST /vks/v1/request-verify`
  (token z odpowiedzi + adres z UID-a) zleca mail weryfikacyjny; trzeci argument `gpg_sw_export`
  (`noverify`) pomija ten krok. `keyid` walidowany jako hex (8-40 znaków, opcjonalnie `0x`).
  `gpg_sw_generate` przekierowuje stdout `gpg --quick-generate-key` na stderr — inaczej blok `pub …`
  trafia do `$(gpg_sw_generate)` i psuje fingerprint (a z nim eksport i `gpg.keyname` w Mavenie).
  **Odwołanie/usuwanie:** keyserverów nie da się wyczyścić (SKS nie kasuje, openpgp pokazuje klucz
  jako unieważniony), więc `gpg_sw_revoke <keyid> [ubuntu|openpgp|both|none]` generuje certyfikat
  (`gpg --batch --command-fd 0 --gen-revoke`, powód `GPG_SW_REVOKE_REASON` 0-3, plik
  `revoke-<fpr>.asc` 0600 w `~/.config/git-configuration-signing/`), importuje go i publikuje.
  `gpg_sw_delete_all` — nieodwracalne usunięcie wszystkich kluczy z keyringu (`--delete-secret-and-
  public-keys`), `gpg-sw.cfg` i profilu `gpg-sw-signing`; potwierdzenie wpisaniem `TAK`
  (`GPG_SW_ASSUME_YES=1` pomija), przed usunięciem odwołuje klucze (`GPG_SW_REVOKE=1|0`, brak =
  pytanie); klucz, którego odwołanie się nie powiodło, nie jest usuwany (wtedy `gpg-sw.cfg` i profil
  Mavena też zostają). `gpg_sw_revoke` bierze gotowy certyfikat z `$GNUPGHOME/openpgp-revocs.d/<fpr>.rev`
  (gpg ≥ 2.1 tworzy go przy generowaniu klucza; zdejmowany dwukropek sprzed nagłówka `-----BEGIN`),
  a `--gen-revoke` — **bez** `--batch`, bo ten tryb go odrzuca ("nie działa w trybie wsadowym") —
  tylko gdy pliku brak albo `GPG_SW_REVOKE_REASON` ≠ 0. Usuwa też stuby kart;
  nie rusza SSH-sk ani JKS.
  **Wspólne** — `~/.m2/settings.xml`: `~/.m2/settings.xml` może już mieć realną konfigurację
  (mirrory/servery Nexusa, patrz `services/nexus/key_setup.sh`) — **nigdy nie
  parsujemy/przepisujemy całego pliku** (np. `ElementTree` kasuje komentarze przy reserializacji);
  zamiast tego idempotentny insert oznaczonego bloku (`<!-- <marker>:BEGIN/END -->`) do
  `<profiles>`/`<activeProfiles>` (dopisywanych tylko jeśli ich jeszcze nie ma —
  `_maven_settings_ensure_container`), resztę pliku zostawia nietkniętą — ten sam styl co
  `gpg_card_use_pcscd` (idempotentny append do `scdaemon.conf`), tylko na blok XML. Nazwane
  `_maven_settings_*` (nie `_jar_*`) właśnie dlatego, że obsługują wszystkie trzy profile —
  `jar-hw-signing`, `jar-sw-signing`, `gpg-sw-signing` — które mogą współistnieć w jednym pliku,
  każdy w swoim oznaczonym bloku.
  Test: `test/unit/test_maven_signing.sh` (mock `pkcs11-tool`/`jarsigner`/`keytool`/`jar`/`gpg`/
  `curl`; blok maven-settings testowany na realnych plikach — bez mocków, to czysta manipulacja
  tekstem).
- `functions.d/160_cron.sh` — wygodna konfiguracja crontaba: `cron_list [-o]` (własne zadania z numerami
  + **wszystkie zadania innych użytkowników i systemu, do których jest dostęp** — spoole, `/etc/crontab`,
  `/etc/cron.d`, nazwy skryptów `cron.{hourly,daily,...}`; `-o` = tylko własne), `cron_add [-n nazwa]
  [--no-log] <harmonogram> <polecenie…>`, `cron_remove <nr|wzorzec>`, `cron_edit` (`$VISUAL`/`$EDITOR` +
  walidacja składni przed zapisem), `cron_schedule <opis>` (tłumaczy „co 5 min”, „codziennie o 03:00”,
  „w poniedziałek o 08:00”, `hourly`, `at boot` … na składnię cron; gotowe 5 pól/`@makro` przechodzi po
  walidacji zakresów). **Cudzych zadań wolno tylko czytać** — funkcje modyfikujące działają wyłącznie na
  własnym crontabie (nigdy `crontab -u`; pilnuje tego `testNeverCallsCrontabWithUserFlag`). `cron_add`
  dopisuje do oznaczonego bloku `# koziolek-cron:BEGIN/END` (ustawia w nim `SHELL`/`PATH`; reszta crontaba
  nietknięta — ten sam styl co blok XML w 157), jest idempotentne, escapuje `%` i kieruje wyjście do
  `${CRON_LOG_DIR:-~/.cache/cron}/<nazwa>.log`; pusty blok znika po `cron_remove`. Różnice per-system przez
  zmienne (`CRON_SPOOL_DIRS`, `CRON_SYSTEM_FILES`, `CRON_SYSTEM_DIRS`, `CRON_PERIODIC_DIRS`,
  `CRON_DAEMON_CHECK`, opcjonalnie `CRON_USE_SUDO=1` → `sudo -n cat` dla nieczytelnych spooli);
  `contexts/darwin.sh` ustawia spool `/usr/lib/cron/tabs` i wyłącza sprawdzanie demona (launchd). Brak
  działającego demona (subsystem `apx` Vanilla OS) = ostrzeżenie `cron.no_daemon`, nie błąd. Test:
  `test/unit/test_cron.sh` (mock `crontab` na pliku).

Funkcje w `functions.d/` trzymają **wersję Linux** (bez guardów `uname`). Rozbieżności per-system
rozwiązuj tak, by **jak najwięcej zostało wspólne**:

- pośrednictwo zmiennej: funkcja używa `${DOCKER_CLI:-docker}`, a `contexts/vanilla.sh` ustawia
  `DOCKER_CLI=podman` — funkcja się nie rozgałęzia i nie dubluje;
- dopiero gdy się nie da (`/proc`, `swapoff`, `systemd`, `apt`) — `contexts/darwin.sh`
  **redefiniuje** całą funkcję (`reswap`, `who_use_swap`, `turn_async_profiler_*`, `start_x`,
  `netconf_diag`, `refresh_apt_gpg_keys`, `_listening_socket_pairs`, `detect_display_env`,
  `_gpg_pinentry_setup`);
- co wspólne dla rodziny → wyżej w łańcuchu: instalacja `hub` przez apt jest w `contexts/debian.sh`
  (widzą ją `ubuntu` i `vanilla`), nie w liściach.

### Konteksty (`bash/contexts/`)

`$OS_TYPE` (`uname -s`) rozróżnia tylko Darwin/Linux — za mało dla różnic Ubuntu / Debian /
Vanilla OS / WSL / RedHat. `bash/contexts/detect.sh` dokłada warstwę:

- **`detect_context()`** → jedno słowo (liść): `darwin` / `ubuntu` / `debian` / `vanilla` / `wsl` /
  `redhat` / `linux`. Źródła: `uname`, `/etc/os-release` (`ID`/`ID_LIKE`), `/proc/version`,
  `$WSL_DISTRO_NAME`. Wynik w `$CONFIG_CONTEXT` (eksport z `main.sh`). Wymuszenie w testach:
  `CONFIG_CONTEXT_FORCE=…`, podmiana pliku: `OS_RELEASE_FILE=…`.
- **`context_chain()`** rozwija liść w łańcuch ogólny→szczegółowy: `vanilla → linux debian vanilla`,
  `ubuntu → linux debian ubuntu`, `wsl → linux debian wsl` (WSL jest w praktyce zawsze
  Ubuntu/Debian pod spodem — dziedziczy apt/hub z `debian.sh`), `redhat → linux redhat`
  (RHEL/CentOS/Fedora/Rocky/Alma — rodzina yum, osobna od debian), `darwin → darwin`.
- **`load_contexts()`** (z `bash/main.sh`, po wspólnej konfiguracji, przed `bash_customs`) sourcuje
  `contexts/<c>.sh` dla każdego ogniwa — plik szczegółowy nadpisuje ogólniejszy.
- **`context_is <name>`** — czy `<name>` jest w łańcuchu (`context_is debian` jest prawdą i dla
  `ubuntu`, i dla `vanilla`).
- **`context_package_suffix [ctx]`** — mapuje kontekst na sufiks
  `packages/<sufiks>/{install,update}.sh` (`darwin→mac`, `vanilla→vanilla`, `redhat→redhat`,
  `ubuntu|debian|wsl→ubuntu`; kod 1 dla nieobsługiwanego). Jedyne źródło prawdy tego mapowania —
  konsumują je root-owe `initial_packages.sh`/`update_packages.sh` (patrz „Bootstrap pakietów”).
- **`resolve_vanilla_subsystem <ctx>`** — rozróżnia immutable host Vanilla OS od subsystemu `apx`
  (markery `/run/.containerenv` + `/run/host/etc/os-release`); kod 2 = immutable host, przerwij.

Pliki `contexts/{linux,debian,ubuntu,vanilla,wsl,redhat,darwin}.sh` trzymają **tylko** nadpisania
swojej warstwy (aliasy, `export`, redefinicje funkcji). Wspólne rzeczy zostają w `bash_*.sh` /
`functions.d/`. Stan: `linux` (aliasy), `debian` (hub/apt), `vanilla` (`DOCKER_CLI`/`DOCKER_COMPOSE`/`fix-net`, `vanilla_console_font` — `setfont Lat2-Terminus16` tylko na VT: `TERM=linux` + TTY na stdout, więc tmux i terminal graficzny pomija; nietrwałe, `VANILLA_CONSOLE_FONT` zmienia/wyłącza),
`wsl` (`in-window`→`wslview`), `redhat` (hub/yum), `darwin` (Homebrew, hub/brew, redefinicje funkcji);
`ubuntu` pusty. Testy: `test/unit/test_context_detect.sh`,
`test/unit/linux/test_{vanilla_aliases,vanilla_context,debian_context,wsl_context,redhat_context}.sh`.

### Komunikaty (i18n) — `bash/messages/`

Komunikaty logów żyją w `bash/messages/messages.<LANG>.sh` (bazowy `pl`, dodatkowo `en`) — same
przypisania do **pięciu tablic asocjacyjnych, po jednej na poziom**: `MSG_DEBUG`, `MSG_INFO`,
`MSG_WARN`, `MSG_ERROR`, `MSG_MAN`. Klucz `<obszar>.<nazwa>` (np. `install_lib.no_access`) → szablon
dla `printf` (`%s`, `%d`). Każda funkcja `log_<poziom>` czyta **wyłącznie własną tablicę**
(`log_warn` → `MSG_WARN`): `log_warn install_lib.no_access "$url"`. Pierwszy argument, który nie jest
kluczem własnej tablicy, to dosłowny tekst — stare wywołania `log_info "tekst"` działają bez zmian,
migracja może iść plik po pliku. Do **`log_message` (niezmienionego) trafia gotowy komunikat**, który
tylko dostaje prefiks/kolor.

Język: `MESSAGES_LANG` (np. w `~/.senv`) > `LC_ALL` > `LC_MESSAGES` > `LANG` (dwuliterowy kod; `C`/`POSIX`/
puste/nieznany plik → `pl`). Ładowany jest zawsze `pl`, a wybrany język nakłada się na niego, więc
klucz bez tłumaczenia wraca po polsku. Ładowanie jest leniwe (pierwsze użycie komunikatu) — start
powłoki nic nie kosztuje; działa też w procesach potomnych z `export -f`, gdzie tablice nie są
dziedziczone. Wartości placeholderów są danymi (`%`, `$(…)` w argumencie nie są interpretowane);
liczba argumentów musi odpowiadać placeholderom (nadmiarowe powtarzają szablon — zachowanie `printf`).
`MESSAGES_DIR` przekierowuje na inny katalog (testy). Nowy język = nowy plik `messages.<lang>.sh`
(test `testEveryPolishKeyHasEnglishTranslation` pilnuje kompletności `en`). Test:
`test/unit/test_messages.sh` — m.in. pilnuje, że każdy klucz użyty w kodzie (`log_<poziom> obszar.nazwa`)
ma definicję w tablicy swojego poziomu w `pl` i `en`. Testy asertujące polskie teksty ustawiają
`MESSAGES_LANG=pl` (inaczej wynik zależałby od `LANG` maszyny, np. en_US na macOS). Loader i guard w
`010_function_log.sh` nie używają zewnętrznych poleceń (`dirname`) — działają przy pustym `PATH`;
`MESSAGES_DEFAULT_LANG` i `_MESSAGES_DIR_DEFAULT` są eksportowane, bo w procesach potomnych
(`git fun …`) plik `005` nie jest sourcowany. Zmigrowane są wszystkie pliki z `log_*` (lista i stan: issue #135), w tym podpisywanie
(`150`, `155`, `157`), `110_git-context.sh` i `git/git_functions.sh`. Dosłownie zostają linie, w których
kolor, element listy albo zrzut danych jest częścią komunikatu (`"${C_RED}   - $service"`, `"  - $r"`,
`"user.name = $name"`, separatory `----`), polecenia do skopiowania (`"  git branch -M …"`,
`"export SSH_SK_KEY_FILE=…"`), `"Push tagów: $(… echo tak || echo nie)"` (słowo tak/nie wplecione w
argument) oraz generyczny `log_error "$message"`. Wartości z kolorem przekazuj jako argument
(`"${C_BOLD}$name${C_NC}"`) albo, gdy kolor otacza tekst, jako dwa `%s` (`"\n%sTytuł:%s"` z `C_BOLD`/`C_NC`);
literalny `%` po placeholderze to `%%`. Klucze nowych komunikatów nazywaj po angielsku (`obszar.krotki_opis`).
Testy, które mockują `log_*`, widzą „klucz argumenty”. `test_messages.sh` pilnuje też zgodności liczby
placeholderów `pl`/`en` dla każdego klucza. Pliki bez loggerów (`echo` w `packages/*.sh`,
`install.sh` itd.) **nie podlegają migracji**.

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
  aktualizacje repo.
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

**Pre-check „brak zmian”:** obie funkcje zaczynają od `git status --porcelain` (staged + unstaged +
untracked, bo i tak idzie `git add .`). Brak zmian → `INFO: Brak zmian` i **zamiast błędu o pustym
`commit-message.txt`** (ani dopisywania do pliku) sprawdzane są niewypchnięte commity
(`git rev-list --count @{u}..HEAD`; brak upstreamu = gałąź jeszcze niepushowana = też push): są →
zwykły `git push -u origin <gałąź>` (także w `git bleeh` — bez `--force-with-lease`, bo historii nie
przepisywano), nie ma → koniec z kodem 0. Są zmiany → działanie jak dotąd. Helpery:
`__git_has_changes_or_push`, `__git_has_unpushed` (niewyeksportowane).

### Funkcja `git_exterminatus_worktree`

`git exterminatus-worktree [-n|--dry-run]` (`git/git_functions.sh`) usuwa worktree, których gałąź jest już zmergowana do
gałęzi domyślnej (`origin/HEAD`, domyślnie `master`): worktree, lokalną gałąź i zdalną (jeśli istnieje). Po `git fetch --prune`
rozpoznaje zwykły/ff merge (`merge-base --is-ancestor`) **i squash/rebase merge** — `git branch --merged` tego nie widzi, więc
tworzy tymczasowy commit z drzewem gałęzi na `merge-base` i sprawdza `git cherry` (zmiana ma odpowiednik po patch-id; nie
potrzebuje `gh`). Zostają: niezmergowane, brudne (`git worktree remove` bez `--force`), bieżące oraz świeże gałęzie bez własnych
commitów (jeden wpis w reflogu — inaczej wyglądałyby na zmergowane). `-n` tylko pokazuje. Główny checkout nigdy nie jest ruszany.
Test: `test/unit/test_git_exterminatus_worktree.sh` (prawdziwy git na bare origin w `mktemp`).

### Funkcja `git_context`

Interaktywne narzędzie do przełączania `user.name`/`user.email` git per-repozytorium, sterowane plikiem
`~/.config/git-context` (format INI z sekcjami `[nazwa_kontekstu]`, kluczami `name =`, `email =`).

### Sekrety

Wrażliwe zmienne środowiskowe trafiają do `~/.senv` (tworzony automatycznie przy pierwszym załadowaniu, tryb 400). Nigdy
nie commituj tu danych uwierzytelniających. Plik `.senv.template` pokazuje oczekiwane zmienne.

## Bootstrap pakietów (per system)

Instalacja i aktualizacja narzędzi — osobny katalog na system w `packages/` (`ubuntu/`, `vanilla/`, `redhat/`,
`mac/`), każdy z `install.sh` i `update.sh`, plus `packages/commons/` na rzeczy współdzielone. Zasada: plik używany
przez jeden system leży w jego katalogu (`redhat/yum_packages.sh`, `mac/brew_packages.sh`,
`vanilla/fixes.d/`), używany przez więcej niż jeden — w `commons/` (`apt_packages.sh` dla Debian/Ubuntu/Vanilla,
`prepare_workspace.sh`, `verify_and_run_script.sh`, `link_claude_skills.sh`, `git_bug.sh`, `sdk_tools.sh`, `sdk_tools_apply.sh`, `lang_packages.sh`, `lang_packages_apply.sh`, `fixes_runner.sh`, `fixes_apply.sh` oraz
`fixes.d/`). Fix dotyczący jednego systemu idzie do `packages/<system>/fixes.d/`, współdzielony do `commons/fixes.d/`.

**`install.sh`** (root repo) — bootstrap pod `curl … | bash`, dla maszyny bez klonu. Robi **tylko**: `ensure_git` →
klon repo do `~/workspace/<projekt>` + symlink `~/.<projekt>` (inline, idempotentny, bez `pull`) →
`bash ~/.<projekt>/initial_packages.sh`. Niczego poza `git clone` nie pobiera z sieci i nie ma własnej logiki wyboru
systemu: wykrycie kontekstu, rozróżnienie host/subsystem Vanilla i mapowanie na skrypt robi dispatcher z klona
(patrz niżej) — jedno miejsce, bez zduplikowanych kopii. Zmienne: `KOZIOLEK_REF` (gałąź/tag; `git clone --branch`,
tylko świeży klon — istniejący zostaje nietknięty), `PROJECT_CLONE_URL` (adres klona; testy podstawiają lokalne
repo). Test: `test/unit/test_install_dispatch.sh` (offline: lokalne repo w `mktemp`, podmieniony `HOME`; pilnuje
też, że `install.sh` nie zawiera `raw.githubusercontent`/`curl -`/`wget` ani `detect_context` poza komentarzami).

**`initial_packages.sh`** / **`update_packages.sh`** (root repo) — te same dispatchery co `install.sh`,
ale dla repo już sklonowanego: sourcują lokalny `bash/contexts/detect.sh` (bez sieci) i wołają wprost
`context_package_suffix()` + `resolve_vanilla_subsystem()` — tu nie ma powodu do duplikacji, bo lokalne
sourcowanie nic nie kosztuje. Zmienna `PACKAGES_DISPATCH_DRY_RUN` (wypisz wybrany skrypt i wyjdź — testy).
Test: `test/unit/test_packages_dispatch.sh`; same funkcje `detect.sh` mają testy w
`test/unit/test_context_detect.sh`.

`packages/commons/prepare_workspace.sh` — wspólna, sourcowana funkcja `prepare_workspace()` (klon repo do
`~/workspace/<projekt>` + symlink `~/.<projekt>`; idempotentna, bez `pull`), używana przez cztery
`*/install.sh` (`install.sh` ma własny, minimalny klon inline — zob. wyżej).

Skrypty `*/install.sh` zawsze lecą z klona repo (`install.sh` → `initial_packages.sh`), więc biblioteki
sourcują zwykłym `source "$COMMONS_DIR/<plik>.sh"` (`COMMONS_DIR="$SCRIPT_DIR/../commons"`; pliki własne systemu —
`$SCRIPT_DIR/<plik>.sh`) — **bez** fallbacku „pobierz z GitHuba". Samodzielne
`curl … packages/<system>/install.sh | bash`, z pominięciem `install.sh`, nie jest już wspierane.

Ścieżki w tabeli są względem `packages/`.

| System | Instalacja | Aktualizacja | Menedżer |
|---|---|---|---|
| Ubuntu / Debian | `ubuntu/install.sh` | `ubuntu/update.sh` | apt + Docker |
| macOS | `mac/install.sh` | `mac/update.sh` | Homebrew |
| Vanilla OS 2 | `vanilla/install.sh` | `vanilla/update.sh` | apt (subsystem `apx`) + podman |
| RedHat / CentOS / Fedora | `redhat/install.sh` | `redhat/update.sh` | yum + Docker |

Wariant Vanilla: uruchamiany **wewnątrz subsystemu** (`vso shell` / `apx enter`), reużywa
`commons/apt_packages.sh`, używa `podman` + `podman-compose` zamiast Dockera, pomija
`add-apt-repository universe` (baza = Debian sid),
`vanilla/update.sh` sprząta martwe źródła apt (`docker.list`): fix `stale-sources` z rejestru (tylko Vanilla →
`packages/vanilla/fixes.d/005_stale_sources.sh`, `FIX_CONTEXTS=vanilla`, `FIX_RISK=high`). `fix_detect` (tylko odczyt):
`docker.list` istnieje i brak `docker`; `fix_apply`: `rm` listy + keyringu, `apt-get update`. Fix nie pyta o nic (stdin z `/dev/null`), więc
zgodę na `FIX_RISK=high` daje `apply_fixes` (`[y/N]`, domyślnie nie); `FIX_RISK=high` nigdy z crona.
`vanilla/{install,update}.sh` ustawiają `FIXES_DIRS="$COMMONS_DIR/fixes.d:$SCRIPT_DIR/fixes.d"`. Test: `test/unit/test_stale_sources_fix.sh`. Oba robią `apt-get full-upgrade`
(install: przed listą pakietów; update: zamiast `install --only-upgrade <lista>`), zawsze poprzedzony
`apply_fixes post-update` (fix `sysusers` z `vanilla/fixes.d/010_sysusers.sh`,
`FIX_PHASE=post-update`, `FIX_CONTEXTS=vanilla`): nowszy `systemd-sysusers` przez `apt-get download` + `dpkg -i`, zanim postinst pcscd
padnie na `u!`. `fix_detect` (tylko odczyt, bez sieci) zgłasza `detected` wyłącznie z dodatniego dowodu: `systemd-sysusers --version` < 257
**i** któryś plik `sysusers.d` ma modyfikator `!`; sam nowszy sysusers w repo to nie awaria (brak fałszywych alarmów). `apply_fixes` zawsze
`return 0`, a nieudany download/`dpkg -i` jest teraz `failed` w raporcie (wcześniej cichy). Test: `test/unit/test_sysusers_fix.sh`. Sid jest rolling, a częściowy upgrade zostawiał stare biblioteki przy nowych binarkach
(htop vs `libunwind8`: `undefined symbol: _Ux86_64_get_elf_filename`).

We wszystkich czterech `*/install.sh`: (1) `install_sdkman_tools` (commons) robi `source sdkman-init.sh` **i** wszystkie
`sdk install …` w podpowłoce z `set +eu` — wewnętrzny `sdkman-install.sh` sięga po niepodane argumenty (`unbound variable` pod `set -Eeuo
pipefail`); na Vanilli dodatkowo czyszczone są zmienne proxy przed SDKMAN (install: w `install_sdkman`, update: w podpowłoce wokół `update_sdkman_tools`); (2) `prepare_bashrc` robi `rm -f ~/.bashrc` + `cp szablon` zamiast `cat szablon > ~/.bashrc` (symlink na szablon
byłby obcięty przez `>`).

Claude Code: `install_claude` w każdym `*/install.sh` (po `install_gh`) i `update_claude` w
`*/update.sh` (po SDKMAN). Linux: `curl -fsSL https://claude.ai/install.sh | bash` przez
`verify_and_run_script` (brak sumy → zawsze pyta; odmowa = ostrzeżenie, `return 0`, nie przerywa `set -e`);
macOS: `brew install --cask claude-code`. Aktualizacja wszędzie `claude update`; brak `claude` → tylko `warn`.
Instalacja idempotentna (`command -v claude` / `$HOME/.local/bin/claude` / `brew list --cask`).

Naprawy systemowe (#144, krok 1 — szkielet): rejestr `packages/commons/fixes.d/` (1 fix = 1 plik `NNN_nazwa.sh`, kontrakt w
`fixes.d/README.md`; fix jednego systemu — `packages/<system>/fixes.d/`, dodatkowe katalogi przez `FIXES_DIRS`) i runner
`packages/commons/fixes_runner.sh` (`run_fixes <faza|all> [--check] [--only id,…] [--format text|tsv|json] [--allow-high]
[--strict]`). Każda funkcja fixa (`fix_detect` tylko odczyt, `fix_apply`, opcjonalnie `fix_verify`) leci w osobnym procesie
`bash` (stdin z `/dev/null`, `timeout`, bez `set -e`/`trap ERR` wołającego), więc jeden fix nie przerywa reszty. Stany `ok/na/
detected/fixed/failed/skipped/unknown` (`detected`/`failed` tylko z dodatniego dowodu, brak danych = `unknown`), kody 0/10/11/12;
bez `--check` i `--strict` zawsze `return 0`. Z crona wyłącznie `--check` (bez roota i sieci); `FIX_RISK=high` nigdy z crona.
Wejście dla crona/monitoringu (krok 7): `packages/fixes_check.sh` — funkcje `fixes_check [faza|all] [--only id,…] [--format text|tsv|json]` i `fixes_check_dirs`,
sourcowane albo uruchamiane wprost (`bash packages/fixes_check.sh`); zawsze `run_fixes --check`, kod 0/10/11/12 (2 = zły argument), kontekst i katalogi rejestru
wykrywane same (cron nie ma `$CONFIG_CONTEXT`). Nie dodaje wpisów cron — harmonogram ustawia użytkownik (`cron_add`). Test: `test/unit/test_fixes_check.sh`.
W rejestrze są fixy `dkms` (`fixes.d/010_dkms.sh`), `stale-sources` (`packages/vanilla/fixes.d/005_stale_sources.sh`), `sysusers`
(`packages/vanilla/fixes.d/010_sysusers.sh`) i `apt-gpg` (`fixes.d/020_apt_gpg.sh`). Skrypty nie wołają fixów po nazwie, tylko
`apply_fixes <faza>` z `packages/commons/fixes_apply.sh` (krok 6): kolejność i zakres wynikają z `FIX_PHASE`/`FIX_CONTEXTS` i numeru pliku.
`apply_fixes` robi `run_fixes <faza> --check`, pyta o zgodę `[y/N]` (domyślnie nie, EOF = nie) przy wykrytym `FIX_RISK=high`, potem
`run_fixes <faza> --only <reszta>` (`FIXES_TIMEOUT=900`, prefiks roota z `$SUDO` skryptu przez `FIXES_SUDO`), tłumaczy raport na `ok/warn`
i dopisuje martwe repo do `REPOS_DEAD`; zawsze `return 0`. Wymaga od skryptu `$SUDO`, `ok/warn/info` i (opcjonalnie) `REPOS_DEAD`.
`fixes_refresh_apt_log` robi jeden `apt-get update` do `FIX_APT_UPDATE_LOG` (z niego czyta `apt-gpg`). Kolejność w `{ubuntu,vanilla}/update.sh`:
`fixes_refresh_apt_log` → `apply_fixes pre-apt` → `update_apt_packages` (Vanilla: wewnątrz `apply_fixes post-update` przed `full-upgrade`) →
`apply_fixes post-apt`; `ubuntu/install.sh`: `fixes_refresh_apt_log` → `apply_fixes pre-apt` → `safe_apt_install` → `apply_fixes post-apt`;
`vanilla/install.sh`: `fixes_refresh_apt_log` → `pre-apt` → `post-update` (przed `full-upgrade`) → instalacja listy → `post-apt` (bez tego uszkodzony pakiet `*-dkms`
blokował `apt-get install` w instalatorze). Dispatchery root-owe (`install.sh`, `initial_packages.sh`, `update_packages.sh`) tylko wybierają skrypt systemu — naprawy żyją w `packages/<system>/`. Test pilnujący podpięcia i kolejności: `test/unit/test_fixes_wiring.sh`. Testy: `test/unit/test_fixes_runner.sh`
(syntetyczne fixy w `mktemp`), `test/unit/test_fixes_apply.sh` (zgoda, raport, `REPOS_DEAD`, odporność na `set -Eeuo pipefail`),
`test/unit/test_fixes_registry.sh` (lint: metadane, unikalne ID, `fix_detect` bez sudo/sieci/zapisu).

DKMS: fix `dkms` w rejestrze (`packages/commons/fixes.d/010_dkms.sh`, `FIX_PHASE="pre-apt post-apt"`, `FIX_CONTEXTS=debian`,
root). `fix_detect` (tylko odczyt) wskazuje pakiety `*-dkms` ze statusem `iF/iH/iU/iW/iT` w `dpkg-query` — dodatni dowód;
`rc`/`un` nie są uszkodzeniem i nie są ruszane; brak `dkms` = `na`. `fix_apply` naprawia pakiety `*-dkms` (np. `v4l2loopback-dkms`:
`Error! DKMS tree already contains …`): `dkms remove <moduł>/<wersja> --all` dla katalogów `/usr/src` pakietu, potem
`dpkg --configure <pkg>` (nie apt — ten sam błąd przy każdym wywołaniu); po `dkms remove` fix sprawdza `dkms status` — gdy wpis został (drzewo trzyma kernele już odinstalowane, `Missing some built modules`), czyści `/var/lib/dkms/<moduł>/<wersja>` i wiszące `kernel-*` ręcznie (`DKMS_TREE_DIR` dla testów); błędy `dkms`/`dpkg` są logowane, nie połykane. `fix_verify` sprawdza, że nic nie zostało w `iF`.
Fix ma `FIX_PHASE="pre-apt post-apt"`, więc `apply_fixes` woła go przed i po `update_apt_packages` (jedno miejsce zamiast dwóch
ręcznych wywołań). Bez fałszywych alarmów w monitoringu (`--check` bez roota). Test: `test/unit/test_dkms_fix.sh` (mocki poleceń w PATH).

Klucze GPG apt: fix `apt-gpg` (`packages/commons/fixes.d/020_apt_gpg.sh`, `FIX_PHASE=pre-apt`, `FIX_CONTEXTS=debian`, root) naprawia
brakujące (`NO_PUBKEY`) i wygasłe klucze repo apt; klucz pobiera z keyservera do izolowanego keyringu i przypina `signed-by=` do pliku
źródła — nigdy `trusted.gpg.d`. `fix_detect` **nie woła `apt-get update`**: dowodem jest log ostatniego update'u
(`FIX_APT_UPDATE_LOG`, domyślnie `~/.cache/koziolek-configuration/apt-update.log`, ważny 7 dni) oraz wygasłe `imported-*.gpg` (offline,
`gpg --with-colons`); bez logu i bez wygasłych kluczy stan to `unknown`, nie `ok`. Martwe repo (404) idzie przez `fix_note_dead_repo`
(`#dead_repo` w raporcie), nie zmienia stanu. Log zapisuje `fixes_refresh_apt_log` (wołane w `{ubuntu,vanilla}/update.sh`
przed `apply_fixes pre-apt`); `apply_fixes` uzupełnia `REPOS_DEAD` z raportu. Dwie implementacje zostają (decyzja z #144): powłokowa
`096_function_apt_trust.sh` (interaktywna, `are_you_sure`, i18n) i ta bootstrapowa (bez pytań) — różnią się UX i zależnościami; zmiana
algorytmu wymaga poprawki w obu. Test: `test/unit/test_gpg_fix.sh`.

calibre: `install_calibre` w każdym `*/install.sh` (po `install_claude`) i `update_calibre` w
`*/update.sh` (po `update_claude`). Linux (ubuntu/vanilla/redhat): oficjalny instalator binarny
`wget -nv -O- https://download.calibre-ebook.com/linux-installer.sh | $SUDO sh /dev/stdin` (strona calibre
odradza pakiety dystrybucji; aktualizacja = ponowne uruchomienie instalatora; bez sumy kontrolnej, błąd =
ostrzeżenie, `return 0`). macOS: oficjalnie ręczny DMG, więc `brew install --cask calibre` /
`brew upgrade --cask calibre` (w update, gdy cask nie jest zainstalowany, `brew install`). Instalacja
idempotentna (`command -v calibre`); `update_calibre` nie sprawdza obecności — instaluje, gdy brak.
Przed instalatorem oba wołają `calibre_install_deps` (`packages/commons/calibre_deps.sh`): `libxcb-cursor0` (apt) / `xcb-util-cursor` (yum) —
bez tej biblioteki Qt nie ładuje wtyczki `xcb` i GUI nie startuje (na Vanilla OS jej nie ma w standardzie); błąd = ostrzeżenie. Test: `test/unit/test_calibre_deps.sh`.

git-bug: `install_git_bug` w `{ubuntu,vanilla,redhat}/install.sh` (po `install_calibre`) i `update_git_bug` w
`{ubuntu,vanilla,redhat}/update.sh` (po `update_calibre`), wspólne `packages/commons/git_bug.sh` (w install sourcowane
przez `$COMMONS_DIR`). Brak repo apt/yum → tarball z GitHub Releases,
**bez sudo**: binarka w `${GIT_BUG_INSTALL_DIR:-~/.local/bin}` (jak `claude`/`asdf`), więc aktualizacja działa z crona
użytkownika. Najnowsza wersja z przekierowania `…/releases/latest` (bez API i limitu), zainstalowana z drugiego pola
`git-bug version`; równe = brak pobierania, brak/starsza = pobranie + weryfikacja sha256 z `checksums.txt` + atomowa
podmiana. Z tarballa idą też strony man (`man/*.1` → `$GIT_BUG_DATA_DIR/man/man1`) i bash completion
(`completion/bash/git-bug` → `$GIT_BUG_DATA_DIR/bash-completion/completions/git-bug`), też bez sudo;
`GIT_BUG_DATA_DIR` domyślnie `${XDG_DATA_HOME:-~/.local/share}`. „Aktualny" = wersja równa **i** man + completion na
miejscu — inaczej tarball jest pobierany ponownie i dokumenty uzupełniane; brak `man/`/`completion/` w wydaniu =
ostrzeżenie, binarka i tak się instaluje. Jedna ścieżka dla instalacji i aktualizacji (`update_git_bug` instaluje, gdy
brak). Nieinteraktywne, zawsze `return 0` (błąd = ostrzeżenie). Architektury amd64/arm64. macOS: `git-bug` w
`brew_packages.sh` (install + upgrade robią istniejące pętle). Alias `gb='git bug'` w `bash/bash_aliases.sh` definiowany
tylko gdy `git-bug` jest w PATH i `gb` nie jest już innym poleceniem (nic nie cieniuje). Test: `test/unit/test_git_bug.sh`.

Skille Claude Code: `link_claude_skills` (wspólne `packages/commons/link_claude_skills.sh`, sourcowane w czterech
`*/install.sh` przez `$COMMONS_DIR`; wołane zaraz po
`install_claude`) linkuje każdy `<klaudyna>/skills/<nazwa>/` do `~/.claude/skills/<nazwa>`, dzięki czemu
skille są wspólne między maszynami. Repo `klaudyna` (`$KLAUDYNA_DIR`, domyślnie
`~/workspace/tools/klaudyna` — to samo miejsce co `install_lib` w `bash_customs.sh`) klonowane bez promptu,
gdy brak; brak dostępu (repo prywatne) = ostrzeżenie i `return 0`. Idempotentne; istniejący prawdziwy
katalog w `~/.claude/skills` (np. `synced`) zostaje nietknięty. Test: `test/unit/test_link_claude_skills.sh`.

Lista narzędzi sdkman/asdf: `packages/commons/sdk_tools.sh` — same dane, bez efektów ubocznych przy sourcowaniu. `SDKMAN_TOOLS` (nazwy dla
`sdk install`; **nie** `SDKMAN_CANDIDATES` — tak SDKMAN nazywa własną tablicę wszystkich dostępnych kandydatów i `sdkman-init.sh` ją nadpisuje, a pętla zainstalowałaby cały katalog; helper dodatkowo robi zrzut listy przed `source`) oraz `ASDF_TOOLS` (wpisy `nazwa|url pluginu|wersja`, url pusty = plugin z rejestru asdf, wersja `latest` lub konkretna). Obecny stan:
sdkman `java maven mvnd`, asdf tylko toolchainy: `rust golang ghc cabal` (`ghc` i `cabal` z jednego pluginu ghcup, `sestrella/asdf-ghcup`). Narzędzia nimi instalowane — niżej, `lang_packages.sh` (#172). Dodanie wpisu do listy wystarcza — `*/install.sh` i `*/update.sh` (#167) nie mają już narzędzi wpisanych na sztywno.
Iterują po niej helpery z `packages/commons/sdk_tools_apply.sh` (sourcowane po `verify_and_run_script.sh` w install, po `calibre_deps.sh` w update; w `mac/update.sh` po `brew_packages.sh`):
`install_sdkman_tools` / `update_sdkman_tools` (`sdk install`; w update `sdk upgrade` dla zainstalowanych, brakujący jest instalowany; podpowłoka `set +eu` + `trap - ERR`;
`SDKMAN_DIR`) oraz `install_asdf_tools` / `update_asdf_tools` (`plugin add` tylko gdy pluginu brak → `install` → `asdf set -u`, a dla asdf < 0.16 `asdf global` → `reshim`;
update dodatkowo `plugin update`; `ASDF_BIN`). Błąd jednego narzędzia = ostrzeżenie z podsumowaniem, reszta leci dalej; brak SDKMAN-a/asdf = ostrzeżenie; zawsze `return 0`.
Kolejność w install: `install_asdf` → `install_asdf_tools` → `install_lang_packages` (potrzebuje toolchainów z asdf) → `install_sdkman` (woła `install_sdkman_tools`; mac także gdy SDKMAN już jest);
w update: `update_asdf` → `update_asdf_tools` → `update_lang_packages`, `update_sdkman` woła `update_sdkman_tools` po `sdk selfupdate`.
Testy: `test/unit/test_sdk_tools_apply.sh` (mocki `sdk` w fałszywym `sdkman-init.sh` i `asdf`), `test/unit/test_sdk_tools_wiring.sh` (podpięcie i kolejność w czterech systemach).
Szablony `bash/templates/.sdkman.template` (odpowiednik `sdk current` z `$HOME`: linie `kandydat=wersja`, format `.sdkmanrc`) i `bash/templates/.tool-versions.template` (kopia `~/.tool-versions`) odzwierciedlają
konfigurację z `$HOME`; instalatory ich jeszcze nie wdrażają. Test: `test/unit/test_sdk_tools.sh`.

Pakiety instalowane toolchainami: `packages/commons/lang_packages.sh` (wzór: `apt_packages.sh`; same dane) — `CARGO_PACKAGES` (`difftastic|difft`, `linthis`),
`GO_PACKAGES` (`mvdan.cc/sh/v3/cmd/shfmt@latest`), `CABAL_PACKAGES` (`ShellCheck`). Wpis `pakiet` albo `pakiet|binarka` (binarka = sprawdzenie „już jest”; domyślnie nazwa małymi
literami, dla go ostatni człon ścieżki). Dodanie wpisu wystarcza. Helpery z `packages/commons/lang_packages_apply.sh` (sourcowane zaraz po `sdk_tools_apply.sh`):
`install_{cargo,go,cabal}_packages` / `update_{cargo,go,cabal}_packages` oraz wrappery `install_lang_packages` / `update_lang_packages`. Toolchainy wołane przez `asdf exec`
z shimami asdf w PATH (cabal szuka `ghc` w PATH); install pomija pakiet, którego binarka jest, update instaluje zawsze (też brakujące). Binarki go i cabal lądują w
`${LANG_PACKAGES_BIN_DIR:-~/.local/bin}` (`GOBIN`, `cabal --installdir --install-method=copy --overwrite-policy=always`), więc są w PATH bez reshimu; cargo — jak dotąd w katalogu asdf + `reshim`.
Brak asdf albo toolchaina = ostrzeżenie i pominięcie listy; błąd pakietu = ostrzeżenie z podsumowaniem; zawsze `return 0`. Indeks Hackage (`cabal update`) raz na przebieg i tylko gdy coś się instaluje.
Kompilatory i biblioteki do budowy toolchainów (ghc z ghcup: gcc, gmp, ncurses, libffi…) to tablica `build_libs` w `apt_packages.sh` i `yum_packages.sh` (wpięta w listy pakietów
`{ubuntu,vanilla,redhat}/{install,update}.sh`); na macOS wystarczą narzędzia Xcode CLT, więc brew nie ma odpowiednika.
Test: `test/unit/test_lang_packages.sh` (lista + mock `asdf`); wiring w `test_sdk_tools_wiring.sh`.

cargo zawsze z `--locked` (difftastic, linthis…): bez tego cargo dobiera najnowsze zależności semver, które co jakiś czas
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
