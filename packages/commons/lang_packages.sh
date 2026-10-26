#!/usr/bin/env bash
# Lista narzędzi instalowanych toolchainami języków (cargo, go, cabal) — odpowiednik apt_packages.sh.
# Sourcowane, nie wykonywane — same dane, zero efektów ubocznych przy sourcowaniu.
# Same toolchainy (rust, golang, ghc, cabal) są w sdk_tools.sh (ASDF_TOOLS); tu jest to, co one instalują.
# Konsument: packages/commons/lang_packages_apply.sh.
#
# Wpis: `pakiet` albo `pakiet|binarka`. Binarka służy do sprawdzenia, czy narzędzie już jest
# (install pomija zainstalowane); domyślnie:
#   CARGO_PACKAGES, CABAL_PACKAGES  nazwa pakietu małymi literami
#   GO_PACKAGES                     ostatni człon ścieżki importu, bez `@wersja`
# Pola nie mogą zawierać `|` poza separatorem.

# crates.io — `cargo install --locked <crate>`
CARGO_PACKAGES=(
    "difftastic|difft"
    linthis
)

# ścieżka importu z wersją — `go install <ścieżka>`
GO_PACKAGES=(
    mvdan.cc/sh/v3/cmd/shfmt@latest
)

# Hackage — `cabal install <pakiet>`
CABAL_PACKAGES=(
    ShellCheck
)
