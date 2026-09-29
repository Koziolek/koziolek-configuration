#!/usr/bin/env bash
#
# Podpisywanie plików JAR kluczem sprzętowym przez PKCS11 (aplet PIV karty —
# YubiKey 5, Nitrokey 3, ...). Klucz prywatny nigdy nie opuszcza karty —
# `jarsigner`/OpenSC (`opensc-pkcs11.so`) tylko wołają operację podpisu.
#
# WAŻNE ograniczenie sprzętowe: wymaga apletu PIV (X.509 cert + klucz RSA/EC
# wygenerowany NA karcie). Klucze czysto FIDO2 bez PIV (Thetis BioFP+, Titan —
# te same, których dotyczy 156_function_ssh_sk_signing.sh) NIE obsłużą JAR
# signing — FIDO2 to challenge-response, nie generyczny RSA/EC sign oracle
# przez PKCS11. Provisioning karty (wygenerowanie certu na apletcie PIV,
# np. `ykman piv certificates generate`) jest poza scope tego repo.
#
# Dwa poziomy setupu:
#   1. jar_pkcs11_setup — na maszynie z podpiętą kartą: znajdź moduł OpenSC,
#      zweryfikuj że na karcie jest cert do podpisu, zapisz pkcs11.cfg.
#   2. jar_maven_setup  — wystaw jarsigner.* jako domyślnie aktywny profil
#      Mavena w ~/.m2/settings.xml, żeby `maven-jarsigner-plugin` w pom.xml
#      dowolnego projektu podpisywał JAR-y automatycznie przy
#      `mvn package`/`mvn verify`, bez zmian per-projekt.
#
# ~/.m2/settings.xml może już mieć realną konfigurację (mirrory/servery
# Nexusa) — nie parsujemy/przepisujemy całego pliku (np. ElementTree kasuje
# komentarze przy reserializacji). Zamiast tego: idempotentny insert
# oznaczonego bloku (<!-- jar-hw-signing:BEGIN/END -->) do <profiles>/
# <activeProfiles> (dopisywanych tylko jeśli ich jeszcze nie ma) — reszta
# pliku nietknięta. Ten sam styl co gpg_card_use_pcscd (idempotentny append
# do scdaemon.conf), tylko na blok XML zamiast pojedynczej linii.
#
# Zmienne (opcjonalne, np. w ~/.senv):
#   JAR_PKCS11_MODULE — override ścieżki do opensc-pkcs11.so
#   JAR_PKCS11_ALIAS  — override auto-detekcji aliasu certu na karcie
#   MAVEN_SETTINGS    — override ~/.m2/settings.xml (testy)

_jar_pkcs11_check_deps() {
    local missing=()
    command -v pkcs11-tool &>/dev/null || missing+=("pkcs11-tool (opensc)")
    command -v jarsigner   &>/dev/null || missing+=("jarsigner (JDK)")
    command -v keytool     &>/dev/null || missing+=("keytool (JDK)")
    if [ "${#missing[@]}" -gt 0 ]; then
        log_error "jar: brakujące zależności: ${missing[*]}"
        log_info  "jar: Linux: apt/yum install opensc; macOS: brew install opensc"
        return 1
    fi
    return 0
}

_jar_pkcs11_config_dir() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/git-configuration-signing"; }
_jar_pkcs11_cfg_path()   { echo "$(_jar_pkcs11_config_dir)/pkcs11.cfg"; }

