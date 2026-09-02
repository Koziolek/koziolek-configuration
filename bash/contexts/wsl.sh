#!/usr/bin/env bash
# Kontekst: wsl (Windows Subsystem for Linux). Łańcuch: linux debian wsl
# (WSL w praktyce zawsze siedzi na Ubuntu/Debianie → dziedziczy apt/hub z debian.sh).
# Dziedziczy wszystkie aliasy/ustawienia z contexts/{linux,debian}.sh — tu tylko to,
# co w WSL działa inaczej (interop z Windows).

# in-window: otwieranie plików/URL-i po stronie Windows.
# wslview (pakiet wslu) tłumaczy ścieżki i zna domyślną przeglądarkę;
# explorer.exe to fallback bez wslu.
if command -v wslview >/dev/null 2>&1; then
    alias in-window='wslview'
elif command -v explorer.exe >/dev/null 2>&1; then
    alias in-window='explorer.exe'
fi

# Schowek Windows z powłoki (gdy dostępne mostki .exe).
command -v clip.exe       >/dev/null 2>&1 && alias clip='clip.exe'
command -v powershell.exe >/dev/null 2>&1 && \
    alias paste='powershell.exe -NoProfile -Command Get-Clipboard'
