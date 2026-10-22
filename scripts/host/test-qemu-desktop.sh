#!/usr/bin/env bash
# test-qemu-desktop.sh
# Tests the ARM64 MaiaLinux LXQt desktop environment at the exact RG353V resolution (640x480)
# on the host PC using QEMU user-mode (qemu-aarch64-static) + Xephyr (interactive window)
# or Xvfb (automated screenshot verification).
#
# Usage:
#   sudo ./scripts/host/test-qemu-desktop.sh [/media/roberto/root] [--headless]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS="${1:-/media/roberto/root}"
MODE="${2:---interactive}"
SCREENSHOT_OUT="/tmp/maialinux-qemu-640x480.png"
TEST_DISPLAY=":42"

if [[ $EUID -ne 0 ]]; then
    echo "Error: Run with sudo: sudo $0 [rootfs_path] [--headless|--interactive]" >&2
    exit 1
fi

echo "============================================================"
echo "  MaiaLinux 640x480 QEMU + X11 Desktop Simulator"
echo "  Rootfs : $ROOTFS"
echo "  Mode   : $MODE"
echo "============================================================"

# Create a test script inside target /tmp to run LXQt + Virtual Keyboard + Geany/Terminal
cat > "$ROOTFS/tmp/run-qemu-lxqt-test.sh" << 'EOF'
#!/usr/bin/env bash
set -uo pipefail

export DISPLAY=":42"
export XDG_SESSION_TYPE="x11"
export XDG_CURRENT_DESKTOP="LXQt"
export QT_QPA_PLATFORM="xcb"
export GDK_BACKEND="x11"
export HOME="/home/ark"
export USER="ark"

# Start Xvfb inside the ARM64 chroot at 640x480x24 if no X server is on :42 yet
if ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    Xvfb "$DISPLAY" -screen 0 640x480x24 -ac +extension GLX +render -noreset >/tmp/xvfb.log 2>&1 &
    XVFB_PID=$!
    sleep 2
fi

# Run Openbox + LXQt Panel + PCManFM-Qt Desktop + Matchbox Keyboard + QTerminal as user ark
su - ark -c "
    export DISPLAY=:42
    export XDG_SESSION_TYPE=x11
    export XDG_CURRENT_DESKTOP=LXQt
    export QT_QPA_PLATFORM=xcb
    export GDK_BACKEND=x11
    dbus-launch --sh-syntax > /tmp/dbus-env.sh
    source /tmp/dbus-env.sh
    openbox --config-file /home/ark/.config/openbox/lxqt-rc.xml >/tmp/openbox.log 2>&1 &
    sleep 1
    pcmanfm-qt --desktop --profile=lxqt >/tmp/pcmanfm.log 2>&1 &
    lxqt-panel >/tmp/lxqt-panel.log 2>&1 &
    sleep 2
    qterminal -e 'bash -c \"uname -a; gcc --version | head -n1; python3 --version; ls -la ~/projects; exec bash\"' >/tmp/qterminal.log 2>&1 &
    sleep 1
    matchbox-keyboard >/tmp/mbk.log 2>&1 &
    sleep 2
"

if [[ "${1:-}" == "--headless" ]]; then
    scrot -D "$DISPLAY" /tmp/maialinux-qemu-640x480.png || import -display "$DISPLAY" -window root /tmp/maialinux-qemu-640x480.png
    echo "Captured 640x480 screenshot to /tmp/maialinux-qemu-640x480.png"
    pkill -f "lxqt-panel|pcmanfm-qt|qterminal|matchbox-keyboard|openbox|Xvfb" 2>/dev/null || true
else
    echo "Interactive session running on $DISPLAY. Close the Xephyr window or press Ctrl+C to stop."
    wait
fi
EOF
chmod 755 "$ROOTFS/tmp/run-qemu-lxqt-test.sh"

if [[ "$MODE" == "--headless" ]]; then
    # Ensure xvfb is available inside chroot for headless testing
    "$SCRIPT_DIR/chroot-run.sh" "$ROOTFS" apt-get install -y xvfb
    "$SCRIPT_DIR/chroot-run.sh" "$ROOTFS" /tmp/run-qemu-lxqt-test.sh --headless
    if [[ -f "$ROOTFS/tmp/maialinux-qemu-640x480.png" ]]; then
        cp -f "$ROOTFS/tmp/maialinux-qemu-640x480.png" "$SCREENSHOT_OUT"
        chmod 644 "$SCREENSHOT_OUT"
        echo "==> Screenshot saved on host at: $SCREENSHOT_OUT"
    fi
else
    # If Xephyr is installed on host, open a 640x480 window on the host desktop and share /tmp/.X11-unix
    if command -v Xephyr >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
        Xephyr "$TEST_DISPLAY" -screen 640x480 -title "MaiaLinux RG353V (640x480)" -ac -br 2>/dev/null &
        XEPHYR_PID=$!
        sleep 1
        mkdir -p "$ROOTFS/tmp/.X11-unix"
        mount --bind /tmp/.X11-unix "$ROOTFS/tmp/.X11-unix"
        "$SCRIPT_DIR/chroot-run.sh" "$ROOTFS" /tmp/run-qemu-lxqt-test.sh --interactive || true
        umount -lf "$ROOTFS/tmp/.X11-unix" 2>/dev/null || true
        kill "$XEPHYR_PID" 2>/dev/null || true
    else
        echo "Xephyr not found on host; running headless verification and generating screenshot..."
        "$0" "$ROOTFS" --headless
    fi
fi