# Szuka opensc-pkcs11.so po znanych ścieżkach. Override: $JAR_PKCS11_MODULE.
_jar_pkcs11_module_path() {
    if [ -n "${JAR_PKCS11_MODULE:-}" ]; then
        [ -f "$JAR_PKCS11_MODULE" ] && echo "$JAR_PKCS11_MODULE" && return 0
        log_error "jar: \$JAR_PKCS11_MODULE=$JAR_PKCS11_MODULE nie istnieje" >&2
        return 1
    fi
    local candidates=(
        /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so
        /usr/lib/aarch64-linux-gnu/opensc-pkcs11.so
        /usr/lib64/opensc-pkcs11.so
        /usr/lib/opensc-pkcs11.so
        /usr/local/lib/opensc-pkcs11.so
    )
    [ -n "${HOMEBREW_PREFIX:-}" ] && candidates+=("$HOMEBREW_PREFIX/lib/opensc-pkcs11.so")
    local c
    for c in "${candidates[@]}"; do
        [ -f "$c" ] && echo "$c" && return 0
    done
    {
        log_error "jar: nie znaleziono opensc-pkcs11.so w znanych lokalizacjach"
        log_info  "jar: zainstaluj pakiet opensc albo ustaw \$JAR_PKCS11_MODULE na pełną ścieżkę"
    } >&2
    return 1
}

# Alias jedynego certu na karcie (kolumna "label" z `pkcs11-tool -O --type cert`),
# albo błąd gdy zero/kilka certów — wtedy trzeba podać alias jawnie / JAR_PKCS11_ALIAS.
_jar_pkcs11_detect_alias() {
    local module="$1" out aliases
    out=$(pkcs11-tool --module "$module" -O --type cert 2>/dev/null) || return 1
    aliases=$(awk -F': *' '/^[[:space:]]*label:/ { print $2 }' <<<"$out")
    local count
    count=$(grep -c . <<<"$aliases")
    if [ "$count" -eq 0 ]; then
        log_error "jar: na karcie nie ma certyfikatu do podpisu (aplet PIV zaprowizjonowany?)" >&2
        return 1
    fi
    if [ "$count" -gt 1 ]; then
        log_error "jar: kilka certów na karcie — podaj alias jawnie albo ustaw \$JAR_PKCS11_ALIAS:" >&2
        printf '%s\n' "$aliases" >&2
        return 1
    fi
    printf '%s\n' "$aliases"
}

# Wszystkie aliasy (label) certów na karcie — do jar_sign -l / jar_verify -l.
# W przeciwieństwie do _jar_pkcs11_detect_alias nie błądzi przy >1 certów,
# tylko wylistowuje wszystkie.
_jar_pkcs11_list_aliases() {
    local module out aliases
    module=$(_jar_pkcs11_module_path) || return 1
    out=$(pkcs11-tool --module "$module" -O --type cert 2>/dev/null) || return 1
    aliases=$(awk -F': *' '/^[[:space:]]*label:/ { print $2 }' <<<"$out")
    if [ -z "$aliases" ]; then
        log_warn "jar: na karcie nie ma certyfikatu do podpisu"
        return 1
    fi
    printf '%s\n' "$aliases"
}

##
# Status karty PKCS11: sloty + obiekty (certy/klucze) — czytelny widok tego,
# co `jarsigner`/OpenSC faktycznie widzą.
##
function jar_pkcs11_status() {
    _jar_pkcs11_check_deps || return 1
    local module
    module=$(_jar_pkcs11_module_path) || return 1
    log_info "jar: moduł $module"
    pkcs11-tool --module "$module" -L
    pkcs11-tool --module "$module" -O
}

##
# Jednorazowo na maszynie z podpiętą kartą: znajdź moduł OpenSC, zweryfikuj że
# na karcie jest certyfikat do podpisu, zapisz pkcs11.cfg. Wypisuje wykryty
# alias (do ewentualnego JAR_PKCS11_ALIAS, jeśli certów jest więcej niż jeden).
##
function jar_pkcs11_setup() {
    _jar_pkcs11_check_deps || return 1
    local module alias cfg_dir cfg
    module=$(_jar_pkcs11_module_path) || return 1

    alias="${JAR_PKCS11_ALIAS:-}"
    if [ -z "$alias" ]; then
        alias=$(_jar_pkcs11_detect_alias "$module") || return 1
    fi

    cfg_dir=$(_jar_pkcs11_config_dir)
    cfg=$(_jar_pkcs11_cfg_path)
    mkdir -p "$cfg_dir"
    chmod 700 "$cfg_dir"
    printf 'name=OpenSC-PIV\nlibrary=%s\n' "$module" > "$cfg"
    chmod 600 "$cfg"

    log_info "jar: PKCS11 skonfigurowany → $cfg (moduł $module, alias $alias)"
    log_info "jar: sprawdź: jar_pkcs11_test; do Mavena: jar_maven_setup"
}

