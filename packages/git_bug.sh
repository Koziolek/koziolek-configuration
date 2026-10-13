#!/usr/bin/env bash
# Wspólna funkcja install_git_bug / update_git_bug dla initial_packages_{ubuntu,vanilla,redhat}.sh
# i update_packages_{ubuntu,vanilla,redhat}.sh.
# Sourcowane, nie wykonywane. Na macOS git-bug idzie przez brew (packages/brew_packages.sh).
#
# git-bug nie ma repozytorium apt/yum, więc bierzemy tarball z GitHub Releases. BEZ sudo:
# binarka ląduje w ${GIT_BUG_INSTALL_DIR:-$HOME/.local/bin} (to samo miejsce co claude/asdf),
# dzięki czemu aktualizacja działa z crona użytkownika.
#
# Wersja: przekierowanie https://github.com/git-bug/git-bug/releases/latest -> .../tag/vX.Y.Z
# (bez API, bez limitu zapytań, bez jq). Zainstalowana: drugie pole `git-bug version`.
# Równa najnowszej (i man + completion na miejscu) -> brak pobierania. Brak/starsza -> pobranie
# tarballa, weryfikacja sha256 z checksums.txt tego samego wydania, instalacja. Jedna ścieżka dla
# instalacji i aktualizacji.
#
# Poza binarką tarball niesie strony man (man/*.1) i completion (completion/bash/git-bug). Też BEZ
# sudo, w ${GIT_BUG_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}}:
#   man/man1/git-bug*.1                       (man znajduje je sam, gdy ~/.local/bin jest w PATH)
#   bash-completion/completions/git-bug       (ładowane leniwie przez pakiet bash-completion)
# Brak man/ lub completion w tarballu = ostrzeżenie, binarka i tak zostaje zainstalowana.
#
# Nieinteraktywne (bez read/TTY), zawsze `return 0` — błąd sieci/sumy to ostrzeżenie, nie awaria
# (nie przerywa `set -e` ani crona). Wynik na stdout.

GIT_BUG_REPO_URL="${GIT_BUG_REPO_URL:-https://github.com/git-bug/git-bug}"

# Najnowsza wersja stabilna (bez 'v'), np. 0.11.0. Pusty wynik = nie udało się ustalić.
git_bug_latest_version() {
    local url version
    url=$(curl -fsSL -o /dev/null -w '%{url_effective}' "$GIT_BUG_REPO_URL/releases/latest" 2>/dev/null) || return 1
    version="${url##*/tag/v}"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    echo "$version"
}

# Zainstalowana wersja (bez 'v'); pusty wynik = brak binarki.
git_bug_installed_version() {
    local bin="${1:-${GIT_BUG_INSTALL_DIR:-$HOME/.local/bin}/git-bug}" out
    [ -x "$bin" ] || { command -v git-bug >/dev/null 2>&1 && bin=$(command -v git-bug) || return 1; }
    out=$("$bin" version 2>/dev/null) || return 1
    out=$(echo "$out" | awk '{print $2}')
    echo "${out#v}"
}

# Architektura wydania: amd64 | arm64; inna = kod 1.
git_bug_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo amd64 ;;
        aarch64|arm64) echo arm64 ;;
        *) return 1 ;;
    esac
}

# Katalog danych użytkownika (man, completion).
git_bug_data_dir() {
    echo "${GIT_BUG_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}}"
}

# Kod 0, gdy strony man i completion są już zainstalowane (marker: główna strona + completion).
git_bug_docs_installed() {
    local data_dir
    data_dir=$(git_bug_data_dir)
    [ -f "$data_dir/man/man1/git-bug.1" ] && [ -f "$data_dir/bash-completion/completions/git-bug" ]
}

