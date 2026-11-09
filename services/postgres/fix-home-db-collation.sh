#!/usr/bin/env bash
# fix-home-db-collation.sh - zgłoszenie #206 / #201.
# Uruchamiane NA HOŚCIE. Kroki: kopia -> stan przed -> odtworzenie home-db na
# postgres:17.5-bookworm -> weryfikacja glibc -> REINDEX + REFRESH COLLATION VERSION
# dla baz z rozjazdem -> restart zależnych kontenerów -> weryfikacja końcowa.
#
# Użycie: fix-home-db-collation.sh [--dry-run] [--yes] [--skip-backup] [--no-restart-deps]
#   --dry-run          tylko odczyt: stan baz i lista baz z rozjazdem, nic nie zmienia
#   --yes              bez pytania o potwierdzenie
#   --skip-backup      pomija pg_dumpall (nie zalecane)
#   --no-restart-deps  nie restartuje sonarqube/jenkins/pgadmin
# Zmienne: HOME_DB_CONTAINER (home-db), EXPECTED_GLIBC (2.36), BACKUP_FILE,
#   COMPOSE_FILE (domyślnie $SERVICES_CONFIGURATION_DIR/docker/docker-compose.yaml),
#   DOCKER_COMPOSE (domyślnie "docker compose"), DEPENDENTS ("sonarqube jenkins pgadmin"),
#   WAIT_TIMEOUT (120 s).
# Compose potrzebuje zmiennych z services/main.sh (POSTGRES_DATA itd.) - uruchom
# z powłoki, w której są wyeksportowane.
set -Eeuo pipefail

CONTAINER="${HOME_DB_CONTAINER:-home-db}"
EXPECTED_GLIBC="${EXPECTED_GLIBC:-2.36}"
COMPOSE_FILE="${COMPOSE_FILE:-${SERVICES_CONFIGURATION_DIR:-$HOME/workspace/git-configuration/services}/docker/docker-compose.yaml}"
DEPENDENTS="${DEPENDENTS:-sonarqube jenkins pgadmin}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-120}"
BACKUP_FILE="${BACKUP_FILE:-$HOME/backup-home-db-$(date +%F-%H%M).sql}"
read -r -a COMPOSE <<<"${DOCKER_COMPOSE:-docker compose}"

DRY_RUN=0 ASSUME_YES=0 SKIP_BACKUP=0 RESTART_DEPS=1
for arg in "$@"; do
    case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes) ASSUME_YES=1 ;;
    --skip-backup) SKIP_BACKUP=1 ;;
    --no-restart-deps) RESTART_DEPS=0 ;;
    -h | --help)
        sed -n '2,16p' "$0"
        exit 0
        ;;
    *)
        echo "Nieznana opcja: $arg" >&2
        exit 2
        ;;
    esac
done

step() { printf '\n== %s\n' "$*"; }
die() {
    printf 'BŁĄD: %s\n' "$*" >&2
    exit 1
}
trap 'die "przerwano w linii $LINENO (polecenie: $BASH_COMMAND)"' ERR

compose() { "${COMPOSE[@]}" -f "$COMPOSE_FILE" "$@"; }

# psql w kontenerze: pierwszy argument = baza, reszta = argumenty psql.
# Użytkownik z $POSTGRES_USER kontenera - bez haseł w historii powłoki.
pg() {
    local db="$1"
    shift
    docker exec -i "$CONTAINER" sh -c \
        'db=$1; shift; exec psql -U "$POSTGRES_USER" -d "$db" -X -v ON_ERROR_STOP=1 "$@"' _ "$db" "$@"
}

show_status() {
    pg postgres -c "SELECT datname, datcollversion, pg_database_collation_actual_version(oid) AS actual
                    FROM pg_database ORDER BY 1;"
}

mismatched_dbs() {
    pg postgres -At -c "SELECT datname FROM pg_database
                        WHERE datname <> 'template0'
                          AND datcollversion IS DISTINCT FROM pg_database_collation_actual_version(oid)
                        ORDER BY 1;"
}

wait_ready() {
    local waited=0
    until docker exec "$CONTAINER" sh -c 'pg_isready -q -U "$POSTGRES_USER"' 2>/dev/null; do
        ((waited >= WAIT_TIMEOUT)) && die "$CONTAINER nie wstał w ${WAIT_TIMEOUT}s"
        sleep 2
        waited=$((waited + 2))
    done
}

glibc_version() {
    docker exec "$CONTAINER" ldd --version 2>&1 | awk 'NR==1 {print $NF}'
}

# --- 0. Preflight -------------------------------------------------------------
step "0. Sprawdzenia wstępne"
command -v docker >/dev/null || die "brak docker w PATH"
docker inspect "$CONTAINER" >/dev/null 2>&1 || die "brak kontenera $CONTAINER"
[[ -f "$COMPOSE_FILE" ]] || die "brak pliku compose: $COMPOSE_FILE (ustaw COMPOSE_FILE)"
compose config --services >/dev/null || die "compose config nie działa - wyeksportuj zmienne z services/main.sh"
compose config --services | grep -qx home-db || die "serwisu home-db nie ma w $COMPOSE_FILE"
wait_ready
echo "kontener: $CONTAINER, compose: $COMPOSE_FILE, glibc w kontenerze: $(glibc_version)"

