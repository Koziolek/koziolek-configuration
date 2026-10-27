#!/usr/bin/env bash
# Testy jednostkowe: lista pakietów cargo/go/cabal (packages/commons/lang_packages.sh) i ich
# instalacja/aktualizacja (lang_packages_apply.sh). `asdf` to skrypt w $_TMP — loguje wywołania
# i przy `exec go|cabal install` kładzie binarkę w katalogu docelowym.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIST_FILE="$PROJECT_ROOT/packages/commons/lang_packages.sh"

setUp() {
    _TMP="$(mktemp -d)"
    _LOG="$_TMP/calls.log"
    : >"$_LOG"
    export ASDF_BIN="$_TMP/asdf"
    export LANG_PACKAGES_BIN_DIR="$_TMP/bin"
    export ASDF_DATA_DIR="$_TMP/asdf-data"
    _OLD_PATH="$PATH"
    mkdir -p "$_TMP/path" "$_TMP/ghc-install/bin"
    : >"$_TMP/ghc-install/bin/ghc"
    chmod +x "$_TMP/ghc-install/bin/ghc"
    # Hermetyczny PATH: tylko symlinki do podstawowych poleceń. Prawdziwe difft/shfmt/shellcheck/linthis
    # hosta (np. shellcheck w /usr/bin na runnerze CI) nie mogą udawać zainstalowanych.
    local t src
    for t in bash env mkdir tr chmod cat grep sed awk uniq sort head dirname rm wc mktemp date; do
        src="$(command -v "$t" 2>/dev/null)" && ln -s "$src" "$_TMP/path/$t"
    done
    PATH="$_TMP/path"
    unset ASDF_MISSING ASDF_FAIL
    unset CARGO_PACKAGES GO_PACKAGES CABAL_PACKAGES
    # shellcheck source=/dev/null
    . "$PROJECT_ROOT/packages/commons/lang_packages_apply.sh"
    CARGO_PACKAGES=("difftastic|difft" linthis)
    GO_PACKAGES=(mvdan.cc/sh/v3/cmd/shfmt@latest)
    CABAL_PACKAGES=(ShellCheck)
}

tearDown() {
    PATH="$_OLD_PATH"
    rm -rf "$_TMP"
}

# $ASDF_MISSING — toolchainy, których `asdf which` nie zna; $ASDF_FAIL — pakiety, przy których `exec` pada.
_mock_asdf() {
    cat >"$ASDF_BIN" <<MOCK
#!/usr/bin/env bash
case "\$1" in
    which) echo "asdf which \$2" >> "$_LOG"; case " \${ASDF_MISSING:-} " in *" \$2 "*) exit 1;; esac; exit 0;;
    where) echo "asdf where \$2" >> "$_LOG"; case " \${ASDF_MISSING:-} " in *" \$2 "*) exit 1;; esac; printf '%s' "$_TMP/ghc-install"; exit 0;;
    reshim) echo "asdf reshim" >> "$_LOG"; exit 0;;
    exec)
        shift
        echo "exec \$* GOBIN=\${GOBIN:-} SHIMS=\$([[ \$PATH == $ASDF_DATA_DIR/shims:* ]] && echo yes || echo no)" >> "$_LOG"
        last="\${*: -1}"
        case " \${ASDF_FAIL:-} " in *" \$last "*) exit 1;; esac
        if [ "\$1 \$2" = "go install" ] || [ "\$1 \$2" = "cabal install" ]; then
            name="\${last%@*}"; name="\${name##*/}"
            mkdir -p "$LANG_PACKAGES_BIN_DIR"
            f="$LANG_PACKAGES_BIN_DIR/\$(echo "\$name" | tr '[:upper:]' '[:lower:]')"
            : > "\$f"; chmod +x "\$f"
        fi
        exit 0;;
esac
exit 0
MOCK
    chmod +x "$ASDF_BIN"
}

_calls() { grep '^exec' "$_LOG" | sed 's/ GOBIN=.*//'; }

# ---------------------------------------------------------------- lista

testSourcingListHasNoSideEffects() {
    local out
    out="$(bash -c ". '$LIST_FILE'" 2>&1)"
    assertEquals "" "$out"
}

