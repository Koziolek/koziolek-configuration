install_lib -r "https://github.com/kward/shunit2.git" -t "shunit2" -e "shunit2.sh"
install_lib -r "https://github.com/Koziolek/BashMan.git" -t "BashMan" -e "bashman.sh" -x
install_lib -r "https://github.com/Koziolek/FossFLOW.git" -t "FossFLOW"
install_lib -r "https://github.com/juven/maven-bash-completion.git" -t "maven-bash-completion"
install_lib -r "git@github.com:Koziolek/fix-comp.git" -t "fix-comp" -p

if [ ! -L $HOME/.maven-bash-completion ] && [ ! -d $HOME/.maven-bash-completion ]; then
    ln -s $WORKSPACE_TOOLS/maven-bash-completion $HOME/.maven-bash-completion
fi

# pre_analyze — uruchamia pre-analyze.sh z fix-comp z dowolnego katalogu roboczego.
# Skrypt sam liczy swoją lokalizację przez ${BASH_SOURCE[0]} (nie $PWD), więc podanie
# pełnej ścieżki wystarcza — logi trafiają do $WORKSPACE_TOOLS/fix-comp/logs, dokładnie
# jak przy bezpośrednim `bash pre-analyze.sh` z tego katalogu. Argumenty (-d, -m, -s,
# --profile, --env, --list-profiles) przechodzą bez zmian.
pre_analyze() {
    local script="$WORKSPACE_TOOLS/fix-comp/pre-analyze.sh"
    if [ ! -x "$script" ]; then
        log_error "pre_analyze: brak $script (fix-comp niesklonowany? sprawdź install_lib -p wyżej)"
        return 1
    fi
    bash "$script" "$@"
}
export -f pre_analyze
