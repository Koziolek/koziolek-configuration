#!/usr/bin/env bash
# Wspólna funkcja install_git_bug / update_git_bug dla initial_packages_{ubuntu,vanilla,redhat}.sh
# i update_packages_{ubuntu,vanilla,redhat}.sh (+ samodzielny packages/update_git_bug.sh pod cron).
# Sourcowane, nie wykonywane. Na macOS git-bug idzie przez brew (packages/brew_packages.sh).
#
# git-bug nie ma repozytorium apt/yum, więc bierzemy tarball z GitHub Releases. BEZ sudo:
# binarka ląduje w ${GIT_BUG_INSTALL_DIR:-$HOME/.local/bin} (to samo miejsce co claude/asdf),
# dzięki czemu aktualizacja działa z crona użytkownika.
#
# Wersja: przekierowanie https://github.com/git-bug/git-bug/releases/latest -> .../tag/vX.Y.Z
# (bez API, bez limitu zapytań, bez jq). Zainstalowana: drugie pole `git-bug version`.
# Równa najnowszej -> brak pobierania. Brak/starsza -> pobranie tarballa, weryfikacja sha256
# z checksums.txt tego samego wydania, instalacja. Jedna ścieżka dla instalacji i aktualizacji.
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

    if [ "$installed" = "$latest" ]; then
        echo "✓ git-bug aktualny: v$installed"
        return 0
    fi

    local archive="git-bug_${latest}_linux_${arch}.tar.gz"
    local base="$GIT_BUG_REPO_URL/releases/download/v${latest}"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    if [ -n "$installed" ]; then
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
    elif ! tar -xzf "$tmp_dir/$archive" -C "$tmp_dir" "git-bug_${latest}_linux_${arch}/git-bug"; then
        echo "⚠️  git-bug: nie udało się rozpakować $archive — pomijam"
    else
        mkdir -p "$install_dir"
        # `install` do pliku tymczasowego + mv: podmiana atomowa, działa też gdy stara binarka jest uruchomiona.
        install -m 755 "$tmp_dir/git-bug_${latest}_linux_${arch}/git-bug" "$install_dir/.git-bug.new" \
            && mv -f "$install_dir/.git-bug.new" "$install_dir/git-bug"
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
