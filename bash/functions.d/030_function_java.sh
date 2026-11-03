#!/usr/bin/env bash

# Wersje Linux (/proc/sys/kernel). macOS cieniuje w bash/contexts/darwin.sh.
function turn_async_profiler_on() {
    make_me_sudo
    $SUDO sh -c 'echo 1 > /proc/sys/kernel/perf_event_paranoid'
    $SUDO sh -c 'echo 0 > /proc/sys/kernel/kptr_restrict'
    unmake_me_sudo
}

function turn_async_profiler_off() {
    make_me_sudo
    $SUDO sh -c 'echo 4 > /proc/sys/kernel/perf_event_paranoid'
    $SUDO sh -c 'echo 1 > /proc/sys/kernel/kptr_restrict'
    unmake_me_sudo
}

function java_clear() {
    local target_dir="${1:-.}"

    if ! command -v fdfind &>/dev/null; then
        log_error java.clear_no_fdfind
        return 1
    fi

    while IFS= read -r build_file; do
        local dir
        dir="$(dirname "$build_file")"
        local filename
        filename="$(basename "$build_file")"

        if [[ "$filename" == "pom.xml" ]]; then
            log_info java.clear_mvn "$dir"
            (cd "$dir" && mvn clean)
        elif [[ "$filename" == "build.gradle" || "$filename" == "build.gradle.kts" ]]; then
            log_info java.clear_gradle "$dir"
            if [[ -f "$dir/gradlew" ]]; then
                (cd "$dir" && ./gradlew clean)
            else
                (cd "$dir" && gradle clean)
            fi
        fi
    done < <(fdfind -t f '(pom\.xml|build\.gradle(\.kts)?)' "$target_dir")
}

# ═══ jhot — diagnoza "gorących" wątków JVM (Linux: /proc) ═══════════════════════
#
# Wywołanie: jhot --pid 1234   |   jhot --all   |   jhot -h
#
#   ① wybór JVM          – najgorętsza JVM (lub --pid / --all)
#   ② CPU per wątek      – /proc/PID/task/*/stat (to samo źródło co top -H),
#                          uśrednione z całego okna próbkowania, a nie z 1 s
#   ③ TID → nid          – dopasowanie do jstacka (0x… i dziesiętny z JDK 19+)
#   ④ jstack × N         – czy wątek stoi w tym samym miejscu
#   +  wstępna analiza   – rozkład CPU (aplikacja/GC/JIT/VM), GC z jstat,
#                          throttling cgroup, blokady i deadlocki, grupy wątków,
#                          najczęstsze ramki, wzorce znanych problemów → DIAGNOZA
#
# Wymaga: Linux, bash ≥ 4.4, awk, sort; jstack (i opcjonalnie jstat) z JDK.
#
# Świadomy wyjątek od konwencji log_*: własne _jhot_log/_jhot_warn/_jhot_err
# (stderr, kolor tylko na TTY), bo zachowanie przeniesionego narzędzia ma być
# identyczne ze skryptem źródłowym. Wszystkie funkcje są eksportowane (export -f),
# bo --all i procesy potomne ich używają.

_jhot_usage() {
    cat <<'EOF'
Użycie: jhot [opcje]

  -p, --pid PID        analizuj wskazaną JVM (pomija wyszukiwanie PID)
      --all            analizuj wszystkie JVM równolegle; wyniki w podkatalogach <PID>/
  -n, --threads N      ile najgorętszych wątków opisać (domyślnie 3)
  -s, --samples N      ile zrzutów jstack (domyślnie 3)
  -i, --interval SEK   odstęp między zrzutami (domyślnie 5)
  -d, --depth N        ile ramek stosu pokazać (domyślnie 15)
  -o, --out KATALOG    katalog wyników (domyślnie ./jhot-PID-DATA lub ./jhot-all-DATA)
      --app PREFIKS    pakiet aplikacji, np. pl.gov.pansa – dokładniejsza
                       "pierwsza ramka aplikacji" (domyślnie: pierwsza spoza JDK/bibliotek)
  -a, --arthas         zamiast analizy: Arthas thread -n N (wymaga ARTHAS_JAR=…/arthas-boot.jar)
  -h, --help           ta pomoc

Bez --pid i --all wybierana jest JVM o najwyższym zużyciu CPU.
Opcje długie przyjmują też postać --opcja=wartość.
EOF
}

_jhot_log() { if [[ -t 2 ]]; then printf '\e[1;36m==>\e[0m %s\n' "$*" >&2; else printf '==> %s\n' "$*" >&2; fi; }
_jhot_warn() { if [[ -t 2 ]]; then printf '\e[33m[!]\e[0m %s\n' "$*" >&2; else printf '[!] %s\n' "$*" >&2; fi; }
_jhot_err() { if [[ -t 2 ]]; then printf '\e[31m[x]\e[0m %s\n' "$*" >&2; else printf '[x] %s\n' "$*" >&2; fi; }

_jhot_now() {
    local t=${EPOCHREALTIME:-}
    [[ -n $t ]] && echo "${t/,/.}" || date +%s.%N
}

# a >= b (liczby zmiennoprzecinkowe)
_jhot_ge() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 >= b + 0) }'; }

# część / całość w procentach (całkowite)
_jhot_pct() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%d", (b + 0 > 0) ? a * 100 / b : 0 }'; }

_jhot_dur() {
    local t=${1:-0}
    if ((t >= 86400)); then
        printf '%dd%02dh' $((t / 86400)) $((t % 86400 / 3600))
    elif ((t >= 3600)); then
        printf '%dh%02dm' $((t / 3600)) $((t % 3600 / 60))
    elif ((t >= 60)); then
        printf '%dm%02ds' $((t / 60)) $((t % 60))
    else printf '%ds' "$t"; fi
}

# Wszystkie pola /proc/PID/stat po nazwie procesu (f[0] = pole 3 "state")
_jhot_stat_fields() {
    local s
    { s=$(<"/proc/$1/stat"); } 2>/dev/null || return 1
    echo "${s##*) }"
}

