#!/usr/bin/env bash
##
# Resizes the currently active window to full screen if running under X11
# and using xdotool ow gdbus ir swaymsg on Wayland
##
function resize_to_full () {
    # Only run if X11 session
    if [ "$XDG_SESSION_TYPE" = "x11" ]; then
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

        local current_width
        current_width="$(xwininfo -id "$win_id" -stats \
                          | grep -E '(Width):' \
                          | awk '{print $2}')"
        local current_height
        current_height="$(xwininfo -id "$win_id" -stats \
                          | grep -E '(Height):' \
                          | awk '{print $2}')"

        local max_size

        readarray -t max_size < <(xrandr | grep -E '\*' | awk '{print $1}')

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
    elif [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        # --- GNOME ---
        if command -v gdbus >/dev/null 2>&1; then
            echo "Attempting to toggle fullscreen in GNOME"
            gdbus call --session \
              --dest org.gnome.Shell \
              --object-path /org/gnome/Shell \
              --method org.gnome.Shell.Eval \
              'global.display.focus_window.toggle_fullscreen();' \
              >/dev/null 2>&1
            return $?
        fi

        # --- sway / wlroots-based compositor ---
        if command -v swaymsg >/dev/null 2>&1; then
            echo "Attempting to toggle fullscreen in Sway"
            swaymsg fullscreen toggle
            return $?
        fi

        echo "Wayland session detected, but no supported window manager interface found (gdbus/swaymsg missing)"
        return 0
    else
        echo "Unsupported session type: $XDG_SESSION_TYPE"
        return 0
    fi
}

##
# Runs tmux if not inside a tmux session already
##
function run_tmux () {
    if command -v tmux >/dev/null 2>&1; then
        # If not in a tmux session and not in a TERM that starts with "screen"
        if [[ ! "$TERM" =~ screen ]] && [ -z "$TMUX" ]; then
            exec tmux
        fi
    fi
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

    neofetch --ascii "$BASH_CONFIGURATION_DIR/logo-ascii-art.txt"
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
  return 0;
}

# DO NOT EXPORT FUNCTIONS
# We need them only during evaluation of ~/.bashrc file, and they should not be avaliable after that.