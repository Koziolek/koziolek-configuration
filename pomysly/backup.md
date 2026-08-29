# Procedura backupu — stacja koziolek

**Data:** 2026-06-12  
**System:** Ubuntu 24.04.4 LTS, ASUS TRX40-PRO S, 256 GB RAM

---

## Dyski i co jest na nich

| Urządzenie     | Punkt montowania               | Rozmiar | Użyte  | Zawartość                     |
|----------------|--------------------------------|---------|--------|-------------------------------|
| `/dev/nvme1n1` | `/` (system + home)            | 916 GB  | 434 GB | system, `~`, projekty         |
| `/dev/nvme2n1` | `/media/koziolek/storage`      | 916 GB  | 648 GB | storage (media, dane)         |
| `/dev/nvme0n1` | `/media/koziolek/steam-lib`    | 1,8 TB  | 1,7 TB | biblioteka Steam — NIE backup |
| `/dev/sda1`    | `/media/koziolek/My Passport1` | 466 GB  | 201 GB | NTFS, potencjalny cel local   |

---

## Narzędzia

### Główne: `restic`

```bash
sudo apt install restic
```

**Dlaczego:** inkrementalny, deduplikacja bloków, szyfrowanie AES-256 na poziomie repo,
wiele backendów (local, SFTP, S3, Backblaze B2, rclone), weryfikacja integralności
(`restic check`), przycinanie (`restic forget --prune`).

### Uzupełniające: `rsync`

Dla lokalnego szybkiego kopiowania na WD My Passport (bez szyfrowania, bez wersjonowania).

```bash
# instalacja (jest domyślnie)
rsync --version
```

### Docker volumes: `docker run --rm` + `tar`

Natywna metoda — nie wymaga instalacji dodatkowych narzędzi.

---

## Cele backupu

### Cel A — Backblaze B2 (zdalny, szyfrowany)

Dual ISP (T-Mobile + Finemedia) → backup chmurowy sensowny. Backblaze B2 = tanie,
restic ma natywną obsługę.

```bash
# Konfiguracja repo (jednorazowo):
export B2_ACCOUNT_ID= <id>
export B2_ACCOUNT_KEY=<key>
restic -r b2:koziolek-backup init
```

### Cel B — WD My Passport `/dev/sda1` (lokalny)

466 GB, 265 GB wolnych. NTFS = brak uprawnień unix → tylko pliki bez metadanych uprawnień.
Używać przez `restic` (binary blobs, nie raw files) — omija problem NTFS.

```bash
restic -r /media/koziolek/My\ Passport1/restic-repo init
```

**Uwaga:** Passport musi być podmontowany. Skrypt `scripts/dysk/05-mount-my-passport.sh`
gdy automount zawiedzie.

---

## Zakres — co backupować

### Tier 1 — KRYTYCZNE (codziennie)

Utrata = realna strata pracy lub danych.

| Ścieżka                      | Zawartość                 | Rozmiar          |
|------------------------------|---------------------------|------------------|
| `~/.ssh/`                    | klucze SSH                | 152 KB           |
| `~/.gnupg/`                  | klucze GPG                | 12 KB            |
| `~/workspace/`               | repozytoria git, projekty | 33 GB            |
| `/etc/`                      | cała konfiguracja systemu | 17 MB            |
| Docker volumes (bazy danych) | patrz sekcja Docker niżej | ~440 MB          |
| **Tier 1 łącznie**           |                           | **~33,5 GB raw** |

Docker volumes do backupu (aktywne projekty z danymi):

- `ghost-track_db_data` — baza danych ghost-track
- `home-db` (wolumin pgadmin/home-db) — lokalna baza
- `nexus` — repozytorium Maven/npm

```bash
# Przykład: backup woluminu ghost-track_db_data
docker run --rm \
  -v ghost-track_db_data:/data \
  -v /media/koziolek/My\ Passport1/docker-volumes:/backup \
  alpine tar czf /backup/ghost-track_db_data-$(date +%F).tar.gz -C /data .
```

### Tier 2 — WAŻNE (tygodniowo)

Utrata = kilka godzin odtwarzania.

| Ścieżka                                                 | Zawartość                         | Rozmiar       |
|---------------------------------------------------------|-----------------------------------|---------------|
| `~/.config/JetBrains/`                                  | ustawienia IDE (IntelliJ, skróty) | 4,9 GB        |
| `~/.local/share/JetBrains/IntelliJIdea2026.1`           | dane bieżącej wersji IDE          | 4,2 GB        |
| `~/.local/share/claude/`                                | historia rozmów                   | 1,9 GB        |
| `~/.config/1Password/`, `~/.config/Signal/`             | menadżer haseł, wiadomości        | ~94 MB        |
| `~/.config/Microsoft/`                                  | VS Code i inne ustawienia MS      | 521 MB        |
| `/etc/systemd/`, `/etc/sysctl.d/`, `/etc/udev/rules.d/` | override systemd, sysctl, udev    | w /etc/ Tier1 |
| **Tier 2 łącznie**                                      |                                   | **~11,6 GB**  |

> Wykluczenia z Tier 2: `~/.config/Slack` (1,9 GB), `~/.config/discord` (1,3 GB),
> `~/.config/google-chrome` (100 MB), `~/.local/share/Steam` (6,7 GB),
> `~/.local/share/flatpak` (1,3 GB), `~/.local/share/pnpm` (890 MB) — cache/Electron, odbudowują się.

