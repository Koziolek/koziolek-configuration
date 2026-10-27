#!/usr/bin/env bash
# Instalacja i aktualizacja narzędzi z listy packages/commons/lang_packages.sh.
# Sourcowane, nie wykonywane. Wspólne dla {ubuntu,vanilla,redhat,mac}/{install,update}.sh.
#
#   install_cargo_packages / update_cargo_packages   cargo install --locked <crate>
#   install_go_packages    / update_go_packages      go install <ścieżka@wersja>
#   install_cabal_packages / update_cabal_packages   cabal install <pakiet> (indeks Hackage odświeżany raz)
#   install_lang_packages  / update_lang_packages    wszystkie trzy, w tej kolejności
#
# install pomija pakiet, którego binarka już jest; update uruchamia instalację zawsze (instaluje też
# brakujące; cargo/cabal same rozpoznają, że nic nowego nie ma). Toolchainy pochodzą z asdf
# (ASDF_TOOLS w sdk_tools.sh), więc jego brak albo brak toolchaina to ostrzeżenie i pominięcie listy.
# Zawsze `return 0`: błąd jednego pakietu to ostrzeżenie i podsumowanie na końcu, nie przerwanie
# reszty ani skryptu wołającego (`set -Eeuo pipefail`).
#
# Zmienne (domyślnie jak w skryptach; nadpisywane w testach):
#   ASDF_BIN             binarka asdf (domyślnie ~/.local/bin/asdf)
#   ASDF_DATA_DIR        katalog danych asdf (domyślnie ~/.asdf) — stąd shimy w PATH narzędzi
#   CARGO_HOME           gdzie cargo kładzie binarki (domyślnie ~/.cargo)
#   LANG_PACKAGES_BIN_DIR  gdzie lądują binarki go/cabal (domyślnie ~/.local/bin, jak claude/git-bug)

_LANG_PACKAGES_APPLY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packages/commons/lang_packages.sh
source "$_LANG_PACKAGES_APPLY_DIR/lang_packages.sh"

_lang_summary() {
    local label="$1"
    shift
    if [ "$#" -gt 0 ]; then
        echo "⚠️  $label — nie udało się: $*"
    fi
}

_lang_bin_dir() { echo "${LANG_PACKAGES_BIN_DIR:-$HOME/.local/bin}"; }

# Uruchamia narzędzie toolchaina przez asdf z shimami w PATH (cabal szuka ghc w PATH, a skrypt
# instalacyjny nie ma shimów w środowisku).
_lang_run() {
    local asdf_bin="${ASDF_BIN:-$HOME/.local/bin/asdf}"
    PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH" "$asdf_bin" exec "$@"
}

# Czy toolchain jest dostępny (asdf ma jego binarkę).
_lang_has_tool() {
    local asdf_bin="${ASDF_BIN:-$HOME/.local/bin/asdf}"
    "$asdf_bin" which "$1" >/dev/null 2>&1
}

# cargo instaluje do ${CARGO_HOME:-~/.cargo}/bin, którego skrypt instalacyjny nie ma w PATH
_lang_binary_present() {
    command -v "$1" >/dev/null 2>&1 ||
        [ -x "$(_lang_bin_dir)/$1" ] ||
        [ -x "${CARGO_HOME:-$HOME/.cargo}/bin/$1" ]
}

# $1 = cargo|go|cabal; $2 = wpis listy → "pakiet binarka" (spacja; pakiet/ścieżka nie ma spacji)
_lang_parse_entry() {
    local kind="$1" entry="$2" pkg bin extra
    IFS='|' read -r pkg bin extra <<<"$entry"
    if [ -z "$pkg" ] || [ -n "$extra" ]; then
        return 1
    fi
    if [ -z "$bin" ]; then
        case "$kind" in
        go)
            bin="${pkg%@*}"
            bin="${bin##*/}"
            ;;
        *) bin="$(echo "$pkg" | tr '[:upper:]' '[:lower:]')" ;;
        esac
    fi
    echo "$pkg $bin"
}

