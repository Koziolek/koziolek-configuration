#!/usr/bin/env bash
# Lista narzędzi, języków i bibliotek instalowanych przez sdkman i asdf.
# Sourcowane, nie wykonywane — same dane, zero efektów ubocznych przy sourcowaniu.
# Jedno miejsce prawdy dla {ubuntu,vanilla,redhat,mac}/{install,update}.sh.
#
# SDKMAN_CANDIDATES — nazwy kandydatów sdkman (`sdk install <nazwa>`), po jednej na element.
#
# ASDF_TOOLS — wpisy `nazwa|url pluginu|wersja`:
#   nazwa        nazwa pluginu asdf (`asdf plugin add <nazwa> <url>`)
#   url pluginu  repozytorium pluginu; puste = plugin z rejestru asdf
#   wersja       `latest` albo konkretna wersja (`asdf install <nazwa> <wersja>`)
# Pola nie mogą zawierać `|`; nazwa i wersja są wymagane.

SDKMAN_CANDIDATES=(
    java
    maven
    mvnd
)

ASDF_TOOLS=(
    "rust|https://github.com/asdf-community/asdf-rust.git|latest"
)
