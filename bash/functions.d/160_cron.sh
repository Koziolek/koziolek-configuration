#!/usr/bin/env bash
#
# Wygodna konfiguracja CRON-a bez ręcznego `crontab -e`.
#
#   cron_list [-o]                         lista zadań: Twoje (numerowane) + wszystkie inne, do których masz dostęp
#   cron_add [-n nazwa] [--no-log] <harmonogram> <polecenie...>
#   cron_remove <nr|wzorzec>
#   cron_edit                              edycja w $VISUAL/$EDITOR z walidacją składni
#   cron_schedule <opis>                   tłumaczy "co 5 min", "codziennie o 03:00", ... na składnię cron
#
# Zasady:
#   • Zadania INNYCH użytkowników i systemu (/etc/crontab, /etc/cron.d, spool) są wyłącznie do ODCZYTU.
#     Funkcje modyfikujące (add/remove/edit) działają tylko na własnym crontabie — nigdy `crontab -u`.
#   • cron_add dopisuje do oznaczonego bloku (# koziolek-cron:BEGIN/END) — reszta crontaba zostaje
#     nietknięta (ten sam styl co blok XML w 157_function_maven_signing.sh). Wpis jest idempotentny.
#   • Wyjście zadania trafia do ${CRON_LOG_DIR:-~/.cache/cron}/<nazwa>.log; blok ustawia SHELL i PATH.
#
# Różnice per-system przez zmienne (nadpisywane w bash/contexts/<system>.sh), nie przez `uname`:
#   CRON_SPOOL_DIRS      katalogi spoolu użytkowników (Linux: /var/spool/cron/crontabs, /var/spool/cron)
#   CRON_SYSTEM_FILES    pliki systemowe w formacie z polem użytkownika (/etc/crontab)
#   CRON_SYSTEM_DIRS     katalogi z takimi plikami (/etc/cron.d)
#   CRON_PERIODIC_DIRS   katalogi skryptów okresowych (/etc/cron.daily ...)
#   CRON_DAEMON_CHECK    0 = nie ostrzegaj o braku demona (macOS: launchd uruchamia cron na żądanie)
#   CRON_USE_SUDO        1 = nieczytelne spoole próbuj czytać przez `sudo -n cat`

_CRON_BEGIN="# koziolek-cron:BEGIN"
_CRON_END="# koziolek-cron:END"

_cron_check_cli() {
    command -v crontab &>/dev/null && return 0
    log_error cron.no_crontab
    return 1
}

# Bieżący crontab na stdout (brak crontaba = pusto, nie błąd).
_cron_dump() {
    crontab -l 2>/dev/null || true
}

# Czy linia jest zadaniem (harmonogram + polecenie), a nie komentarzem/zmienną/pustą.
_cron_is_job() {
    [[ "$1" =~ ^[[:space:]]*[0-9*@] ]]
}

# Zamienia nazwy miesięcy/dni tygodnia na liczby (jan..dec → 1..12, sun..sat → 0..6).
_cron_names_to_numbers() {
    local s="${1,,}" i
    local -a months=(jan feb mar apr may jun jul aug sep oct nov dec)
    local -a days=(sun mon tue wed thu fri sat)
    case "$2" in
    mon) for i in "${!months[@]}"; do s="${s//${months[$i]}/$((i + 1))}"; done ;;
    dow) for i in "${!days[@]}"; do s="${s//${days[$i]}/$i}"; done ;;
    esac
    printf '%s' "$s"
}

