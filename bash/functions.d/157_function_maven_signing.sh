#!/usr/bin/env bash
#
# Podpisywanie artefaktów Mavena — dwa niezależne backendy w jednym pliku,
# bo oba w końcu piszą do tego samego ~/.m2/settings.xml przez te same
# helpery manipulacji XML-em (sekcja "~/.m2/settings.xml" niżej):
#
#   1. JAR przez PKCS11 (jar_*)      — `jarsigner -storetype PKCS11`, aplet
#      PIV karty (X.509 cert + klucz RSA/EC wygenerowany NA karcie — YubiKey 5,
#      Nitrokey 3). Klucz prywatny nigdy nie opuszcza karty.
#   2. Artefakty Mavena przez GPG software (gpg_sw_*/gpg_maven_*) — podpis
#      PGP (`maven-gpg-plugin`, publikacja na Maven Central), dla maszyn/kluczy
#      bez apletu PIV/OpenPGP. Klucz prywatny leży w zwykłym keyringu gpg
#      (~/.gnupg), chroniony tylko passphrase.
#
# WAŻNE ograniczenie sprzętowe (dotyczy OBU): klucze czysto FIDO2 bez apletu
# PIV/OpenPGP (Thetis BioFP+, Titan — te same, których dotyczy
# 155_function_git_signing.sh#ssh_sk_*) NIE obsłużą żadnego z powyższych —
# FIDO2 to challenge-response, nie generyczny RSA/EC/EdDSA sign oracle. Jeśli
# karta MA aplet OpenPGP, do artefaktów Mavena lepszy jest
# 155_function_git_signing.sh#gpg_git_setup (sprzętowy) niż gpg_sw_* tutaj
# (softwarowy) — klucz wtedy nigdy nie opuszcza karty.
#
# --- JAR / PKCS11 -----------------------------------------------------------
#
# Dwa poziomy setupu:
#   1. jar_pkcs11_setup — na maszynie z podpiętą kartą: znajdź moduł OpenSC,
#      zweryfikuj że na karcie jest cert do podpisu, zapisz pkcs11.cfg.
#   2. jar_maven_setup  — wystaw jarsigner.* jako domyślnie aktywny profil
#      Mavena w ~/.m2/settings.xml, żeby `maven-jarsigner-plugin` w pom.xml
#      dowolnego projektu podpisywał JAR-y automatycznie przy
#      `mvn package`/`mvn verify`, bez zmian per-projekt.
#
# Zmienne (opcjonalne, np. w ~/.senv):
#   JAR_PKCS11_MODULE — override ścieżki do opensc-pkcs11.so
#   JAR_PKCS11_ALIAS  — override auto-detekcji aliasu certu na karcie
#   MAVEN_SETTINGS    — override ~/.m2/settings.xml (testy, wspólne dla obu backendów)

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
    settings=$(_maven_settings_path)

    _maven_settings_ensure_skeleton "$settings"
    _maven_settings_ensure_container "$settings" profiles
    _maven_settings_ensure_container "$settings" activeProfiles

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

    _maven_settings_upsert_marked_block "$settings" jar-hw-signing-profile profiles "$profile_block"
    _maven_settings_upsert_marked_block "$settings" jar-hw-signing-active activeProfiles "$active_block"

    log_info "jar: $settings skonfigurowany — profil jar-hw-signing (alias $alias) aktywny domyślnie"
    log_info "jar: projekty z maven-jarsigner-plugin w pom.xml podpiszą JAR-y automatycznie przy 'mvn package'/'mvn verify'"
}

##
# Usuwa profil jar-hw-signing z ~/.m2/settings.xml (kontenery <profiles>/
# <activeProfiles> zostają, nawet puste — reszta pliku nietknięta).
##
function jar_maven_disable() {
    local settings
    settings=$(_maven_settings_path)
    [ -f "$settings" ] || { log_warn "jar: $settings nie istnieje — nic do wyłączenia"; return 0; }
    _maven_settings_remove_marked_block "$settings" jar-hw-signing-profile
    _maven_settings_remove_marked_block "$settings" jar-hw-signing-active
    log_info "jar: profil jar-hw-signing usunięty z $settings"
}

export -f jar_pkcs11_status
export -f jar_pkcs11_setup
export -f jar_pkcs11_test
export -f jar_sign
export -f jar_verify
export -f jar_maven_setup
export -f jar_maven_disable