##
# Próbny podpis + weryfikacja na tymczasowym pliku — sprawdza cały łańcuch
# (karta, PIN, moduł PKCS11, jarsigner) bez dotykania prawdziwego JAR-a.
##
function jar_pkcs11_test() {
    _jar_pkcs11_check_deps || return 1
    local cfg alias tmp jar
    cfg=$(_jar_pkcs11_cfg_path)
    [ -f "$cfg" ] || { log_error "jar: brak $cfg — uruchom najpierw jar_pkcs11_setup"; return 1; }
    alias="${JAR_PKCS11_ALIAS:-}"
    if [ -z "$alias" ]; then
        alias=$(_jar_pkcs11_detect_alias "$(_jar_pkcs11_module_path)") || return 1
    fi

    tmp=$(mktemp -d) || return 1
    jar="$tmp/jar_pkcs11_test.jar"
    echo "jar_pkcs11_test $(date +%s)" > "$tmp/marker.txt"
    ( cd "$tmp" && jar cf "$(basename "$jar")" marker.txt ) || { rm -rf "$tmp"; log_error "jar: nie udało się zbudować testowego jara (jar cf)"; return 1; }

    log_info "jar: próbny podpis $jar aliasem $alias — podaj PIN/dotknij klucza gdy poprosi"
    local rc=0
    jarsigner -storetype PKCS11 -providerClass sun.security.pkcs11.SunPKCS11 \
        -providerArg "$cfg" -keystore NONE "$jar" "$alias" || rc=1

    if [ "$rc" -eq 0 ] && jarsigner -verify "$jar" >/dev/null 2>&1; then
        log_info "jar: podpis działa"
    else
        log_error "jar: podpis albo weryfikacja nie powiodła się"
        rc=1
    fi
    rm -rf "$tmp"
    return "$rc"
}

##
# Podpisuje wskazany plik JAR (ręcznie, poza Mavenem). Bez -storepass w argv —
# PIN wpisywany interaktywnie przez prompt providera (jak PIN FIDO2 — nie w
# historii powłoki). Alias: -k/--key → drugi argument pozycyjny (kompatybilność
# wsteczna) → JAR_PKCS11_ALIAS → auto-detekcja (tylko gdy na karcie jest
# dokładnie jeden cert).
# Usage: jar_sign [-l|--list] [-k|--key <alias>] <plik.jar> [alias]
#   -l, --list          wylistuj aliasy certów dostępnych na karcie i zakończ
#   -k, --key <alias>   alias certu do użycia
##
function jar_sign() {
    _jar_pkcs11_check_deps || return 1
    local list=0 alias="" jar="" cfg
    while [ $# -gt 0 ]; do
        case "$1" in
            -l|--list) list=1; shift ;;
            -k|--key)
                [ -n "${2:-}" ] || { log_error "jar_sign: $1 wymaga argumentu"; return 1; }
                alias="$2"; shift 2 ;;
            -h|--help)
                log_info "Usage: jar_sign [-l|--list] [-k|--key <alias>] <plik.jar> [alias]"
                return 0 ;;
            --) shift; break ;;
            -*)
                log_error "jar_sign: nieznana opcja $1"
                return 1 ;;
            *)
                if [ -z "$jar" ]; then jar="$1"; else [ -z "$alias" ] && alias="$1"; fi
                shift ;;
        esac
    done

    if [ "$list" -eq 1 ]; then
        _jar_pkcs11_list_aliases
        return $?
    fi

    [ -z "$alias" ] && alias="${JAR_PKCS11_ALIAS:-}"

    if [ -z "$jar" ]; then
        log_error "Usage: jar_sign [-l|--list] [-k|--key <alias>] <plik.jar> [alias]"
        return 1
    fi
    [ -f "$jar" ] || { log_error "jar: brak pliku $jar"; return 1; }
    cfg=$(_jar_pkcs11_cfg_path)
    [ -f "$cfg" ] || { log_error "jar: brak $cfg — uruchom najpierw jar_pkcs11_setup"; return 1; }
    if [ -z "$alias" ]; then
        alias=$(_jar_pkcs11_detect_alias "$(_jar_pkcs11_module_path)") || return 1
    fi

    log_info "jar: podpisuję $jar aliasem $alias — podaj PIN/dotknij klucza gdy poprosi"
    jarsigner -storetype PKCS11 -providerClass sun.security.pkcs11.SunPKCS11 \
        -providerArg "$cfg" -keystore NONE "$jar" "$alias"
}