testListsContainCurrentTools() {
    unset CARGO_PACKAGES GO_PACKAGES CABAL_PACKAGES
    # shellcheck source=/dev/null
    . "$LIST_FILE"
    assertContains "${CARGO_PACKAGES[*]}" "difftastic|difft"
    assertContains "${CARGO_PACKAGES[*]}" "linthis"
    assertContains "${GO_PACKAGES[*]}" "mvdan.cc/sh/v3/cmd/shfmt@latest"
    assertContains "${CABAL_PACKAGES[*]}" "ShellCheck"
}

testListEntriesAreWellFormed() {
    unset CARGO_PACKAGES GO_PACKAGES CABAL_PACKAGES
    # shellcheck source=/dev/null
    . "$LIST_FILE"
    local e
    for e in "${CARGO_PACKAGES[@]}" "${GO_PACKAGES[@]}" "${CABAL_PACKAGES[@]}"; do
        assertTrue "poprawny wpis '$e'" "[[ '$e' =~ ^[A-Za-z0-9._/@-]+(\|[A-Za-z0-9._-]+)?$ ]]"
    done
}

testListsHaveNoDuplicates() {
    unset CARGO_PACKAGES GO_PACKAGES CABAL_PACKAGES
    # shellcheck source=/dev/null
    . "$LIST_FILE"
    assertEquals "" "$(printf '%s\n' "${CARGO_PACKAGES[@]}" | sort | uniq -d)"
}

# ---------------------------------------------------------------- cargo

testCargoInstallUsesLockedViaAsdf() {
    _mock_asdf
    install_cargo_packages >/dev/null
    assertEquals "exec cargo install --locked difftastic
exec cargo install --locked linthis" "$(_calls)"
}

testCargoInstallSkipsPresentBinary() {
    _mock_asdf
    : >"$_TMP/path/difft"
    chmod +x "$_TMP/path/difft"
    install_cargo_packages >/dev/null
    assertEquals "tylko linthis" "exec cargo install --locked linthis" "$(_calls)"
}

testCargoInstallSkipsBinaryInCargoHomeOutsidePath() {
    _mock_asdf
    export CARGO_HOME="$_TMP/cargo"
    mkdir -p "$CARGO_HOME/bin"
    : >"$CARGO_HOME/bin/linthis"
    chmod +x "$CARGO_HOME/bin/linthis"
    install_cargo_packages >/dev/null
    unset CARGO_HOME
    assertEquals "tylko difftastic" "exec cargo install --locked difftastic" "$(_calls)"
}

testCargoUpdateAlwaysRunsInstall() {
    _mock_asdf
    : >"$_TMP/path/difft"
    chmod +x "$_TMP/path/difft"
    update_cargo_packages >/dev/null
    assertContains "$(_calls)" "exec cargo install --locked difftastic"
    assertContains "$(_calls)" "exec cargo install --locked linthis"
}

testCargoRunsWithAsdfShimsInPath() {
    _mock_asdf
    install_cargo_packages >/dev/null
    assertContains "$(grep '^exec' "$_LOG" | head -1)" "SHIMS=yes"
}

testCargoMissingToolchainWarnsAndSkips() {
    _mock_asdf
    export ASDF_MISSING="cargo"
    local out rc
    out="$(install_cargo_packages)"
    rc=$?
    assertEquals 0 "$rc"
    assertContains "$out" "cargo niedostępne w asdf"
    assertEquals "" "$(_calls)"
}

testCargoFailureOfOneDoesNotStopOthers() {
    _mock_asdf
    export ASDF_FAIL="difftastic"
    local out rc
    out="$(install_cargo_packages)"
    rc=$?
    assertEquals 0 "$rc"
    assertContains "$(_calls)" "exec cargo install --locked linthis"
    assertContains "$out" "nie udało się: difftastic"
}

testNewCargoEntryIsPickedUp() {
    _mock_asdf
    CARGO_PACKAGES+=(ripgrep)
    install_cargo_packages >/dev/null
    assertContains "$(_calls)" "exec cargo install --locked ripgrep"
}

# ---------------------------------------------------------------- go

testGoInstallSetsGobinAndCreatesBinary() {
    _mock_asdf
    install_go_packages >/dev/null
    assertContains "$(grep '^exec go' "$_LOG")" "exec go install mvdan.cc/sh/v3/cmd/shfmt@latest GOBIN=$LANG_PACKAGES_BIN_DIR"
    assertTrue "shfmt w katalogu docelowym" "[ -e '$LANG_PACKAGES_BIN_DIR/shfmt' ]"
}