# --- JAR software (bez karty/PKCS11) ----------------------------------------
#
# Podpisywanie JAR-ów kluczem w zwykłym keystore JKS — dla maszyn bez apletu
# PIV. Klucz prywatny leży w pliku JKS na dysku, chroniony hasłem
# keystore/klucza — nigdy w argv, jak przy PKCS11 wyżej: `keytool`/
# `jarsigner` wywołane bez `-storepass`/`-keypass` pytają o hasło
# interaktywnie. `jar_verify` (wyżej) weryfikuje podpis niezależnie od
# backendu — `jarsigner -verify` nie musi wiedzieć, jak podpis powstał.
#
# Zmienne: JAR_SW_KEYSTORE (override ścieżki JKS)

_jar_sw_config_dir()    { echo "${XDG_CONFIG_HOME:-$HOME/.config}/git-configuration-signing"; }
_jar_sw_cfg_path()      { echo "$(_jar_sw_config_dir)/jar-sw.cfg"; }
_jar_sw_keystore_path() { echo "${JAR_SW_KEYSTORE:-$(_jar_sw_config_dir)/jar-sw-keystore.jks}"; }

##
# Generuje self-signed parę kluczy RSA w lokalnym keystore JKS. Hasło
# keystore/klucza pytane interaktywnie (bez -storepass/-keypass w argv).
# Usage: jar_sw_generate <alias> <CN/imię i nazwisko> [dni_ważności]
##
function jar_sw_generate() {
    command -v keytool &>/dev/null || { log_error "jar_sw: brak keytool (JDK)"; return 1; }
    local alias="${1:-}" cn="${2:-}" days="${3:-1095}" ks

    if [ -z "$alias" ] || [ -z "$cn" ]; then
        log_error "Usage: jar_sw_generate <alias> <CN/imię i nazwisko> [dni_ważności]"
        return 1
    fi

    ks=$(_jar_sw_keystore_path)
    mkdir -p "$(dirname "$ks")"
    chmod 700 "$(dirname "$ks")"

    log_info "jar_sw: generuję klucz (alias $alias, RSA 3072, $days dni) w $ks — podaj hasło keystore/klucza gdy poprosi"
    keytool -genkeypair -alias "$alias" -keyalg RSA -keysize 3072 \
        -dname "CN=${cn}" -validity "$days" -keystore "$ks" || {
        log_error "jar_sw: generowanie klucza nie powiodło się"
        return 1
    }
    chmod 600 "$ks"

    printf 'ALIAS=%s\nKEYSTORE=%s\n' "$alias" "$ks" > "$(_jar_sw_cfg_path)"
    chmod 600 "$(_jar_sw_cfg_path)"

    log_info "jar_sw: klucz gotowy — alias $alias, keystore $ks"
    log_info "jar_sw: sprawdź: jar_sw_sign <plik.jar>; do Mavena: jar_sw_maven_setup"
}

##
# Podpisuje wskazany plik JAR kluczem z lokalnego keystore JKS. Bez
# -storepass/-keypass w argv — jarsigner pyta o hasło interaktywnie.
# Usage: jar_sw_sign <plik.jar> [alias]
##
function jar_sw_sign() {
    command -v jarsigner &>/dev/null || { log_error "jar_sw: brak jarsigner (JDK)"; return 1; }
    local jar="${1:-}" alias="${2:-}" ks cfg

    if [ -z "$jar" ]; then
        log_error "Usage: jar_sw_sign <plik.jar> [alias]"
        return 1
    fi
    [ -f "$jar" ] || { log_error "jar_sw: brak pliku $jar"; return 1; }

    cfg=$(_jar_sw_cfg_path)
    ks=$(_jar_sw_keystore_path)
    [ -f "$ks" ] || { log_error "jar_sw: brak $ks — uruchom najpierw jar_sw_generate"; return 1; }
    if [ -z "$alias" ] && [ -f "$cfg" ]; then
        alias=$(awk -F= '/^ALIAS=/ { print $2 }' "$cfg")
    fi
    if [ -z "$alias" ]; then
        log_error "jar_sw: brak aliasu — podaj jawnie albo uruchom jar_sw_generate"
        return 1
    fi

    log_info "jar_sw: podpisuję $jar aliasem $alias — podaj hasło keystore/klucza gdy poprosi"
    jarsigner -keystore "$ks" "$jar" "$alias"
}