##
# Weryfikuje podpis pliku JAR.
# Usage: jar_verify [-l|--list] <plik.jar>
#   -l, --list  wylistuj aliasy certów dostępnych na karcie i zakończ
##
function jar_verify() {
    local list=0 jar=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -l|--list) list=1; shift ;;
            -h|--help)
                log_info "Usage: jar_verify [-l|--list] <plik.jar>"
                return 0 ;;
            --) shift; break ;;
            -*)
                log_error "jar_verify: nieznana opcja $1"
                return 1 ;;
            *) jar="$1"; shift ;;
        esac
    done

    if [ "$list" -eq 1 ]; then
        _jar_pkcs11_check_deps || return 1
        _jar_pkcs11_list_aliases
        return $?
    fi

    if [ -z "$jar" ]; then
        log_error "Usage: jar_verify [-l|--list] <plik.jar>"
        return 1
    fi
    [ -f "$jar" ] || { log_error "jar: brak pliku $jar"; return 1; }
    jarsigner -verify -verbose -certs "$jar"
}

# --- ~/.m2/settings.xml: idempotentny insert oznaczonego bloku -------------
# Zasada: NIGDY nie parsujemy/przepisujemy całego pliku (ryzyko utraty
# komentarzy/formatowania cudzej konfiguracji, np. Nexusa) — tylko dopisujemy
# brakujące puste kontenery i wstawiamy/podmieniamy nasz oznaczony blok.

_jar_maven_settings_path() { echo "${MAVEN_SETTINGS:-$HOME/.m2/settings.xml}"; }

# Tworzy minimalny szkielet, jeśli plik nie istnieje / jest pusty.
_jar_ensure_settings_skeleton() {
    local file="$1"
    if [ -s "$file" ]; then
        return 0
    fi
    mkdir -p "$(dirname "$file")"
    printf '<settings>\n</settings>\n' > "$file"
}

