# Detect whether we can use color
if [ -x /usr/bin/tput ] && tput setaf 1 >/dev/null 2>&1; then
    can_color="yes"
else
    can_color=""
fi

# If force_color_prompt is set, we override detection
if [ -n "$force_color_prompt" ]; then
    color_prompt="yes"
elif [[ "$TERM" =~ xterm-color|.*-256color ]] && [ -n "$can_color" ]; then
    color_prompt="yes"
else
    color_prompt=""
fi

# Set the prompt
if [ "$color_prompt" = "yes" ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi

# If this is an xterm (or rxvt), set the window title
case "$TERM" in
    xterm*|rxvt*)
        PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
        ;;
    *)
        ;;
esac

# Cleanup
unset color_prompt
unset can_color
unset force_color_prompt