##
# Wystawia jarsigner.* jako domyślnie aktywny profil Mavena "jar-sw-signing"
# w ~/.m2/settings.xml — analogicznie do jar_maven_setup, ale storetype JKS
# zamiast PKCS11. Współistnieje z jar-hw-signing/gpg-sw-signing (inny profil).
# Usage: jar_sw_maven_setup [alias] [keystore]
##
function jar_sw_maven_setup() {
    local alias="${1:-}" ks="${2:-}" cfg settings

    cfg=$(_jar_sw_cfg_path)
    if [ -z "$alias" ] && [ -f "$cfg" ]; then
        alias=$(awk -F= '/^ALIAS=/ { print $2 }' "$cfg")
    fi
    [ -z "$ks" ] && ks=$(_jar_sw_keystore_path)
    if [ -z "$alias" ] || [ ! -f "$ks" ]; then
        log_error "Usage: jar_sw_maven_setup <alias> <keystore> (albo uruchom najpierw jar_sw_generate)"
        return 1
    fi

    settings=$(_maven_settings_path)
    _maven_settings_ensure_skeleton "$settings"
    _maven_settings_ensure_container "$settings" profiles
    _maven_settings_ensure_container "$settings" activeProfiles

    local profile_block active_block
    profile_block=$(cat <<XML
  <profile>
    <id>jar-sw-signing</id>
    <properties>
      <jarsigner.keystore>${ks}</jarsigner.keystore>
      <jarsigner.storetype>JKS</jarsigner.storetype>
      <jarsigner.alias>${alias}</jarsigner.alias>
    </properties>
  </profile>
XML
)
    active_block="  <activeProfile>jar-sw-signing</activeProfile>"

    _maven_settings_upsert_marked_block "$settings" jar-sw-signing-profile profiles "$profile_block"
    _maven_settings_upsert_marked_block "$settings" jar-sw-signing-active activeProfiles "$active_block"

    log_info "jar_sw: $settings skonfigurowany — profil jar-sw-signing (alias $alias) aktywny domyślnie"
}

##
# Usuwa profil jar-sw-signing z ~/.m2/settings.xml.
##
function jar_sw_maven_disable() {
    local settings
    settings=$(_maven_settings_path)
    [ -f "$settings" ] || { log_warn "jar_sw: $settings nie istnieje — nic do wyłączenia"; return 0; }
    _maven_settings_remove_marked_block "$settings" jar-sw-signing-profile
    _maven_settings_remove_marked_block "$settings" jar-sw-signing-active
    log_info "jar_sw: profil jar-sw-signing usunięty z $settings"
}

export -f jar_sw_generate
export -f jar_sw_sign
export -f jar_sw_maven_setup
export -f jar_sw_maven_disable

# --- ~/.m2/settings.xml: idempotentny insert oznaczonego bloku -------------
# Zasada: NIGDY nie parsujemy/przepisujemy całego pliku (ryzyko utraty
# komentarzy/formatowania cudzej konfiguracji, np. Nexusa) — tylko dopisujemy
# brakujące puste kontenery i wstawiamy/podmieniamy nasz oznaczony blok.
# Wspólne dla OBU backendów tego pliku — jar_maven_setup (profil
# jar-hw-signing) i gpg_maven_setup (profil gpg-sw-signing) — stąd nazwa
# _maven_settings_* zamiast _jar_*: oba profile mogą współistnieć w jednym
# ~/.m2/settings.xml, każdy w swoim oznaczonym bloku.

_maven_settings_path() { echo "${MAVEN_SETTINGS:-$HOME/.m2/settings.xml}"; }

# Tworzy minimalny szkielet, jeśli plik nie istnieje / jest pusty.
_maven_settings_ensure_skeleton() {
    local file="$1"
    if [ -s "$file" ]; then
        return 0
    fi
    mkdir -p "$(dirname "$file")"
    printf '<settings>\n</settings>\n' > "$file"
}