if ((DRY_RUN)); then
    step "DRY-RUN: stan baz (odczyt)"
    show_status
    echo "bazy z rozjazdem wersji collation:"
    mismatched_dbs | sed 's/^/  - /'
    [[ "$(glibc_version)" == "$EXPECTED_GLIBC" ]] || echo "UWAGA: kontener ma glibc $(glibc_version), oczekiwane $EXPECTED_GLIBC (obraz bookworm jeszcze niewdrożony)"
    exit 0
fi

if ((! ASSUME_YES)); then
    read -r -p "Zrobić kopię, odtworzyć $CONTAINER na bookworm i naprawić indeksy? [t/N] " ans
    [[ "$ans" =~ ^[tTyY]$ ]] || die "anulowano"
fi

# --- 1. Kopia zapasowa --------------------------------------------------------
if ((SKIP_BACKUP)); then
    step "1. Kopia zapasowa POMINIĘTA (--skip-backup)"
else
    step "1. Kopia zapasowa -> $BACKUP_FILE"
    (
        umask 077
        docker exec "$CONTAINER" sh -c 'pg_dumpall -U "$POSTGRES_USER"' >"$BACKUP_FILE"
    ) || die "pg_dumpall nie powiódł się (plik: $BACKUP_FILE)"
    [[ -s "$BACKUP_FILE" ]] || die "kopia pusta: $BACKUP_FILE"
    tail -n 3 "$BACKUP_FILE" | grep -q "PostgreSQL database cluster dump complete" ||
        die "kopia niekompletna (brak stopki pg_dumpall): $BACKUP_FILE"
    ls -lh "$BACKUP_FILE"
fi

# --- 2. Stan przed ------------------------------------------------------------
step "2. Stan przed zmianą"
show_status

# --- 3. Odtworzenie kontenera na nowym obrazie --------------------------------
# up -d home-db wprost, NIE start_services (ten woła prepare_key = nowy sekret Nexusa).
step "3. Odtworzenie $CONTAINER (pull + up -d)"
compose pull home-db
compose up -d home-db
wait_ready
got="$(glibc_version)"
[[ "$got" == "$EXPECTED_GLIBC" ]] ||
    die "glibc w kontenerze to $got, oczekiwane $EXPECTED_GLIBC - obraz nie jest bookworm; przerywam przed naprawą indeksów"
echo "OK: glibc $got"

# --- 4. Stan po wymianie obrazu -----------------------------------------------
step "4. Stan po wymianie obrazu"
show_status

# --- 5. Naprawa baz z rozjazdem: REINDEX, potem REFRESH ------------------------
# REFRESH COLLATION VERSION sam indeksów nie naprawia, więc zawsze po REINDEX.
step "5. REINDEX + REFRESH COLLATION VERSION dla baz z rozjazdem"
mapfile -t todo < <(mismatched_dbs)
if ((${#todo[@]} == 0)); then
    echo "brak baz z rozjazdem - nic do naprawy"
fi
for db in "${todo[@]}"; do
    echo "-- $db: REINDEX DATABASE"
    pg "$db" -c "REINDEX DATABASE \"$db\";"
    echo "-- $db: REFRESH COLLATION VERSION"
    pg postgres -c "ALTER DATABASE \"$db\" REFRESH COLLATION VERSION;"
done

# --- 6. Restart zależnych kontenerów -------------------------------------------
if ((RESTART_DEPS)); then
    step "6. Restart zależnych: $DEPENDENTS"
    existing="$(compose config --services)"
    to_restart=()
    for s in $DEPENDENTS; do
        if grep -qx "$s" <<<"$existing"; then to_restart+=("$s"); else echo "pomijam $s (brak w compose)"; fi
    done
    ((${#to_restart[@]} == 0)) || compose restart "${to_restart[@]}"
else
    step "6. Restart zależnych pominięty (--no-restart-deps)"
fi

# --- 7. Weryfikacja końcowa ---------------------------------------------------
step "7. Weryfikacja końcowa"
show_status
left="$(mismatched_dbs)"
if [[ -n "$left" ]]; then
    printf 'Rozjazd nadal w:\n%s\n' "$left" >&2
    die "nie wszystkie bazy zgodne"
fi
echo "OK: wszystkie bazy zgodne (2.36 | 2.36). Zamknij #206 i #201."
[[ -z "${BACKUP_FILE:-}" || $SKIP_BACKUP -eq 1 ]] || echo "Kopia: $BACKUP_FILE (usuń, gdy niepotrzebna - zawiera całą zawartość baz)"