# utime + stime procesu w tickach
_jhot_proc_ticks() {
    local -a f
    read -ra f <<<"$(_jhot_stat_fields "$1")" || return 1
    ((${#f[@]} > 12)) || return 1
    echo $((f[11] + f[12]))
}

# czas działania procesu w sekundach
_jhot_uptime() {
    local -a f
    local up
    read -ra f <<<"$(_jhot_stat_fields "$1")"
    read -r up _ </proc/uptime
    awk -v u="$up" -v st="${f[19]:-0}" -v hz="$2" 'BEGIN { printf "%d", u - st / hz }'
}

_jhot_is_jvm() {
    local p=$1 comm exe
    { read -r comm <"/proc/$p/comm"; } 2>/dev/null || return 1
    case $comm in jstack | jcmd | jstat | jps | jinfo | jmap) return 1 ;; java) return 0 ;; esac
    exe=$(readlink "/proc/$p/exe" 2>/dev/null) && [[ $exe == */bin/java ]] && return 0
    grep -qs -m1 'libjvm\.so' "/proc/$p/maps"
}

_jhot_list_jvms() {
    local d p
    for d in /proc/[0-9]*; do
        p=${d#/proc/}
        [[ $p == "$$" || $p == "${BASHPID:-}" ]] && continue
        _jhot_is_jvm "$p" && echo "$p"
    done
}

# "PID CPU%" posortowane malejąco, pomiar przez 1 s
_jhot_rank_cpu() {
    local hz p t1
    local -A t0=()
    hz=$(getconf CLK_TCK 2>/dev/null) || hz=100
    for p in "$@"; do t0[$p]=$(_jhot_proc_ticks "$p") || unset 't0[$p]'; done
    sleep 1
    for p in "$@"; do
        [[ -n ${t0[$p]:-} ]] || continue
        t1=$(_jhot_proc_ticks "$p") || continue
        echo "$p $(((t1 - ${t0[$p]}) * 100 / hz))"
    done | sort -k2,2nr
}

_jhot_main_class() {
    local -a a=()
    local i
    { mapfile -d '' -t a <"/proc/$1/cmdline"; } 2>/dev/null
    for ((i = 1; i < ${#a[@]}; i++)); do
        case ${a[i]} in
        -jar)
            echo "${a[i + 1]##*/}"
            return
            ;;
        -m | --module)
            echo "${a[i + 1]:-?}"
            return
            ;;
        -cp | -classpath | --class-path | -p | --module-path | --add-modules | --add-opens | --add-exports | --add-reads | --patch-module | --upgrade-module-path | --limit-modules)
            ((i++))
            ;;
        -*) ;;
        *)
            echo "${a[i]}"
            return
            ;;
        esac
    done
    echo '?'
}

# Ustawia tablicę "runas" w zakresie wywołującego (jstack musi działać jako właściciel JVM)
_jhot_set_runas() {
    local owner=$1
    runas=()
    [[ $(id -un) == "$owner" ]] && return 0
    if [[ $(id -u) -eq 0 ]]; then
        if command -v runuser >/dev/null; then
            runas=(runuser -u "$owner" --)
        elif command -v sudo >/dev/null; then
            runas=(sudo -u "$owner")
        else _jhot_warn "JVM $2 należy do '$owner' – brak runuser/sudo, jstack może się nie podłączyć."; fi
    else
        _jhot_warn "JVM $2 należy do '$owner', a Ty jesteś '$(id -un)' – jstack może się nie podłączyć."
    fi
}
_jhot_run() { ${runas[@]+"${runas[@]}"} "$@"; }

# Narzędzie JDK z tej samej instalacji, na której działa JVM
_jhot_jdk_tool() {
    local exe home c
    exe=$(readlink -f "/proc/$1/exe" 2>/dev/null) && home=${exe%/bin/java}
    for c in "${home:+$home/bin/$2}" "${JAVA_HOME:+$JAVA_HOME/bin/$2}" "$(command -v "$2" 2>/dev/null)"; do
        [[ -n $c && -x $c ]] && {
            echo "$c"
            return 0
        }
    done
    return 1
}

# ─────────────────────────────────────────────────────────── pomiary/parsowanie ──

