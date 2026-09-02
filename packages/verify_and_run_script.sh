#!/usr/bin/env bash
# Wspólna funkcja verify_and_run_script dla initial_packages.sh, initial_packages_mac.sh
# i initial_packages_vanilla.sh. Sourcowane, nie wykonywane.
#
# Pobiera zdalny skrypt instalacyjny do pliku tymczasowego i próbuje zweryfikować
# go przez sumę kontrolną (git blob sha1 zgodny z tym, co zgłasza GitHub API dla
# danego pliku/repo/ref — działa tylko gdy skrypt jest hostowany na GitHubie).
# Jeśli suma jest niedostępna (brak parametrów gh_* albo API nie odpowiada) ALBO
# się nie zgadza — wypisuje ostrzeżenie i PYTA użytkownika o zgodę na kontynuację.
# Bez zgody funkcja zwraca 1 i nic nie uruchamia.
# Usage: verify_and_run_script "<opis>" "<url>" ["<gh_owner/repo>" "<sciezka>" "<ref>"]
verify_and_run_script() {
    local desc="$1" url="$2" gh_repo="${3:-}" gh_path="${4:-}" gh_ref="${5:-HEAD}"

    local tmp_script
    tmp_script=$(mktemp)
    if ! curl -fsSL "$url" -o "$tmp_script"; then
        echo "❌ Nie udało się pobrać: $desc ($url)"
        rm -f "$tmp_script"
        return 1
    fi

    local checksum_ok=false
    local reason=""

    if [ -n "$gh_repo" ]; then
        local expected_sha actual_sha size
        expected_sha=$(curl -sf "https://api.github.com/repos/${gh_repo}/contents/${gh_path}?ref=${gh_ref}" \
            | grep -o '"sha": *"[0-9a-f]\{40\}"' | head -1 | grep -o '[0-9a-f]\{40\}')
        if [ -z "$expected_sha" ]; then
            reason="Nie udało się pobrać oficjalnej sumy kontrolnej z GitHub API dla: $desc"
        else
            size=$(wc -c < "$tmp_script")
            actual_sha=$( { printf 'blob %d\0' "$size"; cat "$tmp_script"; } | sha1sum | awk '{print $1}')
            if [ "$actual_sha" = "$expected_sha" ]; then
                checksum_ok=true
            else
                reason="Suma kontrolna NIE ZGADZA SIĘ dla: $desc (oczekiwano ${expected_sha}, jest ${actual_sha})"
            fi
        fi
    else
        reason="Brak dostępnej oficjalnej sumy kontrolnej dla: $desc"
    fi

    if ! $checksum_ok; then
        echo "⚠️  $reason"
        echo "⚠️  Uruchomienie niezweryfikowanego skryptu z sieci: $url"
        local reply
        read -r -p "Kontynuować mimo to? [y/N]: " -n 1 -r reply </dev/tty || reply=n
        echo
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            echo "❌ Przerwano na życzenie użytkownika: $desc"
            rm -f "$tmp_script"
            return 1
        fi
    else
        echo "✓ Suma kontrolna zweryfikowana (git blob sha1 zgodny z GitHub API): $desc"
    fi

    bash "$tmp_script"
    local rc=$?
    rm -f "$tmp_script"
    return $rc
}
