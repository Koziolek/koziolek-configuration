#!/bin/bash

# This script install custom git configuration.


# 1. We need to be root to run it.

AM_I_ROOT=`whoami`

if [ $AM_I_ROOT != "root" ]; then
    echo "Please run this script as root"
    exit 1;
fi

# 2. Check if git available if not install it
git --version 2>&1 >/dev/null # improvement by tripleee
GIT_IS_AVAILABLE=$?

if [ $GIT_IS_AVAILABLE -ne 0 ];
then
    echo "git is not available";
    echo "Should I install git? [y/N]";

    read install
    if [ $install = "y" ] || [ $install = "Y" ]; then
        yes | apt-get install git
    elif [ $install = "n" ] || [ $install = "N" ]; then
        echo "You need git"
        exit 1;
    else
        echo "You need git"
        exit 1;
    fi
fi

# 3. Check if we run from koziolek/git-configuration or fork
# or just run script from scratch
git status 2>&1 >/dev/null
IN_GIT_FOLDER=$?

if [ $IN_GIT_FOLDER -ne 0 ]; then
    echo "You run this script from scratch. I need to download some stuff."
    git clone git@github.com:Koziolek/git-configuration.git
    cd git-configuration
else
    git pull
fi

# 4. Installation of bash part
# 5. Installation of git part