# TID \t TICKS \t NAZWA (nazwa = comm, max 15 znaków)
_jhot_task_snapshot() {
    cat /proc/"$1"/task/*/stat 2>/dev/null | awk '{
    name = $0; sub(/^[0-9]+ \(/, "", name); sub(/\) [A-Za-z] [^)]*$/, "", name)
    rest = $0; sub(/^.*\) /, "", rest)
    split(rest, f, " ")
    printf "%s\t%d\t%s\n", $1, f[12] + f[13], name
  }'
}

# TID \t CPU% \t KATEGORIA \t NAZWA – malejąco po CPU
_jhot_task_delta() {
    awk -F'\t' -v secs="$3" -v hz="$4" '
    function category(n) {
      if (n ~ /^(GC Thread|G1 |Gang worker|Parallel GC|Shenandoah|ZWorker|Z[A-Z][a-z]|Conc )/) return "GC"
      if (n ~ /^(C[12] CompilerThre|JVMCI|Sweeper)/) return "JIT"
      if (n ~ /^(VM Thread|VM Periodic|Monitor Deflati|Service Thread)/) return "VM"
      if (n ~ /^(Finalizer|Reference Handl|Signal Dispatch|Attach Listener|Common-Cleaner|Notification Th|process reaper)/) return "JVM"
      return "APP"
    }
    NR == FNR { t0[$1] = $2; next }
    { b = ($1 in t0) ? t0[$1] : 0
      printf "%s\t%.1f\t%s\t%s\n", $1, ($2 - b) * 100 / (hz * secs), category($3), $3 }
  ' "$1" "$2" | sort -t$'\t' -k2,2gr
}

# jstack → TID \t NAZWA \t STAN \t SZCZYT_STOSU \t PIERWSZA_RAMKA_APLIKACJI \t 8_RAMEK
# (puste pola jako "-", bo IFS=tab zlewa puste kolumny)
_jhot_parse_jstack() {
    awk -v app="$2" '
    function hex2dec(h,   i, d) {
      d = 0; h = tolower(h)
      for (i = 1; i <= length(h); i++) d = d * 16 + index("0123456789abcdef", substr(h, i, 1)) - 1
      return d
    }
    function is_lib(f) {
      if (app != "") return index(f, app) != 1
      return f ~ /^(java|javax|jdk|sun|com\.sun|jakarta|kotlin|kotlinx|scala|groovy|org\.codehaus\.groovy|org\.springframework|org\.apache|org\.eclipse|org\.hibernate|org\.slf4j|org\.jboss|io\.netty|io\.micrometer|io\.undertow|io\.grpc|io\.opentelemetry|io\.lettuce|reactor|com\.fasterxml|com\.google|com\.zaxxer|com\.rabbitmq|ch\.qos|okhttp3|okio|net\.bytebuddy|org\.aspectj|feign|brave|zipkin2)\./
    }
    function flush() {
      if (tid != "")
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", tid, name, state, (top == "" ? "-" : top), (appf == "" ? "-" : appf), (frames == "" ? "-" : frames)
      tid = ""
    }
    stop { next }
    /^Found (one|[0-9]+) Java-level deadlock/ || /^JNI global ref/ { flush(); stop = 1; next }
    /^"/ && / nid=/ {
      flush()
      name = $0; sub(/^"/, "", name); sub(/" .*$/, "", name)
      if (match($0, /nid=0x[0-9a-fA-F]+/)) tid = hex2dec(substr($0, RSTART + 6, RLENGTH - 6))
      else if (match($0, /nid=[0-9]+/))    tid = substr($0, RSTART + 4, RLENGTH - 4)
      state = "-"; top = ""; appf = ""; frames = ""; nf = 0
      next
    }
    tid == "" { next }
    /java\.lang\.Thread\.State: / { state = $0; sub(/^.*State: /, "", state); sub(/ .*$/, "", state); next }
    /^[ \t]+at / {
      f = $0; sub(/^[ \t]+at /, "", f); sub(/^[^(]*\//, "", f)
      nf++
      if (nf == 1) top = f
      if (appf == "" && !is_lib(f)) appf = f
      if (nf <= 8) frames = frames (nf > 1 ? " | " : "") f
    }
    END { flush() }
  ' "$1"
}

# Surowy blok wątku z jstacka (TID dziesiętny)
_jhot_thread_block() {
    awk -v hex="$(printf '%x' "$2")" -v dec="$2" '
    BEGIN { RS = "" }
    {
      split($0, L, "\n"); h = L[1]
      if (h ~ ("nid=0x" hex "( |$)") || h ~ ("nid=" dec "( |$)") || index(h, "[" dec "]")) { print; exit }
    }' "$1"
}

# Rywalizacja o blokady: ILE \t ADRES \t KLASA \t WŁAŚCICIEL \t RAMKA_WŁAŚCICIELA
_jhot_locks() {
    awk '
    stop { next }
    /^Found (one|[0-9]+) Java-level deadlock/ || /^JNI global ref/ { stop = 1; next }
    /^"/ && / nid=/ { name = $0; sub(/^"/, "", name); sub(/" .*$/, "", name); first = 1; inown = 0; next }
    /^[ \t]+at / && first { f = $0; sub(/^[ \t]+at /, "", f); sub(/^[^(]*\//, "", f); top[name] = f; first = 0 }
    /- waiting to lock <0x/ || (/- parking to wait for +<0x/ && /Sync\)/) {
      match($0, /<0x[0-9a-f]+>/); a = substr($0, RSTART, RLENGTH); w[a]++
      c = $0; sub(/^.*\(a /, "", c); sub(/\).*$/, "", c); cls[a] = c
    }
    /- locked <0x/ { match($0, /<0x[0-9a-f]+>/); own[substr($0, RSTART, RLENGTH)] = name }
    /Locked ownable synchronizers:/ { inown = 1; next }
    inown && /^[ \t]+- <0x/ { match($0, /<0x[0-9a-f]+>/); own[substr($0, RSTART, RLENGTH)] = name }
    END {
      for (a in w) {
        o = (a in own) ? own[a] : "?"
        printf "%d\t%s\t%s\t%s\t%s\n", w[a], a, cls[a], o, ((o in top) ? top[o] : "-")
      }
    }' "$1" | sort -t$'\t' -k1,1nr | head -n 3
}

# Najczęstsze ramki AKTYWNYCH wątków ze wszystkich próbek (bez I/O w oczekiwaniu)
_jhot_hot_frames() {
    cat "$@" | awk -F'\t' '
    $3 == "RUNNABLE" && $4 != "-" &&
    $4 !~ /(EPoll\.wait|epollWait|Net\.accept|Net\.poll|socketAccept|socketRead0|SocketDispatcher\.read|FileDispatcherImpl\.read|FileInputStream\.readBytes|KQueue|waitForProcessExit|LinuxWatchService|Native\.epollWait|receive0|accept0|ServerSocketChannelImpl\.accept|Thread\.sleep|Object\.wait|Unsafe\.park|ProcessImpl|readBytes|waitForReferencePendingList|Signal\.waitForSignal)/ {
      k = ($5 != "-") ? $5 : $4; sub(/\(.*$/, "", k); c[k]++
    }
    END { for (k in c) printf "%d\t%s\n", c[k], k }' | sort -t$'\t' -k1,1nr | head -n 5
}

# GC z dwóch odczytów jstat -gcutil: "OLD% ΔFGC ΔYGC %CZASU_W_GC"
_jhot_gc_delta() {
    # nagłówek szukany po " GCT", bo przed nim mogą być np. "Picked up JAVA_TOOL_OPTIONS"
    awk -v secs="$3" '
    FNR == 1 { f++; hdr = 0 }
    !hdr && / GCT/ { delete c; for (i = 1; i <= NF; i++) c[$i] = i; hdr = 1; next }
    hdr == 1 {
      hdr = 2
      o[f] = ("O" in c) ? $c["O"] : "-"
      fgc[f] = ("FGC" in c) ? $c["FGC"] : 0; ygc[f] = ("YGC" in c) ? $c["YGC"] : 0
      gct[f] = $c["GCT"]; ok[f] = 1
    }
    END { if (ok[1] && ok[2]) printf "%s %d %d %.1f\n", o[2], fgc[2] - fgc[1], ygc[2] - ygc[1], (gct[2] - gct[1]) * 100 / secs }
  ' "$1" "$2" 2>/dev/null
}

# cgroup CPU: "LIMIT_RDZENI|- NR_PERIODS NR_THROTTLED THROTTLED_USEC"
_jhot_cgroup_cpu() {
    local line rel dir q p lim=-
    if [[ -f /sys/fs/cgroup/cgroup.controllers ]] && line=$(grep -m1 '^0::' "/proc/$1/cgroup" 2>/dev/null); then
        rel=${line#0::}
        dir=/sys/fs/cgroup$rel
        [[ -r $dir/cpu.stat ]] || dir=/sys/fs/cgroup
        [[ -r $dir/cpu.stat ]] || return 1
        if [[ -r $dir/cpu.max ]]; then
            read -r q p <"$dir/cpu.max"
            [[ $q != max ]] && lim=$(awk -v q="$q" -v p="$p" 'BEGIN { printf "%.2f", q / p }')
        fi
        awk -v lim="$lim" '$1 == "nr_periods" { a = $2 } $1 == "nr_throttled" { b = $2 } $1 == "throttled_usec" { c = $2 }
      END { if (a != "") print lim, a, b + 0, c + 0 }' "$dir/cpu.stat"
    elif line=$(grep -m1 -E '^[0-9]+:([^:]*,)?cpu(,[^:]*)?:' "/proc/$1/cgroup" 2>/dev/null); then
        rel=${line##*:}
        for dir in "/sys/fs/cgroup/cpu,cpuacct$rel" "/sys/fs/cgroup/cpu$rel" /sys/fs/cgroup/cpu,cpuacct /sys/fs/cgroup/cpu; do
            [[ -r $dir/cpu.stat ]] && break
        done
        [[ -r $dir/cpu.stat ]] || return 1
        if [[ -r $dir/cpu.cfs_quota_us ]]; then
            read -r q <"$dir/cpu.cfs_quota_us"
            read -r p <"$dir/cpu.cfs_period_us"
            ((q > 0)) && lim=$(awk -v q="$q" -v p="$p" 'BEGIN { printf "%.2f", q / p }')
        fi
        awk -v lim="$lim" '$1 == "nr_periods" { a = $2 } $1 == "nr_throttled" { b = $2 } $1 == "throttled_time" { c = $2 / 1000 }
      END { if (a != "") print lim, a, b + 0, c + 0 }' "$dir/cpu.stat"
    else
        return 1
    fi
}

# Wzorce znanych problemów w stosie gorącego wątku: "regex => wskazówka"
_jhot_hints() {
    local frames=$1 line re
    while IFS= read -r line; do
        [[ -z $line || $line == \#* ]] && continue
        re=${line%% => *}
        [[ $frames =~ $re ]] && printf '%s\n' "${line#* => }"
    done <<'EOF'
java\.util\.regex\. => Regex: możliwy katastrofalny backtracking (ReDoS) – sprawdź wzorzec i długość wejścia.
java\.util\.HashMap[.$] => HashMap w gorącej ścieżce: jeśli współdzielona między wątkami bez synchronizacji, możliwa pętla/uszkodzona struktura – użyj ConcurrentHashMap.
ConcurrentHashMap\.computeIfAbsent => computeIfAbsent: modyfikacja tej samej mapy wewnątrz funkcji mapującej daje livelock.
Throwable\.(fillInStackTrace|<init>)|Exception\.<init> => Masowe tworzenie wyjątków (wyjątki jako sterowanie przepływem?) – każdy to kosztowny stack trace.
Thread\.(yield|onSpinWait)|LockSupport\.parkNanos => Aktywne czekanie: pętla z yield/onSpinWait/parkNanos o małym timeoucie.
com\.fasterxml\.jackson|com\.google\.gson|javax\.xml|jakarta\.xml|org\.apache\.xerces|com\.sun\.org\.apache\.xerces => Serializacja/parsowanie JSON/XML – duże payloady albo (de)serializacja w pętli.
ch\.qos\.logback|org\.apache\.logging\.log4j|java\.util\.logging => Logowanie w gorącej ścieżce – poziom DEBUG/TRACE, synchroniczny appender, kosztowne argumenty logów.
java\.util\.zip|Inflater|Deflater => Kompresja/dekompresja.
javax\.crypto|sun\.security|java\.security => Kryptografia/TLS – brak reużycia połączeń (handshake za każdym razem)?
org\.hibernate|org\.eclipse\.persistence => ORM: dirty checking dużego persistence contextu, flush w pętli, N+1.
java\.util\.(ArrayList|LinkedList|AbstractCollection)\.(indexOf|contains|remove|node) => Liniowe przeszukiwanie listy w pętli – O(n²); rozważ Set/Map.
String\.format|java\.util\.Formatter|String\.intern => String.format/intern w gorącej ścieżce.
java\.lang\.ClassLoader\.loadClass|URLClassLoader|defineClass => Ciągłe ładowanie/generowanie klas – dynamiczne proxy, wyciek classloaderów.
java\.math\.(BigDecimal|BigInteger) => Intensywna arytmetyka BigDecimal/BigInteger.
java\.io\.FileOutputStream\.write|FileDispatcherImpl\.write|RandomAccessFile => Intensywny zapis na dysk (logi? flush po każdym wpisie?).
EOF
}

_jhot_cat_label() {
    case $1 in
    APP) echo 'aplikacja' ;; GC) echo 'GC' ;; JIT) echo 'kompilator JIT' ;;
    VM) echo 'VM / safepointy' ;; *) echo 'wewnętrzny JVM' ;;
    esac
}

_jhot_same() {
    local first=$1 x
    [[ -z $first || $first == - || $first == . ]] && return 1
    for x; do [[ $x == "$first" ]] || return 1; done
}

# Kolorowanie raportu na terminalu
_jhot_show() {
    if [[ -t 1 ]]; then
        sed -e $'s/\\[!!\\]/\e[1;31m[!!]\e[0m/' -e $'s/\\[! \\]/\e[33m[! ]\e[0m/' \
            -e $'s/^═══.*/\e[1m&\e[0m/' -e $'s/^── .*/\e[1;36m&\e[0m/' "$1"
    else
        cat "$1"
    fi
}

# ──────────────────────────────────────────────────────────── analiza jednej JVM ──

# _jhot_analyze PID KATALOG WĄTKI PRÓBKI ODSTĘP GŁĘBOKOŚĆ PREFIKS_APP  → raport na stdout
_jhot_analyze() {
    local pid=$1 dir=$2 nthreads=$3 samples=$4 interval=$5 depth=$6 app=$7
    local -x LC_ALL=C
    local tag="[$pid]" hz owner jstack jstat main up s
    local -a runas=() findings=()

    [[ -d /proc/$pid ]] || {
        _jhot_err "$tag proces nie istnieje"
        return 1
    }
    mkdir -p "$dir" || return 1
    hz=$(getconf CLK_TCK 2>/dev/null) || hz=100
    owner=$(stat -c %U "/proc/$pid")
    _jhot_set_runas "$owner" "$pid"
    jstack=$(_jhot_jdk_tool "$pid" jstack) ||
        {
            _jhot_err "$tag nie znalazłem jstack (JVM na JRE bez JDK?) – ustaw JAVA_HOME na JDK"
            return 1
        }
    jstat=$(_jhot_jdk_tool "$pid" jstat) || jstat=
    main=$(_jhot_main_class "$pid")
    up=$(_jhot_uptime "$pid" "$hz")

    # ── pomiar ────────────────────────────────────────────────────────────────
    local t_start t_end secs p0 p1 cg0 cg1
    _jhot_log "$tag ② CPU wątków + ④ $samples× jstack co ${interval}s ($main)"
    _jhot_task_snapshot "$pid" >"$dir/tasks-0.tsv"
    p0=$(_jhot_proc_ticks "$pid")
    cg0=$(_jhot_cgroup_cpu "$pid")
    [[ -n $jstat ]] && _jhot_run "$jstat" -gcutil "$pid" >"$dir/jstat-0.txt" 2>&1
    t_start=$(_jhot_now)

    for ((s = 1; s <= samples; s++)); do
        if ! _jhot_run "$jstack" -l "$pid" >"$dir/jstack-$s.txt" 2>&1; then
            _jhot_err "$tag jstack nie zadziałał – szczegóły w $dir/jstack-$s.txt"
            return 1
        fi
        _jhot_parse_jstack "$dir/jstack-$s.txt" "$app" >"$dir/threads-$s.tsv"
        if ((s < samples)); then sleep "$interval"; fi
    done
    if ((samples == 1)); then sleep 1; fi

    t_end=$(_jhot_now)
    _jhot_task_snapshot "$pid" >"$dir/tasks-1.tsv"
    p1=$(_jhot_proc_ticks "$pid") || {
        _jhot_err "$tag proces zakończył się w trakcie pomiaru"
        return 1
    }
    cg1=$(_jhot_cgroup_cpu "$pid")
    [[ -n $jstat ]] && _jhot_run "$jstat" -gcutil "$pid" >"$dir/jstat-1.txt" 2>&1
    secs=$(awk -v a="$t_start" -v b="$t_end" 'BEGIN { printf "%.2f", b - a }')

    _jhot_task_delta "$dir/tasks-0.tsv" "$dir/tasks-1.tsv" "$secs" "$hz" >"$dir/threads-cpu.tsv"

    # ── liczby zbiorcze ───────────────────────────────────────────────────────
    local pcpu c_app c_gc c_jit c_vm c_jvm nthr last="$dir/threads-$samples.tsv"
    pcpu=$(awk -v a="$p0" -v b="$p1" -v hz="$hz" -v s="$secs" 'BEGIN { printf "%.1f", (b - a) * 100 / (hz * s) }')
    read -r c_app c_gc c_jit c_vm c_jvm < <(awk -F'\t' '{ c[$3] += $2 }
    END { printf "%.1f %.1f %.1f %.1f %.1f\n", c["APP"], c["GC"], c["JIT"], c["VM"], c["JVM"] }' "$dir/threads-cpu.tsv")
    nthr=$(wc -l <"$dir/threads-cpu.tsv")

    local lim=- thr_pct="" thr_s="" a0 b0 c0 a1 b1 c1
    if [[ -n $cg0 && -n $cg1 ]]; then
        read -r lim a0 b0 c0 <<<"$cg0"
        read -r _ a1 b1 c1 <<<"$cg1"
        if ((a1 > a0)); then
            thr_pct=$(((b1 - b0) * 100 / (a1 - a0)))
            thr_s=$(awk -v a="$c0" -v b="$c1" 'BEGIN { printf "%.1f", (b - a) / 1e6 }')
        fi
    fi

    local old="" dfgc="" dygc="" gc_pct=""
    if [[ -s $dir/jstat-0.txt && -s $dir/jstat-1.txt ]]; then
        read -r old dfgc dygc gc_pct < <(_jhot_gc_delta "$dir/jstat-0.txt" "$dir/jstat-1.txt" "$secs")
    fi

    # ── nagłówek ──────────────────────────────────────────────────────────────
    printf '═══ JVM %s · %s · użytkownik %s · uptime %s\n' "$pid" "$main" "$owner" "$(_jhot_dur "$up")"
    printf 'Okno pomiaru %ss · %d× jstack co %ss · wątków systemowych: %d\n' "$secs" "$samples" "$interval" "$nthr"
    printf 'CPU procesu: %s%%' "$pcpu"
    [[ $lim != - ]] && printf ' · limit kontenera: %s rdz. (%s%% z limitu)' "$lim" "$(_jhot_pct "$pcpu" "$(awk -v l="$lim" 'BEGIN { print l * 100 }')")"
    [[ -n $thr_pct ]] && printf ' · throttling: %s%% okresów CFS (%ss)' "$thr_pct" "$thr_s"
    echo
    printf 'Rozkład CPU: aplikacja %s%% · GC %s%% · JIT %s%% · VM %s%% · inne JVM %s%%\n' "$c_app" "$c_gc" "$c_jit" "$c_vm" "$c_jvm"
    if [[ -n $gc_pct ]]; then
        printf 'GC (jstat): Old Gen %s%% · Full GC +%s · Young GC +%s · czas w GC: %s%% okna\n' "$old" "$dfgc" "$dygc" "$gc_pct"
    elif [[ -n $jstat ]]; then
        echo 'GC (jstat): brak danych (PerfDisableSharedMem? inny /tmp?)'
    fi

    # ── najgorętsze wątki ────────────────────────────────────────────────────
    echo
    echo "── Najgorętsze wątki (CPU uśrednione z ${secs}s)"
    local rank=0 h_tid h_cpu h_cat h_name row r_name r_state r_top r_app r_frames
    local shown last_top last_app last_frames verdict focus hints first_hint in_js stable all_run x
    local -a h_st h_top h_app
    while IFS=$'\t' read -r -u 3 h_tid h_cpu h_cat h_name; do
        ((rank >= nthreads)) && break
        _jhot_ge "$h_cpu" 0.5 || {
            ((rank == 0)) && echo '    (żaden wątek nie zużywa istotnie CPU)'
            break
        }
        ((rank++))
        h_st=()
        h_top=()
        h_app=()
        shown=$h_name
        last_top=-
        last_app=-
        last_frames=-
        in_js=0
        for ((s = 1; s <= samples; s++)); do
            row=$(awk -F'\t' -v t="$h_tid" '$1 == t { print; exit }' "$dir/threads-$s.tsv")
            if [[ -n $row ]]; then
                IFS=$'\t' read -r _ r_name r_state r_top r_app r_frames <<<"$row"
                in_js=1
                shown=$r_name
                last_top=$r_top
                last_app=$r_app
                last_frames=$r_frames
                h_st+=("$r_state")
                h_top+=("${r_top%%(*}")
                h_app+=("${r_app%%(*}")
            else
                h_st+=(.)
                h_top+=(.)
                h_app+=(.)
            fi
        done

        printf '\n[%d] %s%% CPU · TID %s · nid=0x%x · "%s" · %s\n' "$rank" "$h_cpu" "$h_tid" "$h_tid" "$shown" "$(_jhot_cat_label "$h_cat")"
        if [[ $last_top == - ]]; then
            if ((in_js)); then
                echo '    Wątek bez stosu Java (wewnętrzny wątek JVM) – patrz rozkład CPU i DIAGNOZA.'
            else echo '    Brak w jstacku – wątek natywny (JNI/agent) albo zakończył się w trakcie okna.'; fi
            continue
        fi

        stable=0
        all_run=1
        for x in "${h_st[@]}"; do [[ $x == RUNNABLE ]] || all_run=0; done
        printf '    stan w próbkach:          %s\n' "${h_st[*]}"
        if _jhot_same "${h_top[@]}"; then
            verdict="stały w $samples/$samples"
            stable=1
        else verdict='zmienny'; fi
        printf '    szczyt stosu:             %s  [%s]\n' "$last_top" "$verdict"
        focus=$last_top
        if [[ $last_app != - ]]; then
            if _jhot_same "${h_app[@]}"; then
                verdict="stała w $samples/$samples"
                stable=1
            else verdict='zmienna'; fi
            printf '    pierwsza ramka aplikacji: %s  [%s]\n' "$last_app" "$verdict"
            focus=$last_app
        fi
        hints=$(_jhot_hints "$last_frames")
        first_hint=${hints%%$'\n'*}
        [[ -n $hints ]] && while IFS= read -r x; do printf '    → %s\n' "$x"; done <<<"$hints"
        echo '    stos (ostatnia próbka):'
        _jhot_thread_block "$dir/jstack-$samples.txt" "$h_tid" | sed -n "2,$((depth + 1))p" | sed 's/^[[:space:]]*/      /'

        if [[ $h_cat == APP ]]; then
            if ((samples >= 2 && stable && all_run)) && _jhot_ge "$h_cpu" 30; then
                findings+=("!!|Wątek \"$shown\" ($h_cpu% CPU) kręci się w $focus – to samo miejsce we wszystkich $samples próbkach.${first_hint:+ $first_hint}")
            elif ((samples == 1)) && _jhot_ge "$h_cpu" 30; then
                findings+=("! |Wątek \"$shown\" ($h_cpu% CPU) – w jedynej próbce: $focus. Uruchom z -s 3, żeby potwierdzić.${first_hint:+ $first_hint}")
            elif _jhot_ge "$h_cpu" 50; then
                findings+=("! |Wątek \"$shown\" ($h_cpu% CPU) jest gorący, ale zmienia miejsce w kodzie (ostatnio $focus) – użyj profilera (async-profiler -e cpu).${first_hint:+ $first_hint}")
            elif [[ -n $first_hint ]] && _jhot_ge "$h_cpu" 20; then
                findings+=("! |Wątek \"$shown\" ($h_cpu% CPU): $first_hint")
            fi
        fi
    done 3<"$dir/threads-cpu.tsv"

    # ── najczęstsze ramki ────────────────────────────────────────────────────
    local hot_frames
    local -a tsvs=()
    for ((s = 1; s <= samples; s++)); do tsvs+=("$dir/threads-$s.tsv"); done
    hot_frames=$(_jhot_hot_frames "${tsvs[@]}")
    echo
    echo '── Najczęstsze miejsca aktywnych wątków (RUNNABLE, bez oczekiwania na I/O, wszystkie próbki)'
    if [[ -n $hot_frames ]]; then
        while IFS=$'\t' read -r x row; do printf '    %4d×  %s\n' "$x" "$row"; done <<<"$hot_frames"
    else
        echo '    (brak aktywnych wątków Java)'
    fi

    # ── stany wątków ─────────────────────────────────────────────────────────
    local n_blocked=0
    echo
    echo '── Stany wątków Java'
    printf '    %-7s %9s %8s %8s %14s %7s\n' próbka RUNNABLE BLOCKED WAITING TIMED_WAITING razem
    for ((s = 1; s <= samples; s++)); do
        awk -F'\t' -v s="$s" '{ c[$3]++; n++ }
      END { printf "    #%-6s %9d %8d %8d %14d %7d\n", s, c["RUNNABLE"], c["BLOCKED"], c["WAITING"], c["TIMED_WAITING"], n }' \
            "$dir/threads-$s.tsv"
    done
    n_blocked=$(awk -F'\t' '$3 == "BLOCKED" { n++ } END { print n + 0 }' "$last")

    # ── blokady ──────────────────────────────────────────────────────────────
    local locks deadlock=0 l_n l_addr l_cls l_own l_frame
    echo
    echo '── Blokady (ostatnia próbka)'
    if grep -q 'Java-level deadlock' "$dir/jstack-$samples.txt"; then
        deadlock=1
        echo '    [!!] DEADLOCK:'
        sed -n '/Found one Java-level deadlock/,$p' "$dir/jstack-$samples.txt" | head -n 40 | sed 's/^/      /'
    fi
    locks=$(_jhot_locks "$dir/jstack-$samples.txt")
    if [[ -n $locks ]]; then
        while IFS=$'\t' read -r l_n l_addr l_cls l_own l_frame; do
            printf '    %d× czeka na %s (%s) – trzyma: "%s" @ %s\n' "$l_n" "$l_addr" "$l_cls" "$l_own" "$l_frame"
        done <<<"$locks"
        IFS=$'\t' read -r l_n l_addr l_cls l_own l_frame <<<"${locks%%$'\n'*}"
    elif ((! deadlock)); then
        echo '    brak rywalizacji o monitory/ReentrantLocki'
        l_n=0
    fi

    # ── grupy wątków ─────────────────────────────────────────────────────────
    local groups g_n g_name n_java
    n_java=$(wc -l <"$last")
    groups=$(awk -F'\t' '{ n = $2; gsub(/[0-9]+/, "#", n); c[n]++ } END { for (n in c) printf "%d\t%s\n", c[n], n }' "$last" |
        sort -t$'\t' -k1,1nr | head -n 5)
    echo
    echo "── Największe grupy wątków (z $n_java w jstacku)"
    while IFS=$'\t' read -r g_n g_name; do printf '    %5d×  %s\n' "$g_n" "$g_name"; done <<<"$groups"
    IFS=$'\t' read -r g_n g_name <<<"${groups%%$'\n'*}"

    # ── reguły diagnozy ──────────────────────────────────────────────────────
    local gc_share jit_share vm_share top_app
    gc_share=$(_jhot_pct "$c_gc" "$pcpu")
    jit_share=$(_jhot_pct "$c_jit" "$pcpu")
    vm_share=$(_jhot_pct "$c_vm" "$pcpu")
    # Serial GC i Full GC w Parallel GC wykonuje VM Thread – jeśli jstat pokazuje dużo GC, to CPU VM to GC
    if [[ -n $gc_pct ]] && _jhot_ge "$gc_pct" 20; then
        gc_share=$((gc_share + vm_share))
        vm_share=0
    fi

    ((deadlock)) && findings=("!!|Deadlock Java – szczegóły w sekcji Blokady." "${findings[@]}")

    if [[ -n $old ]] && _jhot_ge "$old" 95 && ((${dfgc:-0} > 0)); then
        findings+=("!!|Old Gen ${old}% i Full GC +$dfgc w ${secs}s → heap pełny, prawdopodobny wyciek pamięci (GC zjada ${gc_share}% CPU). Dalej: jcmd $pid GC.class_histogram | head -40, potem jcmd $pid GC.heap_dump /tmp/$pid.hprof")
    elif _jhot_ge "$pcpu" 5 && { ((gc_share >= 30)) || { [[ -n $gc_pct ]] && _jhot_ge "$gc_pct" 20; }; }; then
        findings+=("! |GC zużywa ${gc_share}% CPU procesu${gc_pct:+, ${gc_pct}% czasu w GC} → wysokie tempo alokacji albo za mały heap. Dalej: -Xlog:gc*, async-profiler -e alloc.")
    fi
    if _jhot_ge "$pcpu" 5 && ((jit_share >= 30)); then
        if ((up < 600)); then
            findings+=("i |JIT kompiluje (${jit_share}% CPU) – rozgrzewka po starcie, zwykle mija.")
        else findings+=("! |JIT zużywa ${jit_share}% CPU po $(_jhot_dur "$up") działania – deoptymalizacje albo pełny code cache. Dalej: jcmd $pid Compiler.codecache"); fi
    fi
    if _jhot_ge "$pcpu" 5 && ((vm_share >= 20)); then
        findings+=("! |VM Thread zużywa ${vm_share}% CPU – częste safepointy (GC, deoptymalizacje, zrzuty). Dalej: -Xlog:safepoint")
    fi
    if [[ -n $thr_pct ]] && ((thr_pct >= 5)); then
        findings+=("$( ((thr_pct >= 25)) && echo '!!' || echo '! ')|Throttling CPU kontenera: ${thr_pct}% okresów CFS ograniczonych (${thr_s}s w oknie), limit $lim rdz. Część opóźnień wynika z limitu, nie z kodu.")
    fi
    if [[ $lim != - ]] && _jhot_ge "$pcpu" "$(awk -v l="$lim" 'BEGIN { print l * 90 }')"; then
        findings+=("! |JVM zużywa prawie cały limit CPU kontenera (${pcpu}% przy limicie $lim rdz.).")
    fi
    if ((${l_n:-0} >= 3)); then
        findings+=("! |Rywalizacja o blokadę: $l_n wątków czeka na $l_addr ($l_cls), trzyma ją \"$l_own\" w $l_frame.")
    elif ((n_blocked >= 5)); then
        findings+=("! |$n_blocked wątków w stanie BLOCKED – rywalizacja o monitory.")
    fi
    if ((n_java >= 1000)); then
        findings+=("! |Bardzo dużo wątków ($n_java) – największa grupa \"$g_name\": $g_n. Możliwy wyciek wątków / nieograniczona pula.")
    elif ((${g_n:-0} >= 200)); then
        findings+=("! |Grupa wątków \"$g_name\" liczy $g_n – sprawdź, czy pula nie jest nieograniczona.")
    fi
    top_app=$(awk -F'\t' '$3 == "APP" { print $2; exit }' "$dir/threads-cpu.tsv")
    if _jhot_ge "$c_app" 50 && [[ -n $top_app ]] && (($(_jhot_pct "$top_app" "$c_app") < 30)); then
        findings+=("i |CPU aplikacji (${c_app}%) rozłożone na wiele wątków (najgorętszy ma ${top_app}%) – raczej ogólne obciążenie niż jedna pętla.${hot_frames:+ Najczęściej: ${hot_frames%%$'\n'*}}")
    fi
    if grep -qE 'java\.lang\.VirtualThread|jdk\.internal\.vm\.Continuation|"VirtualThread-unparker"' "$dir/jstack-$samples.txt"; then
        findings+=("i |Aplikacja używa wątków wirtualnych – jstack ich nie pokazuje. Pełny zrzut: jcmd $pid Thread.dump_to_file -format=json /tmp/$pid-threads.json")
    fi
    if ! _jhot_ge "$pcpu" 5 && ((${#findings[@]} == 0)); then
        findings+=("i |JVM praktycznie bezczynna (CPU ${pcpu}%) – w tym oknie nie widać problemu z CPU.")
    fi
    ((${#findings[@]})) || findings+=("i |Brak oczywistych anomalii w tym oknie.")
    findings=("${findings[@]//$'\t'/ }")

    # ── DIAGNOZA ─────────────────────────────────────────────────────────────
    local sev f worst="" worst_txt=""
    echo
    echo '── DIAGNOZA'
    for sev in '!!' '! ' 'i '; do
        for f in "${findings[@]}"; do
            [[ ${f%%|*} == "$sev" ]] || continue
            printf '    [%s] %s\n' "$sev" "${f#*|}"
            [[ -z $worst ]] && {
                worst=$sev
                worst_txt=${f#*|}
            }
        done
    done
    echo
    echo "Pliki: $dir"

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$pid" "$pcpu" "$nthr" "$main" "$worst" "$worst_txt" >"$dir/summary.tsv"
}

_jhot_arthas() {
    local pid=$1 dir=$2 n=$3 java owner
    local -a runas=()
    [[ -f ${ARTHAS_JAR:-} ]] || {
        _jhot_err "Tryb --arthas wymaga ARTHAS_JAR=/ścieżka/arthas-boot.jar"
        return 1
    }
    java=$(_jhot_jdk_tool "$pid" java) || {
        _jhot_err "Nie znalazłem java"
        return 1
    }
    owner=$(stat -c %U "/proc/$pid") || return 1
    _jhot_set_runas "$owner" "$pid"
    mkdir -p "$dir" || return 1
    _jhot_log "[$pid] Arthas: thread -n $n"
    _jhot_run "$java" -jar "$ARTHAS_JAR" "$pid" -c "thread -n $n; stop" | tee "$dir/arthas.txt"
}

# ─────────────────────────────────────────────────────────────── funkcja główna ──

jhot() {
    local -x LC_ALL=C
    local pid="" all=0 arthas=0 nthreads=3 samples=3 interval=5 depth=15 out="" app=""
    local opt val v p rc=0 stamp
    local -a pids=() cand=()

    if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
        _jhot_err "jhot wymaga bash ≥ 4.4"
        return 1
    fi

    while (($#)); do
        opt=$1
        val=""
        case $opt in --*=*)
            val=${opt#*=}
            opt=${opt%%=*}
            ;;
        esac
        case $opt in
        -p | --pid | -n | --threads | -s | --samples | -i | --interval | -d | --depth | -o | --out | --app)
            if [[ -z $val ]]; then
                (($# >= 2)) || {
                    _jhot_err "Opcja $opt wymaga wartości"
                    return 2
                }
                val=$2
                shift
            fi
            ;;
        esac
        case $opt in
        -p | --pid) pid=$val ;;
        -n | --threads) nthreads=$val ;;
        -s | --samples) samples=$val ;;
        -i | --interval) interval=$val ;;
        -d | --depth) depth=$val ;;
        -o | --out) out=$val ;;
        --app) app=$val ;;
        --all) all=1 ;;
        -a | --arthas) arthas=1 ;;
        -h | --help)
            _jhot_usage
            return 0
            ;;
        *)
            _jhot_err "Nieznana opcja: $opt"
            _jhot_usage >&2
            return 2
            ;;
        esac
        shift
    done

    for v in nthreads samples interval depth; do
        [[ ${!v} =~ ^[1-9][0-9]*$ ]] || {
            _jhot_err "$v musi być dodatnią liczbą całkowitą (jest: ${!v})"
            return 2
        }
    done
    [[ -z $pid || $pid =~ ^[0-9]+$ ]] || {
        _jhot_err "--pid musi być liczbą (jest: $pid)"
        return 2
    }
    [[ -n $pid ]] && ((all)) && {
        _jhot_err "--pid i --all wykluczają się"
        return 2
    }
    [[ -d /proc/self/task ]] || {
        _jhot_err "jhot działa tylko na Linuksie (/proc)"
        return 1
    }

    stamp=$(date +%Y%m%d-%H%M%S)

    if ((all)); then
        mapfile -t pids < <(_jhot_list_jvms)
        ((${#pids[@]})) || {
            _jhot_err "Nie znaleziono żadnej JVM"
            return 1
        }
        out=${out:-./jhot-all-$stamp}
        _jhot_log "① Znalezione JVM: ${pids[*]}"
    elif [[ -n $pid ]]; then
        [[ -d /proc/$pid ]] || {
            _jhot_err "Proces $pid nie istnieje"
            return 1
        }
        _jhot_is_jvm "$pid" || _jhot_warn "Proces $pid nie wygląda na JVM – próbuję mimo to."
        pids=("$pid")
    else
        _jhot_log "① Szukam najgorętszej JVM…"
        mapfile -t cand < <(_jhot_list_jvms)
        ((${#cand[@]})) || {
            _jhot_err "Nie znaleziono żadnej JVM. Podaj PID: --pid PID"
            return 1
        }
        local ranking
        ranking=$(_jhot_rank_cpu "${cand[@]}")
        while read -r p v; do printf '    %-8s %4s%%  %s\n' "$p" "$v" "$(_jhot_main_class "$p")" >&2; done <<<"$ranking"
        pids=("${ranking%% *}")
    fi
    [[ -n $out ]] || out=./jhot-${pids[0]}-$stamp
    mkdir -p "$out" || return 1

    if ((arthas)); then
        if ((all)); then
            for p in "${pids[@]}"; do _jhot_arthas "$p" "$out/$p" "$nthreads" || rc=1; done
        else
            _jhot_arthas "${pids[0]}" "$out" "$nthreads" || rc=1
        fi
        return $rc
    fi

    if ((! all)); then
        _jhot_analyze "${pids[0]}" "$out" "$nthreads" "$samples" "$interval" "$depth" "$app" >"$out/report.txt" || rc=$?
        _jhot_show "$out/report.txt"
        return $rc
    fi

    # --all: równolegle (ten sam przedział czasu dla wszystkich JVM); subshell = bez komunikatów job control
    _jhot_log "Analizuję równolegle ${#pids[@]} JVM → $out/<PID>/"
    (
        for p in "${pids[@]}"; do
            mkdir -p "$out/$p"
            {
                _jhot_analyze "$p" "$out/$p" "$nthreads" "$samples" "$interval" "$depth" "$app" >"$out/$p/report.txt" ||
                    printf '%s\t-\t-\t%s\tERR\tanaliza nieudana (szczegóły powyżej / w %s)\n' "$p" "$(_jhot_main_class "$p")" "$out/$p" >"$out/$p/summary.tsv"
            } &
        done
        wait
    )

    {
        printf '%-8s %7s %6s  %-36s %s\n' PID 'CPU%' 'WĄTKI' 'MAIN' 'NAJWAŻNIEJSZE'
        cat "$out"/*/summary.tsv 2>/dev/null | sort -t$'\t' -k2,2gr |
            awk -F'\t' '{ m = $4; if (length(m) > 36) m = "…" substr(m, length(m) - 34)
                      printf "%-8s %7s %6s  %-36s [%s] %s\n", $1, $2, $3, m, $5, $6 }'
    } >"$out/summary.txt"
    echo
    _jhot_show "$out/summary.txt"
    echo
    _jhot_log "Pełne raporty: $out/<PID>/report.txt"
}

export -f turn_async_profiler_on
export -f turn_async_profiler_off
export -f java_clear
export -f jhot _jhot_usage _jhot_log _jhot_warn _jhot_err _jhot_now _jhot_ge _jhot_pct _jhot_dur \
    _jhot_stat_fields _jhot_proc_ticks _jhot_uptime _jhot_is_jvm _jhot_list_jvms _jhot_rank_cpu \
    _jhot_main_class _jhot_set_runas _jhot_run _jhot_jdk_tool _jhot_task_snapshot _jhot_task_delta \
    _jhot_parse_jstack _jhot_thread_block _jhot_locks _jhot_hot_frames _jhot_gc_delta _jhot_cgroup_cpu \
    _jhot_hints _jhot_cat_label _jhot_same _jhot_show _jhot_analyze _jhot_arthas