# $1 = cargo|go|cabal; $2 = install|update; reszta = wpisy listy (bez namerefów — bash 3.2 na macOS)
_lang_packages_run() {
    local kind="$1" mode="$2"
    shift 2
    local packages=("$@")
    _LANG_CABAL_INDEX_REFRESHED=

    local asdf_bin="${ASDF_BIN:-$HOME/.local/bin/asdf}"
    if [ ! -x "$asdf_bin" ]; then
        echo "⚠️  asdf nie zainstalowany — pomijam pakiety $kind"
        return 0
    fi
    if [ "${#packages[@]}" -eq 0 ]; then
        return 0
    fi
    if ! _lang_has_tool "$kind"; then
        echo "⚠️  $kind niedostępne w asdf — pomijam pakiety $kind"
        return 0
    fi

    local failed=() entry parsed pkg bin
    for entry in "${packages[@]}"; do
        if ! parsed="$(_lang_parse_entry "$kind" "$entry")"; then
            echo "⚠️  Niepoprawny wpis listy $kind: '$entry' (oczekiwane pakiet albo pakiet|binarka)"
            failed+=("$entry")
            continue
        fi
        read -r pkg bin <<<"$parsed"
        if [ "$mode" = install ] && _lang_binary_present "$bin"; then
            echo "$kind: $pkg już zainstalowany"
            continue
        fi
        echo "$kind: $pkg..."
        _lang_package_install "$kind" "$pkg" || failed+=("$pkg")
    done
    "$asdf_bin" reshim >/dev/null 2>&1 || true
    _lang_summary "pakiety $kind" ${failed[@]+"${failed[@]}"}
    return 0
}

# --locked: użyj Cargo.lock pakietu. Bez tego cargo dobiera najnowsze zależności semver, a te
# (np. tree-sitter-language) wymuszają nowszego rustc niż daje asdf → "rustc X is not supported by
# the following packages". Cabal i go trafiają do ~/.local/bin (na PATH), więc nie trzeba shimów.
_lang_package_install() {
    local kind="$1" pkg="$2" dir
    dir="$(_lang_bin_dir)"
    case "$kind" in
    cargo) _lang_run cargo install --locked "$pkg" ;;
    go)
        mkdir -p "$dir" || return 1
        GOBIN="$dir" _lang_run go install "$pkg"
        ;;
    cabal)
        mkdir -p "$dir" || return 1
        # indeks Hackage odświeżany raz na przebieg i tylko, gdy coś faktycznie się instaluje
        if [ -z "$_LANG_CABAL_INDEX_REFRESHED" ]; then
            _LANG_CABAL_INDEX_REFRESHED=1
            _lang_run cabal update >/dev/null 2>&1 || true
        fi
        # Kompilator wskazany wprost: shim `ghc` jest wspólny z pluginem `haskell` (stack), który
        # wygrywa, gdy ma wersję w ~/.tool-versions — cabal budowałby wtedy ze starym ghc.
        local ghc_dir
        ghc_dir="$("${ASDF_BIN:-$HOME/.local/bin/asdf}" where ghc 2>/dev/null)" || ghc_dir=""
        if [ -z "$ghc_dir" ] || [ ! -x "$ghc_dir/bin/ghc" ]; then
            echo "⚠️  ghc z asdf niedostępny — nie instaluję $pkg"
            return 1
        fi
        _lang_run cabal install --with-compiler="$ghc_dir/bin/ghc" \
            --install-method=copy --overwrite-policy=always --installdir="$dir" "$pkg"
        ;;
    *) return 1 ;;
    esac
}

install_cargo_packages() { _lang_packages_run cargo install ${CARGO_PACKAGES[@]+"${CARGO_PACKAGES[@]}"}; }
update_cargo_packages() { _lang_packages_run cargo update ${CARGO_PACKAGES[@]+"${CARGO_PACKAGES[@]}"}; }
install_go_packages() { _lang_packages_run go install ${GO_PACKAGES[@]+"${GO_PACKAGES[@]}"}; }
update_go_packages() { _lang_packages_run go update ${GO_PACKAGES[@]+"${GO_PACKAGES[@]}"}; }
install_cabal_packages() { _lang_packages_run cabal install ${CABAL_PACKAGES[@]+"${CABAL_PACKAGES[@]}"}; }
update_cabal_packages() { _lang_packages_run cabal update ${CABAL_PACKAGES[@]+"${CABAL_PACKAGES[@]}"}; }

install_lang_packages() {
    install_cargo_packages
    install_go_packages
    install_cabal_packages
}

update_lang_packages() {
    echo ""
    echo "=== Pakiety cargo / go / cabal (lista: packages/commons/lang_packages.sh) ==="
    update_cargo_packages
    update_go_packages
    update_cabal_packages
}
