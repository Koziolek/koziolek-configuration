install_lib -r "https://github.com/kward/shunit2.git" -t "shunit2" -e "shunit2.sh"
install_lib -r "https://github.com/Koziolek/BashMan.git" -t "BashMan" -e "bashman.sh" -x
install_lib -r "https://github.com/Koziolek/FossFLOW.git" -t "FossFLOW"
install_lib -r "https://github.com/juven/maven-bash-completion.git" -t "maven-bash-completion"

if [ ! -L ~/.maven-bash-completion ] && [ ! -d ~/.maven-bash-completion ]; then
    ln -s $WORKSPACE_TOOLS/maven-bash-completion ~/.maven-bash-completion
fi
