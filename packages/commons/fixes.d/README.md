# Rejestr napraw systemowych (`fixes.d`)

1 fix = 1 plik `NNN_nazwa.sh` (numer wyznacza kolejność). Plik **niczego nie wykonuje przy
source'owaniu** — deklaruje metadane i funkcje. Uruchamia je runner `packages/commons/fixes_runner.sh`
(`run_fixes <faza|all> [--check] [--only id,…] [--format text|tsv|json] [--allow-high] [--strict]`),
każdą funkcję w osobnym procesie (stdin z `/dev/null`, `timeout`, bez dziedziczenia `set -e`/`trap ERR`).

Katalog `commons/fixes.d/` trzyma naprawy wspólne dla kilku systemów; naprawa jednego systemu leży
w `packages/<system>/fixes.d/` (regułę podziału opisuje CLAUDE.md, sekcja „Bootstrap pakietów”).
Dodatkowe katalogi rejestru: zmienna `FIXES_DIRS` (rozdzielone `:`).

## Kontrakt pliku

| Zmienna | Znaczenie |
|---|---|
| `FIX_ID` | stabilny identyfikator (`[a-z0-9][a-z0-9_-]*`, unikalny) — po nim parsuje monitoring |
| `FIX_DESC` | jedna linia opisu |
| `FIX_PHASE` | jedna lub kilka z: `pre-apt` `post-update` `post-apt` |
| `FIX_CONTEXTS` | `all` albo nazwy z łańcucha kontekstów (`context_chain`), np. `debian` (ubuntu, vanilla, wsl) |
| `FIX_NEEDS_ROOT` | `0` / `1` |
| `FIX_RISK` | `low` / `high` (`high` tylko z `--allow-high`, nigdy z crona) |

Funkcje:

- `fix_detect` — **tylko odczyt: bez sieci, `sudo` i zapisu**. Kod: `0` = wykryto problem, `1` = zdrowo,
  `2` = nie dotyczy, inny/timeout = `unknown`. `detected` wolno zwrócić wyłącznie z dodatniego dowodu
  (np. `iF` w `dpkg-query`); brak danych to `unknown`, nigdy `detected`.
- `fix_apply` — naprawa; root przez `$SUDO` (w `fix_detect` i przy `--check` to `fix_denied`). Bez pytań
  interaktywnych (stdin to `/dev/null`).
- `fix_verify` — opcjonalne potwierdzenie po `fix_apply`; bez niego kod `0` z `fix_apply` = `fixed`.

Helpery w fixie: `fix_log <format printf> [arg…]`, `fix_detail <tekst>` (szczegół do raportu),
`fix_note_dead_repo <repo>`.

## Wynik

Stany: `ok` / `na` / `detected` / `fixed` / `failed` / `skipped` / `unknown`. Kody `run_fixes`:
`0` / `10` (`--check`: wykryto) / `11` (apply: nieudane) / `12` (tylko `unknown`/`skipped`). Bez `--check`
i `--strict` funkcja zawsze zwraca `0`. Raport `fixes-report v1`: TSV (`fix_id state phase risk detail`,
nagłówek `#fixes-report v1`) albo JSON Lines.

Lint rejestru: `fixes_lint [katalog…]` (test: `test/unit/test_fixes_registry.sh`).

## Wołanie ze skryptów

`install.sh`/`update.sh` nie wołają fixów po nazwie, tylko `apply_fixes <faza>` z `packages/commons/fixes_apply.sh` (po
`fixes_refresh_apt_log`, który zapisuje log `apt-get update` dla fixa `apt-gpg`). `apply_fixes` robi `run_fixes <faza> --check`,
przy wykrytym `FIX_RISK=high` pyta `[y/N]` (domyślnie nie) i dopiero potem uruchamia naprawy bez pytań w samym fixie. Skrypt musi mieć
`$SUDO` oraz `ok`/`warn`/`info`; opcjonalnie tablicę `REPOS_DEAD` i `FIXES_DIRS` (dla Vanilli: `commons/fixes.d` + `vanilla/fixes.d`).
