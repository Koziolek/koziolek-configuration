#!/usr/bin/env bash
# Testy jhot (bash/functions.d/030_function_java.sh) — czyste funkcje na syntetycznych danych,
# bez prawdziwej JVM; opcjonalny test dymny na realnym JDK (pomijany, gdy brak jstack/java).

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export C_RED='' C_GREEN='' C_ORANGE='' C_BLUE='' C_LBLUE=''
export C_PURPLE='' C_CYAN='' C_WHITE='' C_YELLOW='' C_BOLD='' C_NC=''
export SUDO='' RESET_SUDO=0

# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/010_function_log.sh"
# shellcheck source=/dev/null
. "$PROJECT_ROOT/bash/functions.d/030_function_java.sh"

oneTimeSetUp() {
    TMP="$(mktemp -d)"
    cat >"$TMP/jstack.txt" <<'EOF'
2026-11-03 10:00:00
Full thread dump OpenJDK 64-Bit Server VM (21+35 mixed mode):

"http-nio-8080-exec-1" #30 [4660] daemon prio=5 os_prio=0 cpu=100ms elapsed=5s tid=0x00007f nid=4660 runnable [0x00007f]
   java.lang.Thread.State: RUNNABLE
	at java.base/java.util.regex.Pattern$Loop.match(Pattern.java:4800)
	at org.springframework.web.Filter.doFilter(Filter.java:10)
	at pl.firma.app.Service.compute(Service.java:42)
	at pl.firma.app.Controller.get(Controller.java:7)

"worker-2" #31 daemon prio=5 os_prio=0 tid=0x00007f nid=0x1235 waiting on condition [0x00007f]
   java.lang.Thread.State: WAITING (parking)
	at java.base@21/jdk.internal.misc.Unsafe.park(Native Method)
	at pl.firma.app.Queue.take(Queue.java:3)

"VM Thread" os_prio=0 cpu=1ms elapsed=5s tid=0x00007f nid=0x1236 runnable

Found one Java-level deadlock:
=============================
"after-deadlock" #99 nid=0x9999 runnable
   java.lang.Thread.State: RUNNABLE
	at pl.firma.app.Never.seen(Never.java:1)
EOF
    cat >"$TMP/locks.txt" <<'EOF'
"owner" #1 nid=0x10 runnable
   java.lang.Thread.State: RUNNABLE
	at pl.firma.app.Holder.hold(Holder.java:9)
	- locked <0x000000076ab62208> (a java.lang.Object)

"w1" #2 nid=0x11 waiting for monitor entry
   java.lang.Thread.State: BLOCKED (on object monitor)
	at pl.firma.app.Waiter.wait(Waiter.java:5)
	- waiting to lock <0x000000076ab62208> (a java.lang.Object)

"w2" #3 nid=0x12 waiting for monitor entry
   java.lang.Thread.State: BLOCKED (on object monitor)
	at pl.firma.app.Waiter.wait(Waiter.java:5)
	- waiting to lock <0x000000076ab62208> (a java.lang.Object)
EOF
}

oneTimeTearDown() {
    rm -rf "$TMP"
}

# --- _jhot_dur / _jhot_pct / _jhot_ge ----------------------------------------

testDur() {
    assertEquals '5s' "$(_jhot_dur 5)"
    assertEquals '1m05s' "$(_jhot_dur 65)"
    assertEquals '1h01m' "$(_jhot_dur 3660)"
    assertEquals '2d03h' "$(_jhot_dur $((2 * 86400 + 3 * 3600)))"
    assertEquals '0s' "$(_jhot_dur)"
}

testPct() {
    assertEquals '50' "$(_jhot_pct 1 2)"
    assertEquals '0' "$(_jhot_pct 5 0)"
    assertEquals '33' "$(_jhot_pct 1 3)"
}

testGe() {
    _jhot_ge 1.5 1.5
    assertTrue 'równe' $?
    _jhot_ge 2 1.9
    assertTrue 'większe' $?
    _jhot_ge 0.4 0.5
    assertFalse 'mniejsze' $?
}

# --- _jhot_parse_jstack -------------------------------------------------------

testParseJstackDecimalNid() {
    local out
    out="$(_jhot_parse_jstack "$TMP/jstack.txt" "")"
    assertContains 'nid dziesiętny' "$out" "4660	http-nio-8080-exec-1	RUNNABLE"
}

testParseJstackHexNid() {
    local out
    out="$(_jhot_parse_jstack "$TMP/jstack.txt" "")"
    # 0x1235 = 4661
    assertContains 'nid hex -> dziesiętny' "$out" "4661	worker-2	WAITING"
}

testParseJstackFirstAppFrameDefault() {
    local line
    line="$(_jhot_parse_jstack "$TMP/jstack.txt" "" | awk -F'\t' '$1 == 4660')"
    assertEquals 'szczyt stosu' 'java.util.regex.Pattern$Loop.match(Pattern.java:4800)' "$(cut -f4 <<<"$line")"
    assertEquals 'pierwsza ramka aplikacji (poza bibliotekami)' 'pl.firma.app.Service.compute(Service.java:42)' "$(cut -f5 <<<"$line")"
}