# Dopisuje pusty kontener <tag></tag> przed </settings>, jeśli <tag> jeszcze
# nie istnieje w pliku. Idempotentne (grep sprawdza obecność przed wstawieniem).
_maven_settings_ensure_container() {
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
_maven_settings_upsert_marked_block() {
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
_maven_settings_remove_marked_block() {
    local file="$1" marker="$2"
    local begin="<!-- ${marker}:BEGIN -->" end="<!-- ${marker}:END -->"
    awk -v b="$begin" -v e="$end" '
        $0 == b { skip=1 }
        !skip { print }
        $0 == e { skip=0 }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# --- GPG software (Maven artifact signing / Maven Central) ------------------
#
# Softwarowe podpisywanie artefaktów Mavena kluczem PGP (maven-gpg-plugin,
# publikacja na Maven Central przez Sonatype Central) — dla maszyn/kluczy bez
# apletu OpenPGP/PIV na karcie. Klucz prywatny leży w zwykłym keyringu gpg
# (~/.gnupg), chroniony tylko passphrase — jeśli karta z apletem OpenPGP jest
# dostępna, użyj zamiast tego 155_function_git_signing.sh#gpg_git_setup
# (klucz nigdy nie opuszcza karty).
#
# Jedno polecenie na cały proces: gpg_sw_setup
#   1. generuje klucz (gpg_sw_generate — pyta o imię/nazwisko + email,
#      passphrase przez zwykły pinentry gpg-agent, ten sam hook co w 155)
#   2. klucz ląduje w lokalnym keyringu gpg (~/.gnupg) — jedyne miejsce,
#      w którym GPG w ogóle przechowuje klucze prywatne
#   3. eksport na keyserver (gpg_sw_export — ubuntu/openpgp/both)
#   4. pyta, czy dopiąć klucz do Mavena (gpg_maven_setup)
#
# Zmienne (opcjonalne — pozwalają odpalić gpg_sw_setup nieinteraktywnie,
# np. w testach, analogicznie do GIT_ASSUME_YES w git/git_functions.sh):
#   GPG_SW_NAME, GPG_SW_EMAIL       — pomijają pytania o dane klucza
#   GPG_SW_KEY_ALGO   (default: ed25519)
#   GPG_SW_KEY_USAGE  (default: sign)   — tylko podpis, bez szyfrowania
#   GPG_SW_KEY_EXPIRE (default: 2y)
#   GPG_SW_EXPORT_TARGET (ubuntu|openpgp|both|none) — pomija pytanie o eksport
#   GPG_SW_MAVEN_CONFIRM (T/n)          — pomija pytanie o konfigurację Mavena

_gpg_sw_check_deps() {
    command -v gpg &>/dev/null || { log_error "gpg_sw: brak gpg — apt/yum install gnupg2; brew install gnupg"; return 1; }
    return 0
}

_gpg_sw_config_dir() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/git-configuration-signing"; }
_gpg_sw_cfg_path()   { echo "$(_gpg_sw_config_dir)/gpg-sw.cfg"; }

##
# Listuje klucze prywatne dostępne w lokalnym keyringu (do wyboru $keyid dla
# gpg_sw_export / gpg_maven_setup / maven-gpg-plugin).
##
function gpg_sw_list_keys() {
    _gpg_sw_check_deps || return 1
    gpg --list-secret-keys --keyid-format=long
}

##
# Generuje nowy klucz PGP (tylko do podpisu — bez subklucza szyfrującego) i
# zapisuje jego fingerprint w configu (do domyślnego użycia przez
# gpg_maven_setup). Wypisuje fingerprint na stdout — logi (log_info/log_error)
# przekierowane na stderr, żeby nie mieszały się ze zwracaną wartością.
# Usage: gpg_sw_generate [imię i nazwisko] [email]
##
function gpg_sw_generate() {
    _gpg_sw_check_deps || return 1
    local name="${1:-${GPG_SW_NAME:-}}" email="${2:-${GPG_SW_EMAIL:-}}"
    local algo="${GPG_SW_KEY_ALGO:-ed25519}" usage="${GPG_SW_KEY_USAGE:-sign}" expire="${GPG_SW_KEY_EXPIRE:-2y}"

    if [ -z "$name" ] || [ -z "$email" ]; then
        log_error "Usage: gpg_sw_generate <imię i nazwisko> <email>"
        return 1
    fi

    local uid="$name <$email>"
    log_info "gpg_sw: generuję klucz ($algo/$usage, wygasa $expire) dla \"$uid\" — podaj passphrase gdy poprosi" >&2
    # stdout gpg → stderr: gpg wypisuje na nim blok "pub ..." i zaśmiecił by
    # fingerprint zwracany przez $(gpg_sw_generate)
    gpg --quick-generate-key "$uid" "$algo" "$usage" "$expire" >&2 || {
        log_error "gpg_sw: generowanie klucza nie powiodło się" >&2
        return 1
    }

    local fpr
    fpr=$(gpg --list-secret-keys --with-colons --fingerprint "$uid" 2>/dev/null | awk -F: '/^fpr:/ { print $10; exit }')
    if [ -z "$fpr" ]; then
        log_error "gpg_sw: klucz wygenerowany, ale nie udało się odczytać jego fingerprintu" >&2
        return 1
    fi

    mkdir -p "$(_gpg_sw_config_dir)"
    chmod 700 "$(_gpg_sw_config_dir)"
    printf 'KEYID=%s\n' "$fpr" > "$(_gpg_sw_cfg_path)"
    chmod 600 "$(_gpg_sw_cfg_path)"

    echo "$fpr"
}

##
# Upload na keys.openpgp.org przez VKS API: POST /vks/v1/upload z JSON-em
# {"keytext": "<armored>"} (surowy PUT binarium → 404). Odpowiedź niesie
# token; z nim POST /vks/v1/request-verify każe serwerowi wysłać mail
# weryfikacyjny na adres z UID-a (bez tego UID-y są niewidoczne w wyszukiwaniu).
##
_gpg_sw_export_openpgp() {
    local keyid="$1" noverify="${2:-}" base="https://keys.openpgp.org/vks/v1"
    command -v curl &>/dev/null || { log_error "gpg_sw: curl wymagany do eksportu na keys.openpgp.org"; return 1; }
    log_info "gpg_sw: eksport $keyid → keys.openpgp.org (VKS API)"

    local json resp
    json=$(gpg --export --armor "$keyid" | awk 'BEGIN { printf "{\"keytext\":\"" }
        { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); printf "%s\\n", $0 }
        END { printf "\"}" }')
    resp=$(printf '%s' "$json" | curl -sS -X POST -H 'Content-Type: application/json' --data-binary @- "$base/upload") || {
        log_error "gpg_sw: upload na keys.openpgp.org nie powiódł się"
        return 1
    }
    case "$resp" in
        *'"token"'*|*'"key_fpr"'*) : ;;
        *) log_error "gpg_sw: keys.openpgp.org odrzucił klucz: $resp"; return 1 ;;
    esac
    log_info "gpg_sw: klucz wgrany na keys.openpgp.org"
    [ "$noverify" = noverify ] && return 0

    local token email
    token=$(printf '%s' "$resp" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    email=$(gpg --list-keys --with-colons "$keyid" 2>/dev/null | awk -F: '/^uid:/ { print $10; exit }' | sed -n 's/.*<\([^>]*\)>.*/\1/p')
    if [ -z "$token" ] || [ -z "$email" ]; then
        log_warn "gpg_sw: brak tokenu/adresu — zweryfikuj UID ręcznie: https://keys.openpgp.org/upload"
        return 0
    fi

    resp=$(curl -sS -X POST -H 'Content-Type: application/json' \
        -d "{\"token\":\"$token\",\"addresses\":[\"$email\"]}" "$base/request-verify") || {
        log_warn "gpg_sw: nie udało się zlecić maila weryfikacyjnego — zrób to na https://keys.openpgp.org/upload"
        return 0
    }
    log_info "gpg_sw: mail weryfikacyjny zlecony dla $email — kliknij link, żeby UID był publiczny ($resp)"
    return 0
}

##
# Eksportuje klucz publiczny na keyserver.
# Usage: gpg_sw_export <keyid> [ubuntu|openpgp|both]
#   ubuntu  — keyserver.ubuntu.com (SKS-owy, publikuje UID-y od razu)
#   openpgp — keys.openpgp.org (VKS API); UID-y zostają niezweryfikowane
#             (niewidoczne w wyszukiwaniu po adresie e-mail), dopóki nie
#             potwierdzisz linku z maila, który stamtąd przyjdzie
##
function gpg_sw_export() {
    _gpg_sw_check_deps || return 1
    local keyid="${1:-}" target="${2:-both}" noverify="${3:-}" rc=0

    if [ -z "$keyid" ]; then
        log_error "Usage: gpg_sw_export <keyid> [ubuntu|openpgp|both]"
        return 1
    fi
    case "$target" in
        ubuntu|openpgp|both) : ;;
        *) log_error "gpg_sw: nieznany cel eksportu '$target' (ubuntu|openpgp|both)"; return 1 ;;
    esac
    # keyid to hex (8-40 znaków, opcjonalnie 0x) — odrzuca np. wielolinijkowy
    # wynik --list-keys wklejony zamiast fingerprintu
    if ! [[ "$keyid" =~ ^(0x)?[0-9A-Fa-f]{8,40}$ ]]; then
        log_error "gpg_sw: '$keyid' nie wygląda na keyid/fingerprint (hex, 8-40 znaków)"
        return 1
    fi

    if [ "$target" = ubuntu ] || [ "$target" = both ]; then
        log_info "gpg_sw: eksport $keyid → keyserver.ubuntu.com"
        gpg --keyserver hkps://keyserver.ubuntu.com --send-keys "$keyid" || rc=1
    fi

    if [ "$target" = openpgp ] || [ "$target" = both ]; then
        _gpg_sw_export_openpgp "$keyid" "$noverify" || rc=1
    fi

    return "$rc"
}

