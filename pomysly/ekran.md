# Zarządzanie ekranem

Pierwotny pomysł (skrypt poniżej) — **poprawiony** wg analizy z 2026-08-08 (patrz niżej):
wywołanie `SetPowerSaveMode` zmienione z nieistniejącej metody na `Properties.Set`. Reszta
(`_fp_on`/`_fp_off`/watcher) bez zmian względem oryginalnego pomysłu.

```bash
fake_poweroff() {
    local ACTION="${1:-off}"
    local PIDFILE="/tmp/fake-poweroff.pid"
    local desktop="${XDG_CURRENT_DESKTOP:-}"
    local session="${XDG_SESSION_TYPE:-}"
    local env=""

    # --- detekcja środowiska ---
    if [[ "$desktop" == *GNOME* ]] && command -v gdbus >/dev/null; then
        env="gnome"
    elif [[ "$session" == "x11" ]] && command -v xset >/dev/null; then
        env="x11"
    elif [[ "$session" == "wayland" ]] && command -v wlopm >/dev/null; then
        env="wlroots"
    else
        echo "[fake_poweroff] Nie rozpoznano środowiska (desktop=$desktop, session=$session)." >&2
        echo "[fake_poweroff] Zainstaluj: xset (X11), wlopm (wlroots), lub uruchom pod GNOME." >&2
        return 1
    fi

    # --- akcje sterujące monitorem ---
    _fp_off() {
        case "$env" in
            gnome)
                gdbus call --session \
                    --dest org.gnome.Mutter.DisplayConfig \
                    --object-path /org/gnome/Mutter/DisplayConfig \
                    --method org.freedesktop.DBus.Properties.Set \
                    org.gnome.Mutter.DisplayConfig PowerSaveMode "<int32 3>" >/dev/null
                ;;
            x11)
                xset +dpms
                xset dpms force off
                ;;
            wlroots)
                for out in $(wlopm | cut -d' ' -f1); do wlopm --off "$out"; done
                ;;
        esac
    }

    _fp_on() {
        case "$env" in
            gnome)
                gdbus call --session \
                    --dest org.gnome.Mutter.DisplayConfig \
                    --object-path /org/gnome/Mutter/DisplayConfig \
                    --method org.freedesktop.DBus.Properties.Set \
                    org.gnome.Mutter.DisplayConfig PowerSaveMode "<int32 0>" >/dev/null
                ;;
            x11)
                xset dpms force on
                ;;
            wlroots)
                for out in $(wlopm | cut -d' ' -f1); do wlopm --on "$out"; done
                ;;
        esac
    }

    case "$ACTION" in
        off)
            _fp_off
            echo "[fake_poweroff] Monitor wygaszony ($env)." >&2

            # watcher tylko dla gnome/wlroots - X11 DPMS budzi się sam
            if [[ "$env" != "x11" ]] && command -v libinput >/dev/null; then
                (
                    stdbuf -oL libinput debug-events 2>/dev/null | while IFS= read -r line; do
                        case "$line" in
                            *POINTER_MOTION*|*POINTER_BUTTON*|*KEYBOARD_KEY*)
                                _fp_on
                                break
                                ;;
                        esac
                    done
                    rm -f "$PIDFILE"
                ) &
                disown
                echo $! > "$PIDFILE"
            elif [[ "$env" != "x11" ]]; then
                echo "[fake_poweroff] Brak libinput - zainstaluj 'libinput-tools' dla auto-wybudzenia." >&2
            fi
            ;;
        on)
            _fp_on
            [[ -f "$PIDFILE" ]] && kill "$(cat "$PIDFILE")" 2>/dev/null && rm -f "$PIDFILE"
            echo "[fake_poweroff] Monitor przywrócony ($env)." >&2
            ;;
        *)
            echo "Użycie: fake_poweroff {off|on}" >&2
            return 1
            ;;
    esac
}
```

Zarządzamy stanem ekranów. Podpięcie do M3(?) lub jakiejś kombinacji. 

## Analiza pod kątem tej maszyny (2026-08-08)

Środowisko: Ubuntu 24.04, GNOME (`ubuntu:GNOME`), sesja X11. Skrypt wybierze gałąź `gnome`
(gdbus obecny) — to dobrze, Mutter obsługuje przez tę samą metodę i X11, i Wayland.

Znalezione problemy:

