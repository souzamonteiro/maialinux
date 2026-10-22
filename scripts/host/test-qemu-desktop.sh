#!/usr/bin/env bash
# test-qemu-desktop.sh
# Runs and tests the ARM64 MaiaLinux LXQt desktop environment at the exact RG353V
# resolution (640x480) on the host PC using Bubblewrap (bwrap) + QEMU user-mode
# (qemu-aarch64-static) + Xephyr.
# Works rootlessly (no sudo required!) directly against a mounted SD card (/media/roberto/root).
#
# Usage:
#   ./scripts/host/test-qemu-desktop.sh [/media/roberto/root] [--screenshot-only|--interactive]

set -euo pipefail

ROOTFS="${1:-/media/roberto/root}"
MODE="${2:---interactive}"
SCREENSHOT_OUT="${SCREENSHOT_OUT:-/tmp/maialinux-qemu-640x480.png}"
TEST_DISPLAY=":42"

if [[ ! -d "$ROOTFS/usr/lib/aarch64-linux-gnu" ]]; then
    echo "Error: ARM64 rootfs not found at '$ROOTFS'" >&2
    exit 1
fi

echo "============================================================"
echo "  MaiaLinux 640x480 ARM64 QEMU + Bubblewrap + Xephyr Test"
echo "  Rootfs : $ROOTFS"
echo "  Mode   : $MODE"
echo "============================================================"

# Prepare temporary /home/ark overlay with our latest 640x480 configs & compiled examples
# (Skip copying 2.5 GB of .config/retroarch so startup is instant and uses <1 MB of /tmp)
SIM_HOME="/tmp/maialinux-sim-home"
rm -rf "$SIM_HOME"
mkdir -p "$SIM_HOME/.config/lxqt" \
         "$SIM_HOME/.config/openbox" \
         "$SIM_HOME/.config/pcmanfm-qt/lxqt" \
         "$SIM_HOME/.config/geany" \
         "$SIM_HOME/.config/featherpad" \
         "$SIM_HOME/.config/qterminal.org" \
         "$SIM_HOME/.config/autostart" \
         "$SIM_HOME/.local/share/applications" \
         "$SIM_HOME/Desktop" \
         "$SIM_HOME/projects"

for item in Desktop projects .bashrc .profile; do
    if [[ -e "$ROOTFS/home/ark/$item" ]]; then
        cp -rf "$ROOTFS/home/ark/$item" "$SIM_HOME/" 2>/dev/null || true
    fi
done
for cfg in lxqt openbox pcmanfm-qt geany featherpad qterminal.org autostart; do
    if [[ -d "$ROOTFS/home/ark/.config/$cfg" ]]; then
        cp -rf "$ROOTFS/home/ark/.config/$cfg" "$SIM_HOME/.config/" 2>/dev/null || true
    fi
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cp -f "$REPO_ROOT/config/lxqt/lxqt.conf" "$SIM_HOME/.config/lxqt/lxqt.conf"
cp -f "$REPO_ROOT/config/lxqt/panel.conf" "$SIM_HOME/.config/lxqt/panel.conf"
cp -f "$REPO_ROOT/config/lxqt/session.conf" "$SIM_HOME/.config/lxqt/session.conf"
cp -f "$REPO_ROOT/config/lxqt/openbox-lxqt-rc.xml" "$SIM_HOME/.config/openbox/lxqt-rc.xml"
cp -f "$REPO_ROOT/config/lxqt/pcmanfm-qt-settings.conf" "$SIM_HOME/.config/pcmanfm-qt/lxqt/settings.conf"
cp -f "$REPO_ROOT/config/geany/geany.conf" "$SIM_HOME/.config/geany/geany.conf"

# Pick a free Xephyr display number
for disp_num in 42 43 44 45 46; do
    if [[ ! -e "/tmp/.X${disp_num}-lock" ]]; then
        TEST_DISPLAY=":${disp_num}"
        break
    fi
done