##
# Wystawia gpg.keyname jako domyślnie aktywny profil Mavena "gpg-sw-signing"
# w ~/.m2/settings.xml — maven-gpg-plugin (goal `sign`, patrz devtools-maven-
# extension/pom.xml) podpisze artefakty automatycznie przy `mvn verify`/
# `deploy`, bez zmian per-projekt. Ten sam, oznaczony-blokowy mechanizm co
# jar_maven_setup wyżej (idempotentny insert, reszta pliku nietknięta) —
# inny profil (gpg-sw-signing zamiast jar-hw-signing), więc oba mogą
# współistnieć w jednym settings.xml.
# Usage: gpg_maven_setup [keyid]   (bez argumentu: keyid z gpg_sw_generate)
##
function gpg_maven_setup() {
    local keyid="${1:-}" settings

    if [ -z "$keyid" ] && [ -f "$(_gpg_sw_cfg_path)" ]; then
        keyid=$(awk -F= '/^KEYID=/ { print $2 }' "$(_gpg_sw_cfg_path)")
    fi
    if [ -z "$keyid" ]; then
        log_error "Usage: gpg_maven_setup <keyid> (albo uruchom najpierw gpg_sw_generate)"
        return 1
    fi

    settings=$(_maven_settings_path)
    _maven_settings_ensure_skeleton "$settings"
    _maven_settings_ensure_container "$settings" profiles
    _maven_settings_ensure_container "$settings" activeProfiles

    local profile_block active_block
    profile_block=$(cat <<XML
  <profile>
    <id>gpg-sw-signing</id>
    <properties>
      <gpg.keyname>${keyid}</gpg.keyname>
    </properties>
  </profile>
XML
)
    active_block="  <activeProfile>gpg-sw-signing</activeProfile>"

    _maven_settings_upsert_marked_block "$settings" gpg-sw-signing-profile profiles "$profile_block"
    _maven_settings_upsert_marked_block "$settings" gpg-sw-signing-active activeProfiles "$active_block"

    log_info "gpg_sw: $settings skonfigurowany — profil gpg-sw-signing (klucz $keyid) aktywny domyślnie"
}

