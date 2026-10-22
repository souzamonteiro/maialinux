#!/usr/bin/env bash
# switch-boot-mode.sh
# Switches default boot target on the Anbernic RG353V between:
#   - es      (Dual-Mode: Boot into EmulationStation, launch LXQt from Tools menu)
#   - desktop (Desktop-First: Boot directly into MaiaLinux LXQt desktop)
#   - toggle  (Flip between the two modes)

set -euo pipefail

MODE="${1:-toggle}"
CUR_TTY="/dev/tty1"

current_mode() {
    if systemctl is-enabled --quiet maialinux-desktop.service 2>/dev/null; then
        echo "desktop"
    else
        echo "es"
    fi
}

if [[ "$MODE" == "toggle" ]]; then
    if [[ "$(current_mode)" == "desktop" ]]; then
        MODE="es"
    else
        MODE="desktop"
    fi
fi

case "$MODE" in
    es|dual)
        sudo systemctl disable maialinux-desktop.service 2>/dev/null || true
        sudo systemctl enable emulationstation.service 2>/dev/null || true
        MSG="Boot mode set to DUAL-MODE (EmulationStation on boot, MaiaLinux via Tools menu)."
        ;;
    desktop|lxqt)
        sudo systemctl disable emulationstation.service 2>/dev/null || true
        sudo systemctl enable maialinux-desktop.service 2>/dev/null || true
        MSG="Boot mode set to DESKTOP-FIRST (MaiaLinux LXQt directly on boot)."
        ;;
    status)
        echo "Current boot mode: $(current_mode)"
        exit 0
        ;;
    *)
        echo "Usage: $0 {es|desktop|toggle|status}"
        exit 1
        ;;
esac

echo "$MSG"
if [[ -w "$CUR_TTY" ]]; then
    printf "\033c" > "$CUR_TTY" 2>/dev/null || true
    echo "====================================================" > "$CUR_TTY"
    echo "  MaiaLinux Boot Mode Switcher" > "$CUR_TTY"
    echo "====================================================" > "$CUR_TTY"
    echo "  $MSG" > "$CUR_TTY"
    echo "====================================================" > "$CUR_TTY"
    sleep 3
fi
