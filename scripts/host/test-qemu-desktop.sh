#!/usr/bin/env bash
# test-qemu-desktop.sh
# Runs and tests the ARM64 MaiaLinux LXQt desktop environment at the exact RG353V
# resolution (640x480) on the host PC using Bubblewrap (bwrap) + QEMU user-mode
# (qemu-aarch64-static) + Xephyr.
# Works rootlessly (no sudo required!) directly against a mounted SD card in the current user's media directory.
#
# Usage:
#   ./scripts/host/test-qemu-desktop.sh [rootfs_mount] [--screenshot-only|--interactive]

set -euo pipefail

if [[ "$EUID" -eq 0 ]]; then
    echo "Run the QEMU desktop as your normal desktop user, without sudo." >&2
    exit 1
fi

for tool in Xephyr xdpyinfo bwrap; do
    command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 1; }
done
QEMU_BIN="${QEMU_BIN:-$(command -v qemu-aarch64-static || true)}"
if [[ -z "$QEMU_BIN" ]]; then
    echo "Error: qemu-aarch64-static not found on host. Install 'qemu-user-static'." >&2
    exit 1
fi
# Check the actual UID mapping before opening a graphical window.
if ! USERNS_ERROR=$(bwrap --unshare-user --uid 1000 --gid 1000 --ro-bind / / -- /usr/bin/true 2>&1); then
    echo "$USERNS_ERROR" >&2
    echo "The host blocked Bubblewrap user namespaces. Check the AppArmor/kernel log." >&2
    echo "Optional Ubuntu administrator setup: $(dirname "${BASH_SOURCE[0]}")/setup-qemu-userns.sh" >&2
    exit 1
fi

CURRENT_USER="${USER:-$(id -un 2>/dev/null || echo root)}"
MEDIA_BASE="${MEDIA_BASE:-}"
if [[ -z "$MEDIA_BASE" ]]; then
    for candidate in "/media/$CURRENT_USER" "/run/media/$CURRENT_USER" "/media/${SUDO_USER:-$CURRENT_USER}" "/run/media/${SUDO_USER:-$CURRENT_USER}"; do
        [[ -d "$candidate" ]] && { MEDIA_BASE="$candidate"; break; }
done
    [[ -n "$MEDIA_BASE" ]] || MEDIA_BASE="/media/$CURRENT_USER"
fi
ROOTFS="${1:-$MEDIA_BASE/root}"
MODE="${2:---interactive}"
SCREENSHOT_OUT="${SCREENSHOT_OUT:-/tmp/maialinux-qemu-640x480.png}"
TEST_DISPLAY=":42"
LOG_DIR="$(mktemp -d /tmp/maialinux-qemu-logs.XXXXXX)"
echo "Session logs: $LOG_DIR"

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
SIM_HOME="$(mktemp -d /tmp/maialinux-sim-home.XXXXXX)"
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
Xephyr "$TEST_DISPLAY" -screen 640x480 -title "MaiaLinux RG353V (640x480 ARM64 QEMU)" -ac -br >"$LOG_DIR/xephyr.log" 2>&1 &
XEPHYR_PID=$!
BWRAP_PID=""

cleanup() {
    [[ -n "$BWRAP_PID" ]] && kill "$BWRAP_PID" 2>/dev/null || true
    kill "$XEPHYR_PID" 2>/dev/null || true
}
trap cleanup EXIT

for attempt in {1..50}; do
    if ! kill -0 "$XEPHYR_PID" 2>/dev/null; then
        cat "$LOG_DIR/xephyr.log" >&2
        exit 1
    fi
    if DISPLAY="$TEST_DISPLAY" xdpyinfo >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done
if ! DISPLAY="$TEST_DISPLAY" xdpyinfo >/dev/null 2>&1; then
    echo "Xephyr display $TEST_DISPLAY is unavailable; see $LOG_DIR/xephyr.log" >&2
    exit 1
fi

# Resolve user ark UID/GID dynamically from guest /etc/passwd
TARGET_UID="$(grep -E '^ark:' "$ROOTFS/etc/passwd" 2>/dev/null | cut -d: -f3 || true)"
[[ -n "$TARGET_UID" ]] || TARGET_UID="1000"
TARGET_GID="$(grep -E '^ark:' "$ROOTFS/etc/passwd" 2>/dev/null | cut -d: -f4 || true)"
[[ -n "$TARGET_GID" ]] || TARGET_GID="1000"

