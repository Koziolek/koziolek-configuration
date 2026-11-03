# Cienka warstwa na oficjalnym obrazie LTS: tylko wtyczki (jenkins-plugin-cli, wersje przypięte w
# plugins.txt). Narzędzia buildowe (JDK, Maven) NIE są w obrazie - Jenkins pobiera je sam przez
# tool installers z JCasC (casc/jenkins.yaml). Przebudowa po zmianie plugins.txt/tagu:
#   docker compose -f services/docker/docker-compose.yaml build jenkins
FROM jenkins/jenkins:2.580.2-lts-jdk21

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