# _cron_field_ok <pole> <min> <max> [mon|dow] — składnia: *, a, a-b, */n, a-b/n oraz lista po przecinku.
_cron_field_ok() {
    local field part base step lo hi
    field="$(_cron_names_to_numbers "$1" "${4:-}")"
    local min="$2" max="$3"
    [ -n "$field" ] || return 1
    local -a parts
    IFS=',' read -ra parts <<<"$field"
    for part in "${parts[@]}"; do
        step=""
        base="$part"
        if [[ "$part" == */* ]]; then
            base="${part%%/*}"
            step="${part#*/}"
            [[ "$step" =~ ^[0-9]+$ ]] && [ "$step" -ge 1 ] || return 1
        fi
        if [ "$base" = "*" ]; then
            continue
        elif [[ "$base" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            lo="${BASH_REMATCH[1]}"
            hi="${BASH_REMATCH[2]}"
            [ "$lo" -ge "$min" ] && [ "$hi" -le "$max" ] && [ "$lo" -le "$hi" ] || return 1
        elif [[ "$base" =~ ^[0-9]+$ ]]; then
            [ -z "$step" ] || return 1
            [ "$base" -ge "$min" ] && [ "$base" -le "$max" ] || return 1
        else
            return 1
        fi
    done
    return 0
}

# Czy tekst (5 pól albo @makro) jest poprawnym harmonogramem.
_cron_schedule_ok() {
    local s="$1" m h dom mon dow extra
    case "$s" in
    @reboot | @hourly | @daily | @midnight | @weekly | @monthly | @yearly | @annually) return 0 ;;
    esac
    read -r m h dom mon dow extra <<<"$s"
    [ -n "$dow" ] && [ -z "$extra" ] || return 1
    _cron_field_ok "$m" 0 59 && _cron_field_ok "$h" 0 23 && _cron_field_ok "$dom" 1 31 &&
        _cron_field_ok "$mon" 1 12 mon && _cron_field_ok "$dow" 0 7 dow
}

# Poprawność całej linii crontaba. 0 = ok (komentarz, pusta, zmienna, zadanie).
_cron_line_ok() {
    local line="$1" sched cmd m h dom mon dow
    [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && return 0
    [[ "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*= ]] && return 0
    _cron_is_job "$line" || return 1
    read -r m h dom mon dow cmd <<<"$line"
    if [[ "$m" == @* ]]; then
        sched="$m"
        cmd="$h${dom:+ $dom}${mon:+ $mon}${dow:+ $dow}${cmd:+ $cmd}"
    else
        sched="$m $h $dom $mon $dow"
    fi
    [ -n "$cmd" ] || return 1
    _cron_schedule_ok "$sched"
}

# Waliduje plik crontaba; błędne linie loguje. 0 = wszystko ok.
_cron_validate_file() {
    local file="$1" line n=0 bad=0
    while IFS= read -r line || [ -n "$line" ]; do
        n=$((n + 1))
        if ! _cron_line_ok "$line"; then
            log_error cron.invalid_line "$n" "$line"
            bad=1
        fi
    done <"$file"
    return "$bad"
}

# Instaluje plik jako crontab bieżącego użytkownika (pusty = usunięcie crontaba).
_cron_install() {
    local file="$1"
    if ! grep -q '[^[:space:]]' "$file"; then
        crontab -r 2>/dev/null || true
        return 0
    fi
    if ! crontab "$file"; then
        log_error cron.install_failed
        return 1
    fi
}

# Demon cron nie działa → wpisy się nie wykonają (np. subsystem apx Vanilla OS nie ma demona).
_cron_warn_no_daemon() {
    [ "${CRON_DAEMON_CHECK:-1}" = "1" ] || return 0
    command -v pgrep &>/dev/null || return 0
    pgrep -x cron &>/dev/null && return 0
    pgrep -x crond &>/dev/null && return 0
    log_warn cron.no_daemon
}

# Numer dnia tygodnia (0=niedziela) dla polskiej/angielskiej nazwy; 1 gdy nie rozpoznano.
_cron_dow_num() {
    case "$1" in
    niedziel* | sun*) echo 0 ;;
    poniedzia* | mon*) echo 1 ;;
    wtor* | tue*) echo 2 ;;
    sro* | śro* | wed*) echo 3 ;;
    czwart* | thu*) echo 4 ;;
    pi*tek* | fri*) echo 5 ;;
    sobot* | sat*) echo 6 ;;
    *) return 1 ;;
    esac
}

