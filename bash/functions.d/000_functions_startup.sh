#!/usr/bin/env bash
##
# Resizes the currently active window to full screen if running under X11
# and using xdotool ow gdbus ir swaymsg on Wayland
##
function resize_to_full () {
    # Routing po detect_display_env (130_function_screen.sh) zamiast heurystyki
    # "$DISPLAY => X11" — pod Wayland Xwayland ustawia $DISPLAY=:0, przez co
    # xdotool był wołany w sesji Wayland i sypał błędami XGetWindowProperty.
    local _disp
    if declare -F detect_display_env >/dev/null 2>&1; then
        _disp="$(detect_display_env)" || return 0
    elif [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = "wayland" ]; then
        _disp="wayland"
    elif [ "${XDG_SESSION_TYPE:-}" = "x11" ] || [ -n "${DISPLAY:-}" ]; then
        _disp="x11"
    else
        return 0
    fi

    case "$_disp" in
        darwin|""|wayland|wlroots)
            return 0
            ;;
        gnome)
            command -v gdbus >/dev/null 2>&1 || return 0
            gdbus call --session \
              --dest org.gnome.Shell \
              --object-path /org/gnome/Shell \
              --method org.gnome.Shell.Eval \
              'global.display.focus_window.toggle_fullscreen();' \
              >/dev/null 2>&1
            return 0
            ;;
        sway)
            command -v swaymsg >/dev/null 2>&1 && swaymsg fullscreen toggle >/dev/null 2>&1
            return 0
            ;;
        x11)
        # Check if xdotool is installed
        if ! command -v xdotool >/dev/null 2>&1; then
            return 0
        fi

        local win_id
        win_id="$(xdotool getactivewindow)"

      if [ -z "$win_id" ]; then
          echo "No active window found"
          return 0
      fi

        local geom
        geom="$(xwininfo -id "$win_id" -stats \
                  | awk '/Width:/{w=$2} /Height:/{h=$2} END{print w"x"h}')"
        local current_width="${geom%%x*}"
        local current_height="${geom##*x}"

        local _d="${DISPLAY//:/_}"
        local _xrandr_cache="$HOME/.cache/display_max_size_${_d//\//_}"
        # Cache wygasa po godzinie, żeby zmiana monitora (inna rozdzielczość natywna)
        # nie została na stałe z nieaktualnym wpisem z poprzedniej sesji na tym $DISPLAY.
        if [ ! -s "$_xrandr_cache" ] || [ -n "$(find "$_xrandr_cache" -mmin +60 2>/dev/null)" ]; then
            xrandr | awk '/\*/{print $1}' > "$_xrandr_cache"
        fi
        local max_size
        readarray -t max_size < "$_xrandr_cache"

        local is_max=0
        for res in "${max_size[@]}" ; do
          local max_width
          local max_height
          IFS='x' read -r max_width max_height <<< "$res"
          if [[ ("$current_width" == "$max_width" &&  "$current_height" == "$max_height")
            || ("$current_width" == "$max_height" &&  "$current_height" == "$max_width") ]]; then
               is_max=1
               break
          fi
        done

        if [[ $is_max -eq 0 ]]; then
             xdotool key F11
        fi
        return 0
            ;;
    esac
}

##
# Uruchamia tmux lub dołącza do istniejącej sesji "main".
# Layout początkowy tworzony tylko raz — przy pierwszym uruchomieniu sesji.
##
function run_tmux () {
    if ! command -v tmux >/dev/null 2>&1; then
        return 0
    fi
    if [[ "$TERM" =~ screen ]] || [ -n "$TMUX" ]; then
        return 0
    fi
    local SESSION="main"
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        bash "${MAIN_CONFIGURATION_DIR}/tmux/session-init.sh"
    fi
    exec tmux attach-session -t "$SESSION"
}

##
# Prints an ASCII art logo using neofetch
# Expects $BASH_CONFIGURATION_DIR/logo-ascii-art.txt to exist
##
function print_logo () {
    if ! command -v neofetch >/dev/null 2>&1; then
        echo "Error: 'neofetch' is not installed or not found in PATH."
        return 1
    fi

    if [ -z "$BASH_CONFIGURATION_DIR" ] || [ ! -f "$BASH_CONFIGURATION_DIR/logo-ascii-art.txt" ]; then
        echo "Error: logo-ascii-art.txt not found in \$BASH_CONFIGURATION_DIR."
        return 1
    fi

    _LOGO_TMP=$(mktemp)
    neofetch --ascii "$BASH_CONFIGURATION_DIR/logo-ascii-art.txt" >"$_LOGO_TMP" 2>&1 &
    _LOGO_PID=$!

    _show_logo() {
        wait "$_LOGO_PID" 2>/dev/null
        cat "$_LOGO_TMP"
        rm -f "$_LOGO_TMP"
        unset _LOGO_PID _LOGO_TMP
        PROMPT_COMMAND="${PROMPT_COMMAND//_show_logo;/}"
        PROMPT_COMMAND="${PROMPT_COMMAND//_show_logo/}"
        unset -f _show_logo
    }
    PROMPT_COMMAND="_show_logo${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
}

function supports_colors() {
    if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
        local colors=$(tput colors 2>/dev/null)
        [[ $colors -ge 8 ]]
    else
        return 1
    fi
}

function set_dirtrim_by_path_length() {
    local full_path="$PWD"
    local display_path="${full_path/#$HOME/~}"
    if [ "${#display_path}" -gt 20 ]; then
        export PROMPT_DIRTRIM=1
    else
        export PROMPT_DIRTRIM=3
    fi
}

function verify_configuration() {
  check_workspace
  return 0;
}

# DO NOT EXPORT FUNCTIONS
# We need them only during evaluation of $HOME/.bashrc file, and they should not be avaliable after that.