1. 🔴 **Był realny bug, już poprawiony w skrypcie wyżej** — `--method
   org.gnome.Mutter.DisplayConfig.SetPowerSaveMode` nie istnieje w obecnym Mutterze.
   Potwierdzone realnym wywołaniem na tej maszynie:
   `Błąd: GDBus.Error:org.freedesktop.DBus.Error.UnknownMethod: Brak metody „SetPowerSaveMode"`.
   `PowerSaveMode` to `readwrite` property (potwierdzone introspekcją), więc trzeba wołać przez
   standardowy interfejs Properties — dokładnie tak, jak jest teraz w skrypcie na górze pliku.
2. 🟡 `libinput-tools` (dostarcza `libinput debug-events`, potrzebne do auto-wybudzenia na
   ruch/klawisz) — **niezainstalowane** na tej maszynie. Skrypt się nie wywali (ma fallback
   z warningiem), ale funkcja auto-wybudzenia nie zadziała bez tego pakietu.
3. 🟡 Nawet po instalacji `libinput-tools` — user **nie jest w grupie `input`**
   (`getent group input` istnieje, ale `groups` usera jej nie zawiera). `libinput debug-events`
   czyta `/dev/input/*`, zwykle zablokowane dla zwykłego usera bez tej grupy. Wymaga
   `sudo usermod -aG input $USER` + wylogowanie/zalogowanie (nie da się tego zastosować w
   trakcie trwającej sesji).
4. ✓ `xset` obecny (fallback czysty X11 bez GNOME) — nieużywany na tej maszynie, ale gotowy.
5. N/A `wlopm` (Wayland/wlroots) — nieistotne, maszyna jest na X11.

## Istniejąca detekcja środowiska w repo

Współdzielona funkcja: `detect_display_env()` w `bash/functions.d/130_function_screen.sh` —
zwraca (echo) jedno słowo: `darwin`, `gnome`, `sway`, `wlroots`, `x11`, `wayland`, albo pusty
string + status 1. Sprawdza `WAYLAND_DISPLAY`/`XDG_SESSION_TYPE` przed `$DISPLAY` (Xwayland
ustawia `$DISPLAY=:0`, więc heurystyka „DISPLAY => X11" była fałszywa pod Wayland).

`resize_to_full` (`000_functions_startup.sh`) **routuje już przez `detect_display_env`** —
`case` na wykryte środowisko (gnome→gdbus Eval, sway→swaymsg, x11→xdotool F11, reszta→no-op).
`fake_poweroff` (poniżej, jeszcze niezaimplementowane) ma pójść tym samym wzorcem: `env=$(detect_display_env)`
zamiast własnej detekcji z linii 15-26.

## Plan wdrożenia (do zrobienia, nie zrobione jeszcze)

1. Dodać funkcję `fake_poweroff` (już poprawioną wersję ze skryptu na górze pliku) do
   `bash/functions.d/130_function_screen.sh` (obok `detect_display_env`), korzystającą z niej
   zamiast własnej inline detekcji (linie 15-26 skryptu wyżej — do zamiany na jedno wywołanie
   `env=$(detect_display_env)`).
2. ✓ **Zrobione**: `libinput-tools` dodany do `diag_tools` w `packages/apt_packages.sh`
   (dostępny w domyślnym `universe` Ubuntu 24.04, bez dodatkowych repo/kluczy). Nie dodany
   do `packages/brew_packages.sh` — brak sensownego odpowiednika na macOS dla tej funkcji.
   Przy okazji dodany też `rocminfo` (AMD ROCm GPU info, też tylko Linux/`universe`).
3. Udokumentować krok ręczny: `sudo usermod -aG input $USER` + wylogowanie — nie da się
   zautomatyzować bez utraty bieżącej sesji, więc to komunikat/instrukcja przy pierwszym
   użyciu (`fake_poweroff` może sprawdzić `groups | grep -qw input` i ostrzec, jeśli brak).
4. Export funkcji + dopisanie do `bash_customs_usage` (helper listing w `bash_functions.sh`,
   patrz D4/pkt 10 z code-review/CR.md — trzymać spójność, nie zostawiać nieudokumentowanej).
5. Podpięcie pod skrót klawiszowy — do ustalenia z użytkownikiem (GNOME custom keybinding
   przez `gsettings`/Ustawienia, nie coś co ten skrypt/repo powinno konfigurować automatycznie
   bez wyraźnej zgody — zmiana systemowych ustawień GNOME to already invazyjniejszy krok niż
   dodanie funkcji powłoki).
6. Test end-to-end na żywo: `fake_poweroff off` (widoczny, przerywający efekt — do zrobienia
   świadomie, w dogodnym momencie, nie w trakcie sesji roboczej) + potwierdzenie że ruch
   myszą/klawiszem faktycznie budzi ekran przez watcher.