### Tier 3 — OPCJONALNE (miesięcznie / na żądanie)

| Ścieżka                              | Zawartość            | Uwagi                                    |
|--------------------------------------|----------------------|------------------------------------------|
| `/media/koziolek/storage/` (wybrane) | dane z dysku storage | tylko katalogi z unikalnymi danymi       |
| `~/.cache/spotify/`                  | biblioteka offline   | 8,5–11 GB, duże — tylko gdy jest miejsce |

---

## Wykluczenia — co NIE backupować

```
/media/koziolek/steam-lib/    # 1,7 TB — reinstaluj przez Steam
~/.cache/JetBrains/           # cache IDE — odbudowuje się
~/.cache/go-build/            # cache kompilacji Go
~/.cache/uv/                  # cache pip/uv
~/.cache/mozilla/             # cache Firefox
/tmp/                         # tymczasowe
/var/tmp/
/var/cache/apt/               # odbudowuje się przez apt
/var/lib/docker/              # obrazy Docker — pulluj ponownie
/swapfile                     # plik wymiany
/proc/ /sys/ /dev/            # pseudosystemy plików
```

---

## Częstotliwość

| Tier       | Częstotliwość   | Metoda         | Cel           |
|------------|-----------------|----------------|---------------|
| Tier 1     | **codziennie**  | restic         | B2 + Passport |
| Tier 2     | **tygodniowo**  | restic         | B2 + Passport |
| Tier 3     | **miesięcznie** | rsync / restic | Passport      |
| Docker vol | **codziennie**  | docker+tar     | Passport      |

---

## Polityka retencji

```bash
# Zachowaj: 7 dziennych, 4 tygodniowe, 3 miesięczne
restic -r b2:koziolek-backup forget --prune \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 3
```

---

## Przykładowe komendy

### Backup Tier 1 (codziennie)

```bash
#!/usr/bin/env bash
# backup-daily.sh

REPO="b2:koziolek-backup"
PASSWORD_FILE="/root/.restic-password"

restic -r "$REPO" --password-file "$PASSWORD_FILE" backup \
  ~/.ssh \
  ~/.gnupg \
  ~/workspace \
  /etc \
  --exclude ~/.cache \
  --exclude ~/workspace/FIX/logs \
  --tag tier1,daily

restic -r "$REPO" --password-file "$PASSWORD_FILE" forget --prune \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 3 \
  --tag tier1
```

### Backup Tier 2 (tygodniowo)

```bash
restic -r "$REPO" --password-file "$PASSWORD_FILE" backup \
  ~/.config \
  ~/.local/share \
  --exclude ~/.cache \
  --exclude ~/.local/share/Trash \
  --tag tier2,weekly
```

### Weryfikacja

```bash
restic -r "$REPO" --password-file "$PASSWORD_FILE" check
restic -r "$REPO" --password-file "$PASSWORD_FILE" snapshots
```

### Przywracanie pojedynczego pliku

```bash
restic -r "$REPO" restore latest --target /tmp/restore --include /home/koziolek/.ssh/id_ed25519
```

---

## Automatyzacja przez cron (root)

```bash
sudo crontab -e
```

```cron
# Backup dzienny Tier 1 — 03:00
0 3 * * * /home/koziolek/workspace/FIX/scripts/backup/01-backup-daily.sh >> /var/log/restic-daily.log 2>&1

# Backup tygodniowy Tier 2 — niedziele 04:00
0 4 * * 0 /home/koziolek/workspace/FIX/scripts/backup/02-backup-weekly.sh >> /var/log/restic-weekly.log 2>&1
```

---

## Priorytety wdrożenia

1. **Najpierw:** zainstaluj `restic`, utwórz repo B2 i lokalne na Passporcie
2. **Zabezpiecz hasło repo** w `/root/.restic-password` (chmod 400)
3. **Przetestuj przywracanie** zanim uznasz backup za działający
4. **Napisz skrypty** w `scripts/backup/` (01-backup-daily.sh, 02-backup-weekly.sh)
5. **Dodaj cron** po weryfikacji działania skryptów

---

## Szacunek rozmiaru kopii

| Tier                       | Raw        | Po dedup restic |
|----------------------------|------------|-----------------|
| Tier 1 (codziennie)        | 33,5 GB    | ~20–25 GB       |
| Tier 2 (tygodniowo)        | 11,6 GB    | ~9 GB           |
| Docker volumes             | 440 MB     | ~440 MB         |
| **Pierwsza kopia łącznie** | **~45 GB** | **~30 GB**      |

Dzienny przyrost Tier 1: **1–5 GB** (zależnie od aktywności w workspace).  
WD My Passport (265 GB wolnych) mieści ~8 pełnych snapshotów przed pruningiem.  
Backblaze B2 przy ~30 GB: ~$0.17/miesiąc storage.

---

## Czego NIE ma (luki do uzupełnienia)

- Brak offsite poza B2 (np. SFTP na VPS) — rozważyć przy danych szczególnie krytycznych
- `/media/koziolek/storage/` — 648 GB, nieznana zawartość; wymaga inwentaryzacji przed decyzją o backupie
- Docker volumes pansa — sprawdzić czy mają dane produkcyjne czy tylko cache buildów