# Start Xephyr 640x480 window on host X11 display
Xephyr "$TEST_DISPLAY" -screen 640x480 -title "MaiaLinux RG353V (640x480 ARM64 QEMU)" -ac -br >/dev/null 2>&1 &
XEPHYR_PID=$!
BWRAP_PID=""

cleanup() {
    [[ -n "$BWRAP_PID" ]] && kill "$BWRAP_PID" 2>/dev/null || true
    kill "$XEPHYR_PID" 2>/dev/null || true
}
trap cleanup EXIT

sleep 1

# Run the entire ARM64 LXQt session inside Bubblewrap chroot mapped to user ark (UID 1002)
bwrap \
    --unshare-user --uid 1002 --gid 1002 \
    --die-with-parent \
    --ro-bind "$ROOTFS" / \
    --dev /dev \
    --proc /proc \
    --bind /tmp /tmp \
    --bind "$SIM_HOME" /home/ark \
    --setenv DISPLAY "$TEST_DISPLAY" \
    --setenv HOME "/home/ark" \
    --setenv USER "ark" \
    --setenv LOGNAME "ark" \
    --setenv XDG_RUNTIME_DIR "/tmp/runtime-ark" \
    --setenv XDG_SESSION_TYPE "x11" \
    --setenv XDG_CURRENT_DESKTOP "LXQt" \
    --setenv QT_QPA_PLATFORM "xcb" \
    --setenv QT_QPA_PLATFORMTHEME "lxqt" \
    --setenv GDK_BACKEND "x11" \
    --setenv LD_LIBRARY_PATH "/etc/maialinux-runtime/lib:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu" \
    --setenv C_INCLUDE_PATH "/etc/maialinux-runtime/include:/etc/maialinux-runtime/include/aarch64-linux-gnu:/usr/include/aarch64-linux-gnu:/usr/include" \
    /usr/bin/qemu-aarch64-static /bin/bash -c '
        mkdir -p /tmp/runtime-ark && chmod 700 /tmp/runtime-ark

        # Start D-Bus session
        eval $(dbus-launch --sh-syntax)

        # Start Openbox with 640x480 rules
        openbox --config-file /home/ark/.config/openbox/lxqt-rc.xml >/tmp/bwrap-openbox.log 2>&1 &
        sleep 0.8

        # Start PCManFM-Qt Desktop & LXQt 24px Bottom Panel first
        pcmanfm-qt --desktop --profile=lxqt >/tmp/bwrap-pcmanfm.log 2>&1 &
        lxqt-panel >/tmp/bwrap-panel.log 2>&1 &
        sleep 2.2

        # Launch Geany IDE in foreground with SDL2 C project
        geany -i /home/ark/projects/hello-sdl2/main.c >/tmp/bwrap-geany.log 2>&1 &
        sleep 3

        # Launch docked Matchbox Virtual Keyboard at bottom (y=296, 640x160)
        matchbox-keyboard >/tmp/bwrap-mbk.log 2>&1 &
        sleep 1.5

        scrot -D "'"$TEST_DISPLAY"'" /tmp/bwrap-screen.png 2>/dev/null || import -display "'"$TEST_DISPLAY"'" -window root /tmp/bwrap-screen.png 2>/dev/null || true

        if [[ "'"$MODE"'" == "--interactive" ]]; then
            echo "==> MaiaLinux 640x480 QEMU window is ready! Close the window or press Ctrl+C to exit."
            wait
        fi
    ' &
BWRAP_PID=$!

if [[ "$MODE" == "--interactive" ]]; then
    wait "$XEPHYR_PID" 2>/dev/null || true
else
    wait "$BWRAP_PID" 2>/dev/null || true
fi

if [[ -f /tmp/bwrap-screen.png ]]; then
    cp -f /tmp/bwrap-screen.png "$SCREENSHOT_OUT"
    echo "==> Captured 640x480 simulation screenshot: $SCREENSHOT_OUT"
fi