testParseJstackAppPrefix() {
    local line
    line="$(_jhot_parse_jstack "$TMP/jstack.txt" "org.springframework" | awk -F'\t' '$1 == 4660')"
    assertEquals 'z --app pierwsza ramka z prefiksem' 'org.springframework.web.Filter.doFilter(Filter.java:10)' "$(cut -f5 <<<"$line")"
}

testParseJstackModulePrefixStripped() {
    local line
    line="$(_jhot_parse_jstack "$TMP/jstack.txt" "" | awk -F'\t' '$1 == 4661')"
    assertEquals 'prefiks modułu java.base@21/ obcięty' 'jdk.internal.misc.Unsafe.park(Native Method)' "$(cut -f4 <<<"$line")"
}

testParseJstackNoStackThread() {
    local line
    line="$(_jhot_parse_jstack "$TMP/jstack.txt" "" | awk -F'\t' '$1 == 4662')"
    assertEquals 'VM Thread: stan -, brak stosu' "4662	VM Thread	-	-	-	-" "$line"
}

testParseJstackDeadlockCutsParsing() {
    local out
    out="$(_jhot_parse_jstack "$TMP/jstack.txt" "")"
    assertNotContains 'wątki po sekcji deadlock pominięte' "$out" 'after-deadlock'
    assertEquals '3 wątki' 3 "$(wc -l <<<"$out")"
}

# --- _jhot_task_delta ---------------------------------------------------------

testTaskDeltaCategoriesAndCpu() {
    local -x LC_ALL=C # jhot/_jhot_analyze wymuszają C; tu wołamy funkcje wprost
    printf '1\t100\tmain\n2\t0\tGC Thread#0\n3\t10\tC2 CompilerThre\n4\t0\tVM Thread\n5\t0\tFinalizer\n' >"$TMP/t0.tsv"
    printf '1\t300\tmain\n2\t50\tGC Thread#0\n3\t10\tC2 CompilerThre\n4\t20\tVM Thread\n5\t1\tFinalizer\n6\t100\tnew\n' >"$TMP/t1.tsv"
    local out
    out="$(_jhot_task_delta "$TMP/t0.tsv" "$TMP/t1.tsv" 2 100)"
    # main: 200 ticków / (100*2) = 100%
    assertEquals 'najgorętszy pierwszy' "1	100.0	APP	main" "$(head -n1 <<<"$out")"
    assertContains 'nowy wątek liczony od zera' "$out" "6	50.0	APP	new"
    assertContains 'GC' "$out" "2	25.0	GC	GC Thread#0"
    assertContains 'JIT' "$out" "3	0.0	JIT	C2 CompilerThre"
    assertContains 'VM' "$out" "4	10.0	VM	VM Thread"
    assertContains 'JVM' "$out" "5	0.5	JVM	Finalizer"
}

# --- _jhot_gc_delta -----------------------------------------------------------

testGcDelta() {
    local -x LC_ALL=C # jhot/_jhot_analyze wymuszają C; tu wołamy funkcje wprost
    printf 'Picked up JAVA_TOOL_OPTIONS: -Xmx1g\n  S0  S1  E  O  M  CCS  YGC  YGCT  FGC  FGCT  GCT\n 0 0 10 50.0 90 80 10 0.5 1 1.0 1.5\n' >"$TMP/j0.txt"
    printf 'Picked up JAVA_TOOL_OPTIONS: -Xmx1g\n  S0  S1  E  O  M  CCS  YGC  YGCT  FGC  FGCT  GCT\n 0 0 10 97.5 90 80 15 0.9 3 3.0 4.5\n' >"$TMP/j1.txt"
    assertEquals '97.5 2 5 30.0' "$(_jhot_gc_delta "$TMP/j0.txt" "$TMP/j1.txt" 10)"
}

testGcDeltaNoData() {
    : >"$TMP/empty.txt"
    assertEquals '' "$(_jhot_gc_delta "$TMP/empty.txt" "$TMP/empty.txt" 10)"
}

# --- _jhot_locks --------------------------------------------------------------

testLocks() {
    assertEquals "2	<0x000000076ab62208>	java.lang.Object	owner	pl.firma.app.Holder.hold(Holder.java:9)" \
        "$(_jhot_locks "$TMP/locks.txt")"
}

testLocksNone() {
    assertEquals '' "$(_jhot_locks "$TMP/jstack.txt")"
}

# --- _jhot_hints / _jhot_same / _jhot_cat_label -------------------------------

testHintsRegex() {
    local out
    out="$(_jhot_hints 'java.util.regex.Pattern$Loop.match | foo')"
    assertContains 'ReDoS' "$out" 'ReDoS'
}

testHintsMultiple() {
    local out
    out="$(_jhot_hints 'com.fasterxml.jackson.Foo | java.math.BigDecimal.add')"
    assertContains 'JSON' "$out" 'Serializacja/parsowanie'
    assertContains 'BigDecimal' "$out" 'BigDecimal'
    assertEquals '2 wskazówki' 2 "$(wc -l <<<"$out")"
}

testHintsNone() {
    assertEquals '' "$(_jhot_hints 'pl.firma.app.Foo.bar')"
}