# Kopiuje man i completion z rozpakowanego wydania ($1) do katalogu danych. Brak źródeł = ostrzeżenie.
_git_bug_install_docs() {
    local src="$1" data_dir man_dir comp_dir f
    data_dir=$(git_bug_data_dir)
    man_dir="$data_dir/man/man1"
    comp_dir="$data_dir/bash-completion/completions"

    if compgen -G "$src/man/*.1" >/dev/null; then
        mkdir -p "$man_dir"
        for f in "$src"/man/*.1; do
            install -m 644 "$f" "$man_dir/.${f##*/}.new" && mv -f "$man_dir/.${f##*/}.new" "$man_dir/${f##*/}"
        done
    else
        echo "⚠️  git-bug: brak stron man w wydaniu — pomijam"
    fi

    if [ -f "$src/completion/bash/git-bug" ]; then
        mkdir -p "$comp_dir"
        install -m 644 "$src/completion/bash/git-bug" "$comp_dir/.git-bug.new" \
            && mv -f "$comp_dir/.git-bug.new" "$comp_dir/git-bug"
    else
        echo "⚠️  git-bug: brak bash completion w wydaniu — pomijam"
    fi
}

install_git_bug() {
    local install_dir="${GIT_BUG_INSTALL_DIR:-$HOME/.local/bin}"
    local latest installed arch

    arch=$(git_bug_arch) || {
        echo "⚠️  git-bug: nieobsługiwana architektura ($(uname -m)) — pomijam"
        return 0
    }
    latest=$(git_bug_latest_version) || {
        echo "⚠️  git-bug: nie udało się ustalić najnowszej wersji — pomijam"
        return 0
    }
    installed=$(git_bug_installed_version "$install_dir/git-bug") || installed=""

    if [ "$installed" = "$latest" ] && git_bug_docs_installed; then
        echo "✓ git-bug aktualny: v$installed"
        return 0
    fi

    local archive="git-bug_${latest}_linux_${arch}.tar.gz"
    local base="$GIT_BUG_REPO_URL/releases/download/v${latest}"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    if [ "$installed" = "$latest" ]; then
        echo "Uzupełnianie man i completion git-bug v$latest..."
    elif [ -n "$installed" ]; then
        echo "Aktualizacja git-bug: v$installed -> v$latest"
    else
        echo "Instalacja git-bug v$latest..."
    fi

    if ! curl -fsSL "$base/$archive" -o "$tmp_dir/$archive"; then
        echo "⚠️  git-bug: nie udało się pobrać $archive — pomijam"
    elif ! curl -fsSL "$base/checksums.txt" -o "$tmp_dir/checksums.txt"; then
        echo "⚠️  git-bug: nie udało się pobrać checksums.txt dla v$latest — pomijam"
    elif ! (cd "$tmp_dir" && grep " ${archive}\$" checksums.txt | sha256sum -c - --status); then
        echo "⚠️  git-bug: suma sha256 $archive nie zgadza się z wydaniem — pomijam"
    elif ! tar -xzf "$tmp_dir/$archive" -C "$tmp_dir"; then
        echo "⚠️  git-bug: nie udało się rozpakować $archive — pomijam"
    else
        local src="$tmp_dir/git-bug_${latest}_linux_${arch}"
        mkdir -p "$install_dir"
        # `install` do pliku tymczasowego + mv: podmiana atomowa, działa też gdy stara binarka jest uruchomiona.
        install -m 755 "$src/git-bug" "$install_dir/.git-bug.new" \
            && mv -f "$install_dir/.git-bug.new" "$install_dir/git-bug"
        _git_bug_install_docs "$src"
        echo "✓ git-bug v$latest zainstalowany w $install_dir (suma sha256 zweryfikowana)"
        case ":$PATH:" in
            *":$install_dir:"*) ;;
            *) echo "ℹ️  $install_dir nie jest w PATH — dodaj go, aby używać 'git bug'" ;;
        esac
    fi
    rm -rf "$tmp_dir"
    return 0
}

# Aktualizacja = ta sama ścieżka co instalacja (brak binarki -> instaluje, bez warunku wstępnego).
update_git_bug() {
    echo ""
    echo "=== git-bug ==="
    install_git_bug
}
