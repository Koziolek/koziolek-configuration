# Cienka warstwa na oficjalnym obrazie LTS: wtyczki (jenkins-plugin-cli, wersje przypięte w plugins.txt) oraz
# MENEDŻERY wersji narzędzi: asdf-vm i SDKMAN. Same narzędzia (Ruby, Node, Python, JDK, Maven, Gradle...) NIE są
# w obrazie - joby instalują dowolne wersje (`asdf install`, `sdk install`) do wolumenu $JENKINS_HOME, więc
# cache przeżywa przebudowę obrazu. JDK/Maven mogą też pochodzić z tool installers w JCasC (casc/jenkins.yaml).
# Przebudowa po zmianie plugins.txt/tagu/wersji asdf:
#   docker compose -f services/docker/docker-compose.yaml build jenkins
FROM jenkins/jenkins:2.580.2-lts-jdk21

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

USER root

# Kompilatory i nagłówki do budowy języków z źródeł (ruby-build, python-build, node-build, erlang...) oraz gemów /
# pakietów z natywnymi rozszerzeniami; zip/unzip/curl wymagane przez SDKMAN.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git curl ca-certificates zip unzip bash \
        build-essential pkg-config autoconf bison patch rustc libtool \
        libyaml-dev libssl-dev zlib1g-dev libffi-dev libreadline-dev libncurses-dev libgdbm-dev libgdbm-compat-dev \
        libbz2-dev libsqlite3-dev liblzma-dev libpq-dev libxml2-dev libxslt1-dev libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

# asdf-vm >= 0.16 (jedna binarka w Go, bez klonowania repo); pluginy i wersje w $ASDF_DATA_DIR (wolumen)
ARG ASDF_VERSION=0.18.0
RUN arch="$(dpkg --print-architecture)" \
    && curl -fsSL "https://github.com/asdf-vm/asdf/releases/download/v${ASDF_VERSION}/asdf-v${ASDF_VERSION}-linux-${arch}.tar.gz" \
        | tar -xz -C /usr/local/bin asdf \
    && asdf --version

# SDKMAN: skrypty w obrazie (/opt/sdkman), kandydaci (JDK, Maven, Gradle...) w wolumenie przez symlink
ENV SDKMAN_DIR=/opt/sdkman \
    SDKMAN_CANDIDATES_HOME=/var/jenkins_home/sdkman/candidates
RUN curl -fsSL "https://get.sdkman.io?rcupdate=false" | bash \
    && rm -rf "$SDKMAN_DIR/candidates" \
    && ln -s "$SDKMAN_CANDIDATES_HOME" "$SDKMAN_DIR/candidates" \
    && sed -i -e 's/^sdkman_auto_answer=.*/sdkman_auto_answer=true/' \
              -e 's/^sdkman_selfupdate_feature=.*/sdkman_selfupdate_feature=false/' \
              -e 's/^sdkman_colour_enable=.*/sdkman_colour_enable=false/' "$SDKMAN_DIR/etc/config" \
    && chown -R jenkins:jenkins "$SDKMAN_DIR"

# Kontroler Jenkinsa ma zawsze startować na własnym JDK z obrazu, niezależnie od JDK wybranego dla buildów
# (PATH poniżej stawia narzędzia SDKMAN/asdf przed JDK obrazu). Build pada głośno, gdy jenkins.sh się zmieni.
RUN sed -i 's#^\([[:space:]]*\)exec java #\1exec /opt/java/openjdk/bin/java #' /usr/local/bin/jenkins.sh \
    && grep -q '^[[:space:]]*exec /opt/java/openjdk/bin/java ' /usr/local/bin/jenkins.sh

# Joby instalujące narzędzia (SDKMAN, asdf) - preinstalowane w obrazie: jenkins.sh kopiuje /usr/share/jenkins/ref do
# $JENKINS_HOME przy starcie, a przyrostek .override wymusza nadpisanie config.xml (bez niego: tylko gdy brak).
COPY --chown=jenkins:jenkins jobs/ /usr/share/jenkins/ref/jobs/

COPY tools-entrypoint.sh /usr/local/bin/jenkins-tools-entrypoint.sh
RUN chmod +x /usr/local/bin/jenkins-tools-entrypoint.sh

USER jenkins

# Domyślne zachowanie dla WSZYSTKICH jobów (także `sh` z pipeline, bez logowania do powłoki):
#  - asdf: shimy w PATH; wersja z .tool-versions repozytorium lub `asdf set`;
#  - SDKMAN: `current/bin` popularnych kandydatów w PATH (po `sdk install`/`sdk default` zmiana działa od razu);
#    `sdk` jako funkcja wymaga `source "$SDKMAN_DIR/bin/sdkman-init.sh"` w bash.
#  - JAVA_HOME wskazuje na `current` JDK z SDKMAN (entrypoint ustawia domyślnie JDK obrazu, dopóki nic nie zainstalowano).
ENV ASDF_DATA_DIR=/var/jenkins_home/.asdf \
    ASDF_FORCE_PREPEND=yes \
    JAVA_HOME=/var/jenkins_home/sdkman/candidates/java/current \
    BUNDLE_PATH=/var/jenkins_home/bundle \
    BUNDLE_USER_HOME=/var/jenkins_home/.bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3
ENV PATH=/var/jenkins_home/.asdf/shims:/var/jenkins_home/sdkman/candidates/java/current/bin:/var/jenkins_home/sdkman/candidates/maven/current/bin:/var/jenkins_home/sdkman/candidates/mvnd/current/bin:/var/jenkins_home/sdkman/candidates/gradle/current/bin:/var/jenkins_home/sdkman/candidates/kotlin/current/bin:/var/jenkins_home/sdkman/candidates/groovy/current/bin:/var/jenkins_home/sdkman/candidates/scala/current/bin:/var/jenkins_home/sdkman/candidates/sbt/current/bin:/var/jenkins_home/sdkman/candidates/ant/current/bin:/usr/local/bin:/usr/bin:/bin:/opt/java/openjdk/bin

ENTRYPOINT ["/usr/local/bin/jenkins-tools-entrypoint.sh"]