testSame() {
    _jhot_same a a a
    assertTrue 'równe' $?
    _jhot_same a a b
    assertFalse 'różne' $?
    _jhot_same - -
    assertFalse 'myślnik nie liczy się jako stały' $?
    _jhot_same . .
    assertFalse 'kropka nie liczy się jako stała' $?
}

testCatLabel() {
    assertEquals 'aplikacja' "$(_jhot_cat_label APP)"
    assertEquals 'kompilator JIT' "$(_jhot_cat_label JIT)"
    assertEquals 'wewnętrzny JVM' "$(_jhot_cat_label JVM)"
}

# --- _jhot_main_class ---------------------------------------------------------
# Czyta /proc/PID/cmdline — uruchamiamy atrapę procesu z potrzebnymi argumentami.

# Atrapa procesu o zadanym cmdline: `bash -s -- ARGS` czeka na stdin (sleep), więc /proc/PID/cmdline
# to "bash -s -- ARGS"; opcje przed ARGS _jhot_main_class pomija jako -*.
_main_class_of() {
    local pid out
    bash -s -- "$@" < <(sleep 5) &
    pid=$!
    sleep 0.2
    out="$(_jhot_main_class "$pid")"
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    echo "$out"
}

testMainClassJar() {
    assertEquals 'app.jar' "$(_main_class_of -jar /x/dir/app.jar)"
}

testMainClassClass() {
    assertEquals 'pl.firma.Main' "$(_main_class_of -Xmx1g -cp /a:/b pl.firma.Main arg)"
}

testMainClassModule() {
    assertEquals 'mod/pl.Main' "$(_main_class_of -p /mods -m mod/pl.Main)"
}

testMainClassUnknown() {
    assertEquals '?' "$(_main_class_of -Xmx1g)"
}

# --- walidacja argumentów jhot ------------------------------------------------

testUsageOnHelp() {
    local out
    out="$(jhot -h)"
    assertEquals 0 $?
    assertContains "$out" 'Użycie: jhot'
    out="$(jhot --help)"
    assertContains "$out" '--arthas'
}

testNoValueReturns2() {
    jhot --pid >/dev/null 2>&1
    assertEquals 2 $?
    jhot -n >/dev/null 2>&1
    assertEquals 2 $?
}

testUnknownOptionReturns2() {
    jhot --bogus >/dev/null 2>&1
    assertEquals 2 $?
}

testBadNumberReturns2() {
    jhot -s abc >/dev/null 2>&1
    assertEquals 2 $?
    jhot -n 0 >/dev/null 2>&1
    assertEquals 2 $?
    jhot --pid x1 >/dev/null 2>&1
    assertEquals 2 $?
}

testPidAndAllExclusive() {
    local err
    err="$(jhot --pid 1 --all 2>&1 >/dev/null)"
    assertEquals 2 $?
    assertContains "$err" 'wykluczają się'
}

testEqualsFormAccepted() {
    # --pid=1 --all → ten sam błąd wykluczenia, więc postać z '=' została sparsowana
    local err
    err="$(jhot --pid=1 --all 2>&1 >/dev/null)"
    assertContains "$err" 'wykluczają się'
    err="$(jhot --samples=zero 2>&1 >/dev/null)"
    assertContains "$err" 'samples musi być'
}

testNonexistentPid() {
    jhot --pid 999999999 >/dev/null 2>&1
    assertEquals 1 $?
}

testFunctionsExported() {
    local f
    for f in jhot _jhot_analyze _jhot_parse_jstack _jhot_hints; do
        bash -c "declare -F $f >/dev/null" 2>/dev/null
        assertTrue "$f widoczna w procesie potomnym" $?
    done
}

testSourcingChangesNoShellOptions() {
    local out
    out="$(bash -c ". '$PROJECT_ROOT/bash/functions.d/030_function_java.sh'; echo \"\$-\"" 2>&1)"
    assertNotContains 'brak set -e' "$out" 'e'
}

# --- test dymny na prawdziwej JVM ---------------------------------------------

testSmokeRealJvm() {
    local java jstack tmp pid out
    java="$(command -v java)" || java=''
    jstack="$(command -v jstack)" || jstack=''
    if [[ -z $java || -z $jstack || ! -d /proc/self/task ]]; then
        startSkipping
    fi
    tmp="$(mktemp -d)"
    cat >"$tmp/Spin.java" <<'EOF'
public class Spin {
    public static void main(String[] a) throws Exception {
        long x = 0;
        while (true) { x += System.nanoTime() % 7; if (x == 42) System.out.println(x); }
    }
}
EOF
    "$java" "$tmp/Spin.java" >/dev/null 2>&1 &
    pid=$!
    sleep 3
    out="$(cd "$tmp" && jhot --pid "$pid" -s 1 -i 1 -o "$tmp/out" 2>/dev/null)"
    local rc=$?
    kill "$pid" 2>/dev/null
    pkill -P "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    assertEquals 'kod wyjścia' 0 "$rc"
    assertContains "$out" '── DIAGNOZA'
    assertContains "$out" "═══ JVM"
    rm -rf "$tmp"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