##
# Usuwa profil gpg-sw-signing z ~/.m2/settings.xml (kontenery <profiles>/
# <activeProfiles> zostają, nawet puste — reszta pliku nietknięta).
##
function gpg_maven_disable() {
    local settings
    settings=$(_maven_settings_path)
    [ -f "$settings" ] || { log_warn "gpg_sw: $settings nie istnieje — nic do wyłączenia"; return 0; }
    _maven_settings_remove_marked_block "$settings" gpg-sw-signing-profile
    _maven_settings_remove_marked_block "$settings" gpg-sw-signing-active
    log_info "gpg_sw: profil gpg-sw-signing usunięty z $settings"
}

##
# Odwołuje (revoke) klucz i publikuje odwołanie na keyserverach. Keyserverów
# nie da się „wyczyścić” — SKS (keyserver.ubuntu.com) w ogóle nie kasuje, a
# keys.openpgp.org pokazuje klucz jako unieważniony — dlatego rewokacja jest
# właściwym sposobem „usunięcia” klucza z obiegu.
# Certyfikat ląduje w ~/.config/git-configuration-signing/revoke-<fpr>.asc
# (0600; zachowaj — jest też zapasem, gdy stracisz klucz prywatny).
# Passphrase klucza poda się w pinentry gpg-agent.
# Usage: gpg_sw_revoke <keyid> [ubuntu|openpgp|both|none]   (domyślnie both)
# Powód: GPG_SW_REVOKE_REASON = 0 brak (domyślnie) | 1 skompromitowany |
#        2 zastąpiony | 3 nieużywany
##
function gpg_sw_revoke() {
    _gpg_sw_check_deps || return 1
    local keyid="${1:-}" target="${2:-both}" reason="${GPG_SW_REVOKE_REASON:-0}"

    if [ -z "$keyid" ]; then
        log_error "Usage: gpg_sw_revoke <keyid> [ubuntu|openpgp|both|none]"
        return 1
    fi
    if ! [[ "$keyid" =~ ^(0x)?[0-9A-Fa-f]{8,40}$ ]]; then
        log_error "gpg_sw: '$keyid' nie wygląda na keyid/fingerprint (hex, 8-40 znaków)"
        return 1
    fi
    case "$target" in
        ubuntu|openpgp|both|none) : ;;
        *) log_error "gpg_sw: nieznany cel '$target' (ubuntu|openpgp|both|none)"; return 1 ;;
    esac
    case "$reason" in
        [0-3]) : ;;
        *) log_error "gpg_sw: GPG_SW_REVOKE_REASON musi być 0-3"; return 1 ;;
    esac

    mkdir -p "$(_gpg_sw_config_dir)"
    chmod 700 "$(_gpg_sw_config_dir)"
    local cert
    cert="$(_gpg_sw_config_dir)/revoke-${keyid#0x}.asc"

    # GnuPG ≥ 2.1 zapisuje certyfikat odwołania przy generowaniu klucza w
    # $GNUPGHOME/openpgp-revocs.d/<fpr>.rev (z dwukropkiem przed nagłówkiem, żeby
    # nie dało się go zaimportować przez pomyłkę) — użyj go: bez passphrase i
    # bez interakcji. Własny powód (REASON != 0) wymaga świeżego --gen-revoke.
    local fpr rev
    fpr=$(gpg --list-keys --with-colons "$keyid" 2>/dev/null | awk -F: '/^fpr:/ { print $10; exit }')
    rev="${GNUPGHOME:-$HOME/.gnupg}/openpgp-revocs.d/${fpr}.rev"
    if [ "$reason" = 0 ] && [ -n "$fpr" ] && [ -f "$rev" ]; then
        log_info "gpg_sw: używam certyfikatu odwołania wygenerowanego razem z kluczem ($rev)"
        sed 's/^:-----BEGIN PGP PUBLIC KEY BLOCK-----/-----BEGIN PGP PUBLIC KEY BLOCK-----/' "$rev" > "$cert" || {
            log_error "gpg_sw: nie udało się odczytać $rev"
            return 1
        }
    else
        # bez --batch: --gen-revoke odmawia pracy w trybie wsadowym; odpowiedzi
        # na pytania idą przez --command-fd (potwierdzenie, powód, opis, ok)
        log_info "gpg_sw: generuję certyfikat odwołania $keyid — podaj passphrase gdy poprosi"
        printf 'y\n%s\n\ny\n' "$reason" | gpg --yes --command-fd 0 --output "$cert" --armor --gen-revoke "$keyid" || {
            log_error "gpg_sw: generowanie certyfikatu odwołania nie powiodło się"
            return 1
        }
    fi
    chmod 600 "$cert"

    gpg --batch --import "$cert" || {
        log_error "gpg_sw: import certyfikatu odwołania nie powiódł się"
        return 1
    }
    log_info "gpg_sw: klucz $keyid odwołany lokalnie (certyfikat: $cert)"

    [ "$target" = none ] && return 0
    gpg_sw_export "$keyid" "$target" noverify
}