testGoSecondInstallDoesNothing() {
    _mock_asdf
    install_go_packages >/dev/null
    : >"$_LOG"
    local out
    out="$(install_go_packages)"
    assertEquals "" "$(_calls)"
    assertContains "$out" "już zainstalowany"
}

testGoUpdateReinstalls() {
    _mock_asdf
    install_go_packages >/dev/null
    : >"$_LOG"
    update_go_packages >/dev/null
    assertEquals "exec go install mvdan.cc/sh/v3/cmd/shfmt@latest" "$(_calls)"
}

# ---------------------------------------------------------------- cabal

testCabalInstallRefreshesIndexOnceThenInstallsToBinDir() {
    _mock_asdf
    CABAL_PACKAGES=(ShellCheck hlint)
    install_cabal_packages >/dev/null
    assertEquals "exec cabal update
exec cabal install --with-compiler=$_TMP/ghc-install/bin/ghc --install-method=copy --overwrite-policy=always --installdir=$LANG_PACKAGES_BIN_DIR ShellCheck
exec cabal install --with-compiler=$_TMP/ghc-install/bin/ghc --install-method=copy --overwrite-policy=always --installdir=$LANG_PACKAGES_BIN_DIR hlint" "$(_calls)"
    assertTrue "shellcheck (małe litery) w katalogu docelowym" "[ -e '$LANG_PACKAGES_BIN_DIR/shellcheck' ]"
}

testCabalUsesGhcFromAsdfPluginNotShim() {
    _mock_asdf
    install_cabal_packages >/dev/null
    assertContains "kompilator z asdf where ghc" "$(_calls)" "--with-compiler=$_TMP/ghc-install/bin/ghc"
}

testCabalWithoutGhcWarnsAndDoesNotInstall() {
    _mock_asdf
    export ASDF_MISSING="ghc"
    local out rc
    out="$(install_cabal_packages)"
    rc=$?
    assertEquals 0 "$rc"
    assertContains "$out" "ghc z asdf niedostępny"
    assertContains "$out" "nie udało się: ShellCheck"
    assertNotContains "$(_calls)" "cabal install"
}

testCabalSecondInstallDoesNothing() {
    _mock_asdf
    install_cabal_packages >/dev/null
    : >"$_LOG"
    install_cabal_packages >/dev/null
    assertEquals "" "$(_calls)"
}

testCabalMissingToolchainWarnsAndSkips() {
    _mock_asdf
    export ASDF_MISSING="cabal"
    local out
    out="$(install_cabal_packages)"
    assertContains "$out" "cabal niedostępne w asdf"
    assertEquals "" "$(_calls)"
}

# ---------------------------------------------------------------- wspólne

testWrapperRunsCargoThenGoThenCabal() {
    _mock_asdf
    install_lang_packages >/dev/null
    local order
    order="$(_calls | awk '{print $2}' | uniq | tr '\n' ' ')"
    assertEquals "cargo go cabal " "$order"
}

testUpdateWrapperRunsAllThree() {
    _mock_asdf
    update_lang_packages >/dev/null
    local order
    order="$(_calls | awk '{print $2}' | uniq | tr '\n' ' ')"
    assertEquals "cargo go cabal " "$order"
}

testAsdfMissingIsWarningNotError() {
    local out rc
    out="$(install_lang_packages)"
    rc=$?
    assertEquals 0 "$rc"
    assertContains "$out" "asdf nie zainstalowany"
}

testInvalidEntryIsReportedAndSkipped() {
    _mock_asdf
    CARGO_PACKAGES=("a|b|c" linthis)
    local out
    out="$(install_cargo_packages)"
    assertContains "$out" "Niepoprawny wpis listy cargo"
    assertContains "$(_calls)" "exec cargo install --locked linthis"
}

testWorksUnderStrictModeOfCaller() {
    _mock_asdf
    local out
    out="$(bash -c "set -Eeuo pipefail; trap 'echo ERRTRAP' ERR
        export ASDF_BIN='$ASDF_BIN' LANG_PACKAGES_BIN_DIR='$LANG_PACKAGES_BIN_DIR' ASDF_DATA_DIR='$ASDF_DATA_DIR'
        . '$PROJECT_ROOT/packages/commons/lang_packages_apply.sh'
        ASDF_FAIL=linthis install_cargo_packages; echo AFTER" 2>&1)"
    assertContains "$out" "AFTER"
    assertNotContains "$out" "ERRTRAP"
}

# shellcheck source=/dev/null
. "${SHUNIT2:-/opt/shunit2/shunit2}"
