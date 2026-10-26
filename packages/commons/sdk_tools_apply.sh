#!/usr/bin/env bash
# Instalacja i aktualizacja narzędzi z listy packages/commons/sdk_tools.sh.
# Sourcowane, nie wykonywane. Wspólne dla {ubuntu,vanilla,redhat,mac}/{install,update}.sh.
#
#   install_sdkman_tools   sdk install <kandydat> dla każdego z SDKMAN_TOOLS
#   update_sdkman_tools    sdk upgrade <kandydat>; brakujący kandydat jest instalowany
#   install_asdf_tools     plugin add → install → ustawienie wersji w ~/.tool-versions → reshim
#   update_asdf_tools      to samo + plugin update (wersja `latest` bierze nowe wydanie)
#
# Zawsze `return 0`: błąd jednego narzędzia to ostrzeżenie i podsumowanie na końcu, nie przerwanie
# reszty ani skryptu wołającego (`set -Eeuo pipefail`). Same instalatory SDKMAN-a i asdf nie
# należą do tego pliku — funkcje przy ich braku tylko ostrzegają.
#
# Zmienne (domyślnie jak w skryptach; nadpisywane w testach):
#   SDKMAN_DIR   katalog SDKMAN-a (domyślnie ~/.sdkman)
#   ASDF_BIN     binarka asdf (domyślnie ~/.local/bin/asdf)

_SDK_TOOLS_APPLY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packages/commons/sdk_tools.sh
source "$_SDK_TOOLS_APPLY_DIR/sdk_tools.sh"

_sdk_tools_summary() {
    local label="$1"
    shift
    if [ "$#" -gt 0 ]; then
        echo "⚠️  $label — nie udało się: $*"
    fi
}

# $1 = install|update. Podpowłoka, bo SDKMAN nie jest pisany pod `set -u` (jego wewnętrzne skrypty,
# np. sdkman-install.sh, sięgają po niepodane `$2` → "unbound variable" pod `set -Eeuo pipefail`),
# a `sdk selfupdate`/`sdk upgrade` potrafią wywołać `exit`. `trap - ERR`: odziedziczony trap
# wołającego nie może zabić pętli przy błędzie pojedynczego kandydata.
_sdkman_tools_run() {
    local mode="$1"
    local sdkman_dir="${SDKMAN_DIR:-$HOME/.sdkman}"
    local init="$sdkman_dir/bin/sdkman-init.sh"

    if [ ! -r "$init" ]; then
        echo "⚠️  SDKMAN nie zainstalowany — pomijam narzędzia sdkman"
        return 0
    fi

    (
        set +eu
        trap - ERR
        # zrzut listy przed source — sdkman-init.sh nadpisuje własne zmienne (SDKMAN_CANDIDATES itd.)
        tools=("${SDKMAN_TOOLS[@]}")
        export SDKMAN_DIR="$sdkman_dir"
        # shellcheck source=/dev/null
        source "$init"
        failed=()
        for candidate in "${tools[@]}"; do
            if [ "$mode" = update ] && [ -d "$sdkman_dir/candidates/$candidate" ]; then
                # `sdk upgrade` zwraca niezerowy kod także przy "nic do aktualizacji" — nie jest błędem
                sdk upgrade "$candidate" || true
            else
                sdk install "$candidate" || failed+=("$candidate")
            fi
        done
        _sdk_tools_summary "narzędzia sdkman" ${failed[@]+"${failed[@]}"}
    ) || true
    return 0
}

install_sdkman_tools() { _sdkman_tools_run install; }
update_sdkman_tools() { _sdkman_tools_run update; }

# asdf ≥ 0.16 (binarka w Go) nie ma `asdf global` — jest `asdf set -u`. Starsze mają tylko `global`.
_asdf_set_global() {
    local bin="$1" name="$2" version="$3"
    if "$bin" help 2>&1 | grep -q '^asdf set'; then
        "$bin" set -u "$name" "$version"
    else
        "$bin" global "$name" "$version"
    fi
}

# $1 = install|update, $2 = wpis `nazwa|url|wersja`
_asdf_tool_apply() {
    local mode="$1" entry="$2"
    local bin="${ASDF_BIN:-$HOME/.local/bin/asdf}"
    local name url version extra
    IFS='|' read -r name url version extra <<< "$entry"
    if [ -z "$name" ] || [ -z "$version" ] || [ -n "$extra" ]; then
        echo "⚠️  Niepoprawny wpis ASDF_TOOLS: '$entry' (oczekiwane nazwa|url|wersja)"
        return 1
    fi

    if "$bin" plugin list 2>/dev/null | grep -qx "$name"; then
        [ "$mode" = update ] && { "$bin" plugin update "$name" >/dev/null 2>&1 || true; }
    elif [ -n "$url" ]; then
        "$bin" plugin add "$name" "$url" || return 1
    else
        "$bin" plugin add "$name" || return 1
    fi
    "$bin" install "$name" "$version" || return 1
    _asdf_set_global "$bin" "$name" "$version" || return 1
}

_asdf_tools_run() {
    local mode="$1"
    local bin="${ASDF_BIN:-$HOME/.local/bin/asdf}"

    if [ ! -x "$bin" ]; then
        echo "⚠️  asdf nie zainstalowany — pomijam narzędzia asdf"
        return 0
    fi

    local failed=() entry
    for entry in "${ASDF_TOOLS[@]}"; do
        echo "asdf: ${entry%%|*}..."
        _asdf_tool_apply "$mode" "$entry" || failed+=("${entry%%|*}")
    done
    "$bin" reshim >/dev/null 2>&1 || true
    _sdk_tools_summary "narzędzia asdf" ${failed[@]+"${failed[@]}"}
    return 0
}

install_asdf_tools() { _asdf_tools_run install; }
update_asdf_tools() { _asdf_tools_run update; }