# Run the entire ARM64 LXQt session inside Bubblewrap chroot mapped to user ark
bwrap \
    --unshare-user --uid "$TARGET_UID" --gid "$TARGET_GID" \
    --die-with-parent --unshare-pid \
    --ro-bind "$ROOTFS" / \
    --bind /tmp /tmp \
    --ro-bind "$QEMU_BIN" /tmp/qemu-aarch64-static \
    --dev /dev \
    --proc /proc \
    --bind "$SIM_HOME" /home/ark \
    --setenv DISPLAY "$TEST_DISPLAY" \
    --setenv HOME "/home/ark" \
    --setenv USER "ark" \
    --setenv LOGNAME "ark" \
    --setenv XDG_RUNTIME_DIR "$SIM_HOME/.runtime" \
    --setenv MAIALINUX_LOG_DIR "$LOG_DIR" \
    --unsetenv SESSION_MANAGER \
    --unsetenv DBUS_SESSION_BUS_ADDRESS \
    --setenv XDG_SESSION_TYPE "x11" \
    --setenv XDG_CURRENT_DESKTOP "LXQt" \
    --setenv QT_QPA_PLATFORM "xcb" \
    --setenv QT_XCB_GL_INTEGRATION "none" \
    --setenv QT_QPA_PLATFORMTHEME "lxqt" \
    --setenv GDK_BACKEND "x11" \
    --setenv LD_LIBRARY_PATH "/etc/maialinux-runtime/lib:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu" \
    --setenv C_INCLUDE_PATH "/etc/maialinux-runtime/include:/etc/maialinux-runtime/include/aarch64-linux-gnu:/usr/include/aarch64-linux-gnu:/usr/include" \
    /tmp/qemu-aarch64-static /bin/bash -c '
        mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"

        # Start D-Bus session if the guest image provides it
        set -e
        trap "kill -TERM -1 2>/dev/null || true" EXIT

        if ! command -v startlxqt >/dev/null 2>&1; then
            echo "Desktop entry point 'startlxqt' not found in the guest image; this rootfs is not a full LXQt MaiaLinux desktop." >&2
            exit 1
        fi

        # Use dbus-run-session on Debian 13 for clean D-Bus lifecycle
        if command -v dbus-run-session >/dev/null 2>&1; then
            dbus-run-session startlxqt >"$MAIALINUX_LOG_DIR/lxqt-session.log" 2>&1 &
        else
            startlxqt >"$MAIALINUX_LOG_DIR/lxqt-session.log" 2>&1 &
        fi
        SESSION_PID=$!

        # Check readiness of window manager and LXQt panel
        READY=false
        for attempt in {1..120}; do
            kill -0 "$SESSION_PID" 2>/dev/null || exit 1
            if xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q "window id" &&
               xwininfo -root -tree 2>/dev/null | grep -Eq "640x24"; then
                READY=true
                break
            fi
            sleep 0.5
        done
        if [[ "$READY" != true ]]; then
            echo "Desktop did not become ready; inspect $MAIALINUX_LOG_DIR" >&2
            exit 1
        fi

        # A normal desktop starts without demo applications or an open keyboard.
        sleep 5

        scrot "$MAIALINUX_LOG_DIR/screen.png" 2>/dev/null || import -window root "$MAIALINUX_LOG_DIR/screen.png"

        if [[ "'"$MODE"'" == "--interactive" ]]; then
            echo "==> MaiaLinux 640x480 QEMU window is ready! Close the window or press Ctrl+C to exit."
            wait
        fi
    ' &
BWRAP_PID=$!

if [[ "$MODE" == "--interactive" ]]; then
    # Stop waiting on the window if the guest session fails during startup.
    while kill -0 "$XEPHYR_PID" 2>/dev/null && kill -0 "$BWRAP_PID" 2>/dev/null; do
        sleep 0.5
    done
    if ! kill -0 "$BWRAP_PID" 2>/dev/null; then
        wait "$BWRAP_PID"
    fi
else
    wait "$BWRAP_PID"
fi

if [[ -f "$LOG_DIR/screen.png" ]]; then
    cp -f "$LOG_DIR/screen.png" "$SCREENSHOT_OUT"
    echo "==> Captured 640x480 simulation screenshot: $SCREENSHOT_OUT"
fi
