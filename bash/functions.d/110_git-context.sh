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
#   git_context
# ============================================================================

function git_context() {
  local readonly GC_CONFIG_FILE="${HOME}/.config/git-context"

  # ── Helper functions ───────────────────────────────────────────────────

  _gc_usage() {
    cat <<EOF
${C_BOLD}git_context${C_NC} – interaktywna konfiguracja kontekstu git

${C_BOLD}Użycie:${C_NC}
    git_context [-h|--help]

${C_BOLD}Opis:${C_NC}
    Interaktywnie konfiguruje git user.name, user.email i project.name
    na podstawie predefiniowanych kontekstów z pliku ~/.config/git-context

${C_BOLD}Plik konfiguracyjny:${C_NC}
    ~/.config/git-context

    Format:
      [context_name]
      name  = Your Full Name
      email = your.email@example.com
EOF
  }

  _gc_validate() {
    if [[ ! -f "$GC_CONFIG_FILE" ]]; then
      log_error "Brak pliku konfiguracyjnego: $GC_CONFIG_FILE"
      return 1
    fi

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
    done < "$GC_CONFIG_FILE"

    if [[ ${#GC_CTX_ORDER[@]} -eq 0 ]]; then
      log_error "Plik $GC_CONFIG_FILE nie zawiera żadnych kontekstów"
      return 1
    fi

    return 0
  }

  _gc_select_context() {
    local i choice

    log_man "\n${C_BOLD}Dostępne konteksty:${C_NC}"
    for i in "${!GC_CTX_ORDER[@]}"; do
      local ctx="${GC_CTX_ORDER[$i]}"
      printf "  ${C_YELLOW}%2d)${C_NC} %-20s  %s <%s>\n" \
        $((i + 1)) "$ctx" "${GC_CTX_NAME[$ctx]:-?}" "${GC_CTX_EMAIL[$ctx]:-?}"
    done
    echo

    while true; do
      read -rp "$(echo -e "${C_BOLD}Wybierz kontekst (0 wyjście) [1-${#GC_CTX_ORDER[@]}]:${C_NC} ")" choice
      
      # Obsługa wyjścia
      if (( choice == 0 )); then
        log_info "Anulowanie"
        return 0
      fi
      
      # Sprawdzenie zakresu
      if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#GC_CTX_ORDER[@]} )); then
        # Zwróć INDEKS, a nie wartość - będziemy dostępować bezpośrednio do tablicy
        return $((choice - 1))
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

  # ── Main logic ─────────────────────────────────────────────────────────

  # Deklaracja zmiennych - muszą być tutaj, zanim będą używane
  declare -A GC_CTX_NAME
  declare -A GC_CTX_EMAIL
  declare -a GC_CTX_ORDER

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
      _gc_usage
      return 0
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

  # Validate environment
  _gc_validate || return 1

  # Parse configuration file
  _gc_parse_config || return 1

  # Select context
  _gc_select_context
  local selected_idx=$?
  
  # Jeśli funkcja zwróciła 1, to anulowano
  if [[ $selected_idx -eq 0 ]]; then
    return 1
  fi
  
  local selected_ctx="${GC_CTX_ORDER[$selected_idx]}"

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