##
# Usuwa z lokalnego keyringu WSZYSTKIE klucze prywatne (i ich publiczne
# odpowiedniki), kasuje config gpg-sw.cfg i wyłącza profil gpg-sw-signing w
# ~/.m2/settings.xml. Operacja nieodwracalna — wymaga wpisania "TAK"
# (pomijalne przez GPG_SW_ASSUME_YES=1). Kluczy wysłanych na keyservery nie da
# się stamtąd usunąć — dlatego PRZED usunięciem klucze są odwoływane
# (gpg_sw_revoke) i odwołanie publikowane na keyserwerach. Sterowanie:
# GPG_SW_REVOKE=1 zawsze | 0 nigdy | brak → pytanie [T/n].
# Stuby kluczy z karty też znikną z keyringu (karta zachowuje klucz; odtworzysz
# je przez gpg_git_setup / gpg --card-status).
##
function gpg_sw_delete_all() {
    _gpg_sw_check_deps || return 1
    local fprs fpr rc=0
    fprs=$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^sec:/ { want=1; next } want && /^fpr:/ { print $10; want=0 }')
    if [ -z "$fprs" ]; then
        log_warn "gpg_sw: brak kluczy prywatnych w keyringu — nic do usunięcia"
        return 0
    fi

    log_warn "gpg_sw: zostaną NIEODWRACALNIE usunięte klucze (prywatne + publiczne):"
    gpg --list-secret-keys --keyid-format=long
    if [ "${GPG_SW_ASSUME_YES:-0}" != 1 ]; then
        local confirm
        read -r -p "Wpisz TAK, aby usunąć wszystkie powyższe klucze: " confirm
        if [ "$confirm" != TAK ]; then
            log_info "gpg_sw: anulowano"
            return 1
        fi
    fi

    local revoke="${GPG_SW_REVOKE:-}"
    if [ -z "$revoke" ]; then
        read -r -p "Odwołać klucze i opublikować odwołanie na keyserverach przed usunięciem? [T/n] " revoke
        revoke="${revoke:-T}"
    fi
    case "$revoke" in
        1|[tTyY]*) revoke=1 ;;
        *) revoke=0 ;;
    esac

    while IFS= read -r fpr; do
        [ -n "$fpr" ] || continue
        if [ "$revoke" = 1 ]; then
            gpg_sw_revoke "$fpr" both || {
                log_error "gpg_sw: odwołanie $fpr nie powiodło się — pomijam usuwanie tego klucza"
                rc=1
                continue
            }
        fi
        if gpg --batch --yes --delete-secret-and-public-keys "$fpr"; then
            log_info "gpg_sw: usunięto $fpr"
        else
            log_error "gpg_sw: nie udało się usunąć $fpr"
            rc=1
        fi
    done <<< "$fprs"

    if [ "$rc" -ne 0 ]; then
        log_warn "gpg_sw: nie wszystkie klucze usunięte — zostawiam gpg-sw.cfg i profil gpg-sw-signing"
        return "$rc"
    fi
    rm -f "$(_gpg_sw_cfg_path)"
    gpg_maven_disable
    return 0
}