# cron_schedule <opis> — składnia cron (5 pól lub @makro) na stdout; kod 1 gdy nie rozumie.
# Przyjmuje gotowy harmonogram oraz opisy: "co 5 min", "co 2 godziny", "co godzinę", "codziennie [o 03:00]",
# "co tydzień [o 8:30]", "w poniedziałek o 08:00", "co miesiąc [o 06:00]", "przy starcie"
# i angielskie odpowiedniki ("every 5 minutes", "daily at 03:00", "hourly", "on monday at 08:00", "at boot").
cron_schedule() {
    local in="${*,,}" h m dow n
    in="${in#"${in%%[![:space:]]*}"}"
    in="${in%"${in##*[![:space:]]}"}"
    [ -n "$in" ] || return 1
    local time_re='( (o|at) ([0-9]{1,2})(:([0-9]{2}))?)?'

    # Gotowy harmonogram
    if _cron_schedule_ok "$in"; then
        printf '%s\n' "$in"
        return 0
    fi

    _cron_time() {  # ustawia h, m z dopasowania: grupy 3 i 5 względem offsetu $1
        h="${BASH_REMATCH[$1]:-0}"
        m="${BASH_REMATCH[$(($1 + 2))]:-0}"
        m=$((10#$m))
        h=$((10#$h))
        [ "$h" -le 23 ] && [ "$m" -le 59 ]
    }

    local ok=1
    if [[ "$in" =~ ^(przy\ starcie|po\ starcie|at\ boot|on\ boot|reboot)$ ]]; then
        echo "@reboot"
        ok=0
    elif [[ "$in" =~ ^(co|every)\ minut(ę|e)$ || "$in" == "every minute" ]]; then
        echo "* * * * *"
        ok=0
    elif [[ "$in" =~ ^(co|every)\ ([0-9]+)\ (min|minut|minuty|minutę|minute|minutes)$ ]]; then
        n="${BASH_REMATCH[2]}"
        if [ "$n" -ge 1 ] && [ "$n" -le 59 ]; then
            echo "*/$n * * * *"
            ok=0
        fi
    elif [[ "$in" =~ ^(co\ godzin(ę|e)|co\ godz|hourly|every\ hour)$ ]]; then
        echo "0 * * * *"
        ok=0
    elif [[ "$in" =~ ^(co|every)\ ([0-9]+)\ (godz|godzin|godziny|godzinę|hour|hours)$ ]]; then
        n="${BASH_REMATCH[2]}"
        if [ "$n" -ge 1 ] && [ "$n" -le 23 ]; then
            echo "0 */$n * * *"
            ok=0
        fi
    elif [[ "$in" =~ ^(codziennie|daily|every\ day)$time_re$ ]]; then
        if _cron_time 4; then
            echo "$m $h * * *"
            ok=0
        fi
    elif [[ "$in" =~ ^(co\ tydzień|co\ tydzien|weekly|every\ week)$time_re$ ]]; then
        if _cron_time 4; then
            echo "$m $h * * 0"
            ok=0
        fi
    elif [[ "$in" =~ ^(co\ miesiąc|co\ miesiac|monthly|every\ month)$time_re$ ]]; then
        if _cron_time 4; then
            echo "$m $h 1 * *"
            ok=0
        fi
    elif [[ "$in" =~ ^(w|we|co|every|on)\ ([^\ ]+)$time_re$ ]]; then
        if dow="$(_cron_dow_num "${BASH_REMATCH[2]}")" && _cron_time 5; then
            echo "$m $h * * $dow"
            ok=0
        fi
    fi
    unset -f _cron_time
    return "$ok"
}

# Pobiera nazwę wpisu z polecenia: basename pierwszego słowa, znaki spoza [A-Za-z0-9._-] → "_".
_cron_default_name() {
    local first="${1%% *}"
    first="${first##*/}"
    first="${first//[^A-Za-z0-9._-]/_}"
    printf '%s' "${first:-cron}"
}

# cron_add [-n nazwa] [--no-log] <harmonogram> <polecenie...>
# Dopisuje zadanie do bloku "koziolek-cron" własnego crontaba. Idempotentne (ten sam wpis nie dubluje się).
# Wyjście zadania → ${CRON_LOG_DIR:-~/.cache/cron}/<nazwa>.log (nazwa domyślnie z polecenia). `%` w poleceniu
# jest escapowany (cron traktuje go jak znak nowej linii).
cron_add() {
    local name="" log=1
    while [[ "${1:-}" == -* ]]; do
        case "$1" in
        -n | --name) name="${2:-}"; shift 2 || shift ;;
        --no-log) log=0; shift ;;
        --) shift; break ;;
        *) log_error cron.unknown_option "$1"; return 1 ;;
        esac
    done
    if [ $# -lt 2 ]; then
        log_man cron.add_usage
        return 1
    fi
    _cron_check_cli || return 1

    local sched cmd="${*:2}" line logdir
    if ! sched="$(cron_schedule "$1")"; then
        log_error cron.bad_schedule "$1"
        return 1
    fi
    if [[ "$cmd" == *$'\n'* ]]; then
        log_error cron.multiline_command
        return 1
    fi
    cmd="${cmd//%/\\%}"
    if [ -n "$name" ] && [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
        log_error cron.bad_name "$name"
        return 1
    fi
    [ -n "$name" ] || name="$(_cron_default_name "$cmd")"

    line="$sched $cmd"
    if [ "$log" = 1 ]; then
        logdir="${CRON_LOG_DIR:-$HOME/.cache/cron}"
        if ! mkdir -p "$logdir"; then
            log_error cron.log_dir_failed "$logdir"
            return 1
        fi
        line="$line >> $logdir/$name.log 2>&1"
    fi

    local -a lines=() out=()
    local l inserted=0 in_block=0
    mapfile -t lines < <(_cron_dump)
    for l in "${lines[@]}"; do
        if [ "$l" = "$line" ]; then
            log_info cron.already_exists "$line"
            return 0
        fi
    done
    for l in "${lines[@]}"; do
        if [ "$l" = "$_CRON_END" ] && [ "$inserted" = 0 ]; then
            out+=("$line")
            inserted=1
        fi
        out+=("$l")
    done
    if [ "$inserted" = 0 ]; then
        out+=("$_CRON_BEGIN" "SHELL=/bin/bash" "PATH=${CRON_PATH:-$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin}" "$line" "$_CRON_END")
    fi

    local tmp
    tmp="$(mktemp)"
    printf '%s\n' "${out[@]}" >"$tmp"
    _cron_install "$tmp"
    local rc=$?
    rm -f "$tmp"
    [ "$rc" = 0 ] || return "$rc"
    log_info cron.added "$line"
    _cron_warn_no_daemon
    return 0
}

# cron_remove <nr|wzorzec> — usuwa JEDNO zadanie z własnego crontaba. Numer jak w `cron_list`;
# wzorzec = fragment linii (gdy pasuje kilka — błąd z listą, podaj numer). Pusty blok koziolek-cron znika.
cron_remove() {
    if [ $# -ne 1 ] || [ -z "$1" ]; then
        log_man cron.remove_usage
        return 1
    fi
    _cron_check_cli || return 1

    local key="$1" l n=0
    local -a lines=() matches=() match_nr=()
    mapfile -t lines < <(_cron_dump)
    local i
    for i in "${!lines[@]}"; do
        l="${lines[$i]}"
        _cron_is_job "$l" || continue
        n=$((n + 1))
        if [[ "$key" =~ ^[0-9]+$ ]]; then
            [ "$n" -eq "$key" ] && { matches+=("$i"); match_nr+=("$n"); }
        elif [[ "$l" == *"$key"* ]]; then
            matches+=("$i")
            match_nr+=("$n")
        fi
    done

    if [ "${#matches[@]}" -eq 0 ]; then
        log_error cron.no_such_entry "$key"
        return 1
    fi
    if [ "${#matches[@]}" -gt 1 ]; then
        log_error cron.ambiguous "$key" "${#matches[@]}"
        for i in "${!matches[@]}"; do
            log_man "$(printf '%3d  %s' "${match_nr[$i]}" "${lines[${matches[$i]}]}")"
        done
        return 1
    fi

    local removed="${lines[${matches[0]}]}"
    unset 'lines[${matches[0]}]'
    lines=("${lines[@]}")

    # Pusty blok (BEGIN, SHELL/PATH, END bez zadań) → usuń w całości.
    local -a out=() block=()
    local in_block=0 jobs_in_block=0
    for l in "${lines[@]}"; do
        if [ "$l" = "$_CRON_BEGIN" ]; then
            in_block=1; jobs_in_block=0; block=("$l"); continue
        fi
        if [ "$in_block" = 1 ]; then
            block+=("$l")
            _cron_is_job "$l" && jobs_in_block=1
            if [ "$l" = "$_CRON_END" ]; then
                in_block=0
                [ "$jobs_in_block" = 1 ] && out+=("${block[@]}")
            fi
            continue
        fi
        out+=("$l")
    done
    [ "$in_block" = 1 ] && out+=("${block[@]}")

    local tmp
    tmp="$(mktemp)"
    [ "${#out[@]}" -gt 0 ] && printf '%s\n' "${out[@]}" >"$tmp"
    _cron_install "$tmp"
    local rc=$?
    rm -f "$tmp"
    [ "$rc" = 0 ] || return "$rc"
    log_info cron.removed "$removed"
}

# cron_edit — edycja własnego crontaba w ${VISUAL:-${EDITOR:-vi}} z walidacją składni przed zapisem.
# Błędy → ponowna edycja (pytanie [T/n]; bez terminala albo CRON_ASSUME_YES=1 → przerwanie bez zmian).
cron_edit() {
    _cron_check_cli || return 1
    local editor="${VISUAL:-${EDITOR:-vi}}" tmp orig ans
    local -a editor_cmd
    read -ra editor_cmd <<<"$editor"
    tmp="$(mktemp)"
    orig="$(mktemp)"
    _cron_dump >"$tmp"
    cp "$tmp" "$orig"
    while :; do
        if ! "${editor_cmd[@]}" "$tmp"; then
            log_error cron.editor_failed "$editor"
            rm -f "$tmp" "$orig"
            return 1
        fi
        if cmp -s "$orig" "$tmp"; then
            log_info cron.no_changes
            rm -f "$tmp" "$orig"
            return 0
        fi
        if _cron_validate_file "$tmp"; then
            _cron_install "$tmp"
            local rc=$?
            rm -f "$tmp" "$orig"
            [ "$rc" = 0 ] && log_info cron.saved
            return "$rc"
        fi
        if [ "${CRON_ASSUME_YES:-0}" = 1 ] || [ ! -t 0 ]; then
            log_error cron.edit_aborted
            rm -f "$tmp" "$orig"
            return 1
        fi
        log_warn cron.edit_retry
        read -r ans
        if [[ "$ans" =~ ^[nN] ]]; then
            log_error cron.edit_aborted
            rm -f "$tmp" "$orig"
            return 1
        fi
    done
}

# Czyta plik; gdy nieczytelny, a CRON_USE_SUDO=1 — próbuje `sudo -n cat`. 1 = brak dostępu.
_cron_read_file() {
    local f="$1"
    if [ -r "$f" ]; then
        cat "$f"
    elif [ "${CRON_USE_SUDO:-0}" = 1 ] && [ -e "$f" ] && command -v sudo &>/dev/null; then
        sudo -n cat "$f" 2>/dev/null
    else
        return 1
    fi
}

# Wypisuje (read-only) zadania z cudzego źródła: <etykieta> <plik>. Zwraca 1, gdy nieczytelny.
_cron_print_source() {
    local label="$1" file="$2" content line printed=0
    content="$(_cron_read_file "$file")" || return 1
    while IFS= read -r line; do
        _cron_is_job "$line" || continue
        if [ "$printed" = 0 ]; then
            log_info cron.list_source "$label"
            printed=1
        fi
        log_man "    $line"
    done <<<"$content"
    return 0
}

# cron_list [-o|--own] — Twój crontab (numerowany, numery dla cron_remove) + zadania innych użytkowników
# i systemu, do których masz dostęp (tylko odczyt; ich zmieniać nie wolno). -o = tylko własne.
cron_list() {
    local only_own=0
    case "${1:-}" in
    -o | --own) only_own=1 ;;
    "") ;;
    *) log_error cron.unknown_option "$1"; return 1 ;;
    esac
    _cron_check_cli || return 1

    local user l n=0
    user="$(id -un)"
    local -a lines=()
    mapfile -t lines < <(_cron_dump)
    log_info cron.list_own_header "$user"
    for l in "${lines[@]}"; do
        _cron_is_job "$l" || continue
        n=$((n + 1))
        log_man "$(printf '%3d  %s' "$n" "$l")"
    done
    [ "$n" -gt 0 ] || log_info cron.list_own_empty

    [ "$only_own" = 1 ] && return 0

    log_info cron.list_others_header
    local unreadable=0 shown=0 d f base
    # Spoole innych użytkowników (własny pomijamy — już wyżej)
    for d in ${CRON_SPOOL_DIRS-/var/spool/cron/crontabs /var/spool/cron}; do
        [ -d "$d" ] || continue
        # katalog spoolu bez prawa odczytu (Debian: crontabs 1730 root:crontab) = jedno nieczytelne źródło
        if [ ! -r "$d" ]; then
            unreadable=$((unreadable + 1))
            continue
        fi
        for f in "$d"/*; do
            [ -f "$f" ] || continue
            base="${f##*/}"
            [ "$base" = "$user" ] && continue
            if _cron_print_source "użytkownik $base" "$f"; then shown=1; else unreadable=$((unreadable + 1)); fi
        done
    done
    # Pliki systemowe (z polem użytkownika)
    for f in ${CRON_SYSTEM_FILES-/etc/crontab}; do
        [ -f "$f" ] || continue
        if _cron_print_source "system: $f" "$f"; then shown=1; else unreadable=$((unreadable + 1)); fi
    done
    for d in ${CRON_SYSTEM_DIRS-/etc/cron.d}; do
        [ -d "$d" ] || continue
        for f in "$d"/*; do
            [ -f "$f" ] || continue
            if _cron_print_source "system: $f" "$f"; then shown=1; else unreadable=$((unreadable + 1)); fi
        done
    done
    # Skrypty okresowe (hourly/daily/...) — same nazwy
    for d in ${CRON_PERIODIC_DIRS-/etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly}; do
        [ -d "$d" ] && [ -r "$d" ] || continue
        local -a scripts=()
        for f in "$d"/*; do
            base="${f##*/}"
            [ -f "$f" ] && [ "$base" != ".placeholder" ] && scripts+=("$base")
        done
        if [ "${#scripts[@]}" -gt 0 ]; then
            log_info cron.list_periodic "${d##*/}" "${scripts[*]}"
            shown=1
        fi
    done
    [ "$shown" = 1 ] || log_info cron.list_no_others
    [ "$unreadable" -eq 0 ] || log_info cron.list_unreadable "$unreadable"
    return 0
}

export -f cron_list cron_add cron_remove cron_edit cron_schedule
