# branch name in prompt
export PS1="\u@\h \[\033[32m\]\w\[\033[33m\]\$(parse_git_branch)\[\033[00m\] $ "
# printer name because cups sucks
export PRINTER='L6170'
# Add the directory of Tizen .NET Command Line Tools to user path.
export PATH=~/tizen-studio/tools/ide/bin:$PATH
export WORKSPACE=~/workspace
export WORKSPACE_TOOLS=$WORKSPACE/tools

# Export „secrets”
if [ -f ~/.senv ]; then
  . ~/.senv
fi
#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="/home/koziolek/.sdkman"
[ -s "/home/koziolek/.sdkman/bin/sdkman-init.sh" ] && . "/home/koziolek/.sdkman/bin/sdkman-init.sh"
