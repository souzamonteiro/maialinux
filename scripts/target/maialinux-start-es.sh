#!/usr/bin/env bash
# Keep startup errors on the SD card and release Plymouth before gaming starts.
set -uo pipefail
LOG_DIR="${HOME:-/home/ark}/.local/state/maialinux"
mkdir -p "$LOG_DIR" || exit 1
exec >> "$LOG_DIR/emulationstation.log" 2>&1
echo "=== EmulationStation startup: $(date -Is) ==="
sudo -n timeout 5 /bin/plymouth quit 2>/dev/null || true
exec /usr/bin/emulationstation/emulationstation.sh "$@"