##
# Jedno polecenie na cały proces: generuje klucz, eksportuje na keyserver,
# opcjonalnie dopina do Mavena. Interaktywne pytania pomijalne przez
# GPG_SW_NAME/GPG_SW_EMAIL/GPG_SW_EXPORT_TARGET/GPG_SW_MAVEN_CONFIRM.
##
function gpg_sw_setup() {
    _gpg_sw_check_deps || return 1
    local name email keyid target confirm

    name="${GPG_SW_NAME:-}"
    [ -z "$name" ] && read -r -p "Imię i nazwisko (User ID klucza): " name
    email="${GPG_SW_EMAIL:-}"
    [ -z "$email" ] && read -r -p "Adres email: " email
    if [ -z "$name" ] || [ -z "$email" ]; then
        log_error "gpg_sw: imię i nazwisko oraz email są wymagane"
        return 1
    fi

    keyid=$(GPG_SW_NAME="$name" GPG_SW_EMAIL="$email" gpg_sw_generate) || return 1
    log_info "gpg_sw: wygenerowano klucz $keyid"

    target="${GPG_SW_EXPORT_TARGET:-}"
    if [ -z "$target" ]; then
        read -r -p "Eksport na keyserver [ubuntu/openpgp/both/none] (both): " target
        target="${target:-both}"
    fi
    if [ "$target" != none ]; then
        gpg_sw_export "$keyid" "$target"
    fi

    confirm="${GPG_SW_MAVEN_CONFIRM:-}"
    if [ -z "$confirm" ]; then
        read -r -p "Dodać ten klucz do konfiguracji Mavena (~/.m2/settings.xml)? [T/n] " confirm
        confirm="${confirm:-T}"
    fi
    case "$confirm" in
        [tTyY]*) gpg_maven_setup "$keyid" ;;
        *) log_info "gpg_sw: pominięto konfigurację Mavena — uruchom później: gpg_maven_setup $keyid" ;;
    esac
}

export -f gpg_sw_list_keys
export -f gpg_sw_generate
export -f gpg_sw_export
export -f gpg_sw_revoke
export -f gpg_maven_setup
export -f gpg_maven_disable
export -f gpg_sw_delete_all
export -f gpg_sw_setup
