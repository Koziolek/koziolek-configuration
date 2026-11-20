#!/bin/bash
# Przygotowanie katalogów narzędzi w wolumenie $JENKINS_HOME, potem normalny start Jenkinsa (jak w oryginalnym obrazie).
set -e

mkdir -p "$ASDF_DATA_DIR" "$SDKMAN_CANDIDATES_HOME/java" "$BUNDLE_PATH" 2>/dev/null ||
    echo "WARN: nie można utworzyć katalogów narzędzi w ${JENKINS_HOME:-/var/jenkins_home} (uprawnienia?)" >&2

# Dopóki nie zainstalowano JDK przez SDKMAN, `java` dla buildów = JDK obrazu (JAVA_HOME/PATH nie są wiszące).
# `sdk install java …` / `sdk default java …` podmienia ten symlink.
if [ ! -e "$SDKMAN_CANDIDATES_HOME/java/current" ]; then
    ln -sfn /opt/java/openjdk "$SDKMAN_CANDIDATES_HOME/java/current" 2>/dev/null || true
fi

exec /usr/bin/tini -- /usr/local/bin/jenkins.sh "$@"