# Dopisuje pusty kontener <tag></tag> przed </settings>, jeśli <tag> jeszcze
# nie istnieje w pliku. Idempotentne (grep sprawdza obecność przed wstawieniem).
_jar_ensure_container() {
    local file="$1" tag="$2"
    grep -qF "<$tag>" "$file" && return 0
    awk -v tag="$tag" '
        /<\/settings>/ && !done { print "  <" tag ">"; print "  </" tag ">"; done=1 }
        { print }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# Usuwa (jeśli jest) i wstawia od nowa oznaczony blok <!-- marker:BEGIN/END -->
# tuż przed pierwszym wystąpieniem </close_tag>. Idempotentne — powtórne
# wywołanie z tą samą treścią nadpisuje poprzedni blok, nie duplikuje go.
_jar_upsert_marked_block() {
    local file="$1" marker="$2" close_tag="$3" content="$4"
    local begin="<!-- ${marker}:BEGIN -->" end="<!-- ${marker}:END -->"

    awk -v b="$begin" -v e="$end" '
        $0 == b { skip=1 }
        !skip { print }
        $0 == e { skip=0 }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"

    awk -v closetag="</$close_tag>" -v b="$begin" -v e="$end" -v content="$content" '
        index($0, closetag) && !done {
            print b
            print content
            print e
            done=1
        }
        { print }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# Usuwa oznaczony blok bez wstawiania nowego (kontenery zostają, nawet puste).
_jar_remove_marked_block() {
    local file="$1" marker="$2"
    local begin="<!-- ${marker}:BEGIN -->" end="<!-- ${marker}:END -->"
    awk -v b="$begin" -v e="$end" '
        $0 == b { skip=1 }
        !skip { print }
        $0 == e { skip=0 }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

##
# Wystawia jarsigner.* (z jar_pkcs11_setup) jako domyślnie aktywny profil
# Mavena "jar-hw-signing" w ~/.m2/settings.xml — dowolny projekt z
# maven-jarsigner-plugin w pom.xml podpisze JAR-y automatycznie przy
# `mvn package`/`mvn verify`, bez zmian per-projekt. Idempotentne.
##
function jar_maven_setup() {
    _jar_pkcs11_check_deps || return 1
    local cfg alias settings
    cfg=$(_jar_pkcs11_cfg_path)
    [ -f "$cfg" ] || { log_error "jar: brak $cfg — uruchom najpierw jar_pkcs11_setup"; return 1; }
    alias="${JAR_PKCS11_ALIAS:-}"
    if [ -z "$alias" ]; then
        alias=$(_jar_pkcs11_detect_alias "$(_jar_pkcs11_module_path)") || return 1
    fi
    settings=$(_jar_maven_settings_path)

    _jar_ensure_settings_skeleton "$settings"
    _jar_ensure_container "$settings" profiles
    _jar_ensure_container "$settings" activeProfiles

    local profile_block active_block
    profile_block=$(cat <<XML
  <profile>
    <id>jar-hw-signing</id>
    <properties>
      <jarsigner.keystore>NONE</jarsigner.keystore>
      <jarsigner.storetype>PKCS11</jarsigner.storetype>
      <jarsigner.providerClass>sun.security.pkcs11.SunPKCS11</jarsigner.providerClass>
      <jarsigner.providerArg>${cfg}</jarsigner.providerArg>
      <jarsigner.alias>${alias}</jarsigner.alias>
    </properties>
  </profile>
XML
)
    active_block="  <activeProfile>jar-hw-signing</activeProfile>"

    _jar_upsert_marked_block "$settings" jar-hw-signing-profile profiles "$profile_block"
    _jar_upsert_marked_block "$settings" jar-hw-signing-active activeProfiles "$active_block"

    log_info "jar: $settings skonfigurowany — profil jar-hw-signing (alias $alias) aktywny domyślnie"
    log_info "jar: projekty z maven-jarsigner-plugin w pom.xml podpiszą JAR-y automatycznie przy 'mvn package'/'mvn verify'"
}

##
# Usuwa profil jar-hw-signing z ~/.m2/settings.xml (kontenery <profiles>/
# <activeProfiles> zostają, nawet puste — reszta pliku nietknięta).
##
function jar_maven_disable() {
    local settings
    settings=$(_jar_maven_settings_path)
    [ -f "$settings" ] || { log_warn "jar: $settings nie istnieje — nic do wyłączenia"; return 0; }
    _jar_remove_marked_block "$settings" jar-hw-signing-profile
    _jar_remove_marked_block "$settings" jar-hw-signing-active
    log_info "jar: profil jar-hw-signing usunięty z $settings"
}

export -f jar_pkcs11_status
export -f jar_pkcs11_setup
export -f jar_pkcs11_test
export -f jar_sign
export -f jar_verify
export -f jar_maven_setup
export -f jar_maven_disable
