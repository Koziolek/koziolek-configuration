#!/usr/bin/env bash

# ============================================================================
# git-context – interaktywna konfiguracja projektu git
# ============================================================================
# Plik konfiguracyjny: ~/.config/git-context
#
# Format pliku:
#   [work]
#   name  = Jan Kowalski
#   email = jan.kowalski@firma.pl
#
#   [personal]
#   name  = janek99
#   email = janek@example.com
#
# Użycie:
#   git_context [-a|--add]
# ============================================================================

function git_context() {
  local readonly GC_CONFIG_FILE="${HOME}/.config/git-context"

  # ── Helper functions ───────────────────────────────────────────────────

  _gc_usage() {
    cat <<EOF
${C_BOLD}git_context${C_NC} – interaktywna konfiguracja kontekstu git

${C_BOLD}Użycie:${C_NC}
    git_context [-h|--help] [-a|--add]

${C_BOLD}Opis:${C_NC}
    Interaktywnie konfiguruje git user.name, user.email i project.name
    na podstawie predefiniowanych kontekstów z pliku ~/.config/git-context

${C_BOLD}Opcje:${C_NC}
    -a, --add    Dodaj nowy profil do pliku konfiguracyjnego

${C_BOLD}Plik konfiguracyjny:${C_NC}
    ~/.config/git-context

    Format:
      [context_name]
      name  = Your Full Name
      email = your.email@example.com
EOF
  }

  _gc_validate_git_repo() {
    if ! git rev-parse --git-dir &>/dev/null; then
      log_error "Bieżący katalog nie jest repozytorium git"
      return 1
    fi
    return 0
  }

  _gc_parse_config() {
    local current_ctx=""
    local line

    GC_CTX_ORDER=()

    while IFS= read -r line || [[ -n "$line" ]]; do
      # Pomiń komentarze i puste linie
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${line//[[:space:]]/}" ]] && continue

      if [[ "$line" =~ ^\[([^]]+)\]$ ]]; then
        current_ctx="${BASH_REMATCH[1]}"
        GC_CTX_ORDER+=("$current_ctx")
      elif [[ -n "$current_ctx" && "$line" =~ ^[[:space:]]*name[[:space:]]*=[[:space:]]*(.+)$ ]]; then
        GC_CTX_NAME["$current_ctx"]="${BASH_REMATCH[1]}"
      elif [[ -n "$current_ctx" && "$line" =~ ^[[:space:]]*email[[:space:]]*=[[:space:]]*(.+)$ ]]; then
        GC_CTX_EMAIL["$current_ctx"]="${BASH_REMATCH[1]}"
      fi
    done <"$GC_CONFIG_FILE"

    if [[ ${#GC_CTX_ORDER[@]} -eq 0 ]]; then
      log_error "Plik $GC_CONFIG_FILE nie zawiera żadnych kontekstów"
      return 1
    fi

    return 0
  }

  _gc_display_current_config() {
    local current_name current_email

    current_name="$(git config user.name 2>/dev/null || echo "${C_BOLD}(nie ustawiono)${C_NC}")"
    current_email="$(git config user.email 2>/dev/null || echo "${C_BOLD}(nie ustawiono)${C_NC}")"
    current_project="$(git config project.name 2>/dev/null || echo "${C_BOLD}(nie ustawiono)${C_NC}")"

    log_man "\n${C_BOLD}Bieżąca konfiguracja git:${C_NC}"
    log_info "user.name     = $current_name"
    log_info "user.email    = $current_email"
    log_info "project.name  = $current_project"
  }

  _gc_select_context() {
    local i choice

    _gc_display_current_config

    log_man "\n${C_BOLD}Dostępne konteksty:${C_NC}"
    for i in "${!GC_CTX_ORDER[@]}"; do
      local ctx="${GC_CTX_ORDER[$i]}"
      printf "  ${C_YELLOW}%2d)${C_NC} %-20s  %s <%s>\n" \
        $((i + 1)) "$ctx" "${GC_CTX_NAME[$ctx]:-?}" "${GC_CTX_EMAIL[$ctx]:-?}"
    done
    echo

    while true; do
      read -rp "$(echo -e "${C_BOLD}Wybierz kontekst (0 wyjście) [1-${#GC_CTX_ORDER[@]}]:${C_NC} ")" choice

      if ((choice == 0)); then
        log_info "Anulowanie"
        return 1
      fi

      if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#GC_CTX_ORDER[@]})); then
        GC_SELECTED_IDX=$((choice - 1))
        return 0
      fi

      log_warn "Nieprawidłowy wybór. Podaj liczbę od 1 do ${#GC_CTX_ORDER[@]} (0 aby wyjść)"
    done
  }

  _gc_validate_context() {
    local ctx="$1"

    if [[ -z "${GC_CTX_NAME[$ctx]:-}" ]]; then
      log_error "Kontekst '$ctx' nie ma zdefiniowanego 'name'"
      return 1
    fi

    if [[ -z "${GC_CTX_EMAIL[$ctx]:-}" ]]; then
      log_error "Kontekst '$ctx' nie ma zdefiniowanego 'email'"
      return 1
    fi

    return 0
  }

  _gc_configure_git() {
    local ctx="$1"
    local name="$2"
    local email="$3"

    log_man "\n${C_BOLD}Ustawiam konfigurację git:${C_NC}"
    log_man "  Kontekst: ${C_YELLOW}${ctx}${C_NC}"

    git config user.name "$name"
    git config user.email "$email"

    log_info "user.name  = $name"
    log_info "user.email = $email"
  }

  _gc_configure_project() {
    local default_project
    local project_name

    log_man "\n${C_BOLD}Nazwa projektu:${C_NC}"

    default_project="$(basename "$(git rev-parse --show-toplevel)")"

    while true; do
      read -rp "$(echo -e "${C_BOLD}Podaj nazwę projektu [${C_YELLOW}${default_project}${C_BOLD}]:${C_NC} ")" project_name
      project_name="${project_name:-$default_project}"
      [[ -n "${project_name// /}" ]] && break
      log_error "Nazwa projektu nie może być pusta"
    done

    git config project.name "$project_name"
    log_info "project.name = $project_name"
  }

  _gc_display_summary() {
    local key value

    log_man "\n${C_BOLD}Aktualna konfiguracja lokalna repozytorium:${C_NC}"
    echo
    git config --local --list | sort | while IFS='=' read -r key value; do
      printf "  ${C_CYAN}%-30s${C_NC} = %s\n" "$key" "$value"
    done
    echo
  }

  _gc_create_config() {
    local answer name email

    read -rp "$(echo -e "${C_BOLD}Plik $GC_CONFIG_FILE nie istnieje. Stworzyć? [t/N]:${C_NC} ")" answer
    if [[ "${answer,,}" != "t" ]]; then
      log_info "Anulowanie"
      return 1
    fi

    mkdir -p "$(dirname "$GC_CONFIG_FILE")"

    log_man "\n${C_BOLD}Dane dla profilu 'default':${C_NC}"

    while true; do
      read -rp "$(echo -e "${C_BOLD}Imię i nazwisko (user.name):${C_NC} ")" name
      [[ -n "${name// /}" ]] && break
      log_error "Pole nie może być puste"
    done

    while true; do
      read -rp "$(echo -e "${C_BOLD}Email (user.email):${C_NC} ")" email
      [[ -n "${email// /}" ]] && break
      log_error "Pole nie może być puste"
    done

    printf "[default]\nname  = %s\nemail = %s\n" "$name" "$email" > "$GC_CONFIG_FILE"
    log_info "Plik $GC_CONFIG_FILE utworzony z profilem 'default'"
  }

  _gc_add_profile() {
    local ctx_name name email

    while true; do
      read -rp "$(echo -e "${C_BOLD}Nazwa nowego profilu:${C_NC} ")" ctx_name
      [[ -n "${ctx_name// /}" ]] && break
      log_error "Nazwa profilu nie może być pusta"
    done

    if grep -q "^\[${ctx_name}\]" "$GC_CONFIG_FILE" 2>/dev/null; then
      log_error "Profil '$ctx_name' już istnieje w $GC_CONFIG_FILE"
      return 1
    fi

    log_man "\n${C_BOLD}Dane dla profilu '$ctx_name':${C_NC}"

    while true; do
      read -rp "$(echo -e "${C_BOLD}Imię i nazwisko (user.name):${C_NC} ")" name
      [[ -n "${name// /}" ]] && break
      log_error "Pole nie może być puste"
    done

    while true; do
      read -rp "$(echo -e "${C_BOLD}Email (user.email):${C_NC} ")" email
      [[ -n "${email// /}" ]] && break
      log_error "Pole nie może być puste"
    done

    printf "\n[%s]\nname  = %s\nemail = %s\n" "$ctx_name" "$name" "$email" >> "$GC_CONFIG_FILE"
    log_info "Profil '$ctx_name' dodany do $GC_CONFIG_FILE"
  }

  # ── Main logic ─────────────────────────────────────────────────────────

  # Deklaracja zmiennych - muszą być tutaj, zanim będą używane
  declare -A GC_CTX_NAME
  declare -A GC_CTX_EMAIL
  declare -a GC_CTX_ORDER

  local GC_ADD_MODE=0

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
      _gc_usage
      return 0
      ;;
    -a | --add)
      GC_ADD_MODE=1
      shift
      ;;
    -*)
      log_error "Nieznana opcja: $1"
      _gc_usage
      return 1
      ;;
    *)
      log_error "Nieznany argument: $1"
      _gc_usage
      return 1
      ;;
    esac
  done

  _gc_validate_git_repo || return 1

  if ((GC_ADD_MODE)); then
    if [[ ! -f "$GC_CONFIG_FILE" ]]; then
      log_error "Brak pliku konfiguracyjnego: $GC_CONFIG_FILE"
      log_info "Uruchom git_context bez parametrów aby utworzyć plik konfiguracyjny"
      return 1
    fi
    _gc_add_profile
    return $?
  fi

  if [[ ! -f "$GC_CONFIG_FILE" ]]; then
    _gc_create_config || return 1
  fi

  # Parse configuration file
  _gc_parse_config || return 1

  # Select context
  local GC_SELECTED_IDX=''
  _gc_select_context || return 1

  local selected_ctx="${GC_CTX_ORDER[$GC_SELECTED_IDX]}"

  # Validate selected context
  _gc_validate_context "$selected_ctx" || return 1

  # Configure git
  _gc_configure_git "$selected_ctx" "${GC_CTX_NAME[$selected_ctx]}" "${GC_CTX_EMAIL[$selected_ctx]}"

  # Configure project name
  _gc_configure_project

  # Display summary
  _gc_display_summary

  return 0
}

export -f git_context
