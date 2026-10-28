#!/usr/bin/env bash
# start-maialinux.sh
# Launches the MaiaLinux LXQt Desktop Environment on the Anbernic RG353V.
# Works both when called from EmulationStation (Options -> Tools -> Launch MaiaLinux)
# and when called as a standalone systemd service (Desktop-First boot mode).

set -uo pipefail

CUR_TTY="/dev/tty1"
LOG_DIR="${HOME:-/home/ark}/.local/state/maialinux"
mkdir -p "$LOG_DIR" || exit 1
LOG_FILE="$LOG_DIR/desktop.log"
X_DISPLAY=":1"
X_VT="vt1"
GPTOKEYB_BIN="/opt/inttools/gptokeyb"
GPTOKEYB_CONF="/etc/maialinux/desktop.gptk"

exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Starting MaiaLinux LXQt Session at $(date) ==="

export TERM="linux"
sudo chmod 666 /dev/tty0 /dev/tty1 /dev/dri/card0 /dev/input/event* /dev/uinput 2>/dev/null || true
printf "\033c" > "$CUR_TTY" 2>/dev/null || true

cat > "$CUR_TTY" 2>/dev/null << 'EOF' || true
====================================================
   MaiaLinux Desktop (LXQt) - Anbernic RG353V
====================================================
  * Left Stick  : Mouse Cursor
  * L1 / A      : Left Click
  * R1 / B      : Right Click
    * Terminal    : Open via icon or F10
  * Start       : Enter
====================================================
Initializing swap, controls, and X11 server...
EOF

# 0. Ensure runtime headers, Wayland-EGL shim, Openbox/PCManFM configs, wallpapers, boot splash, and starter binaries are synced
if [[ -x /etc/maialinux-runtime/maialinux-boot-setup.sh ]]; then
    sudo /etc/maialinux-runtime/maialinux-boot-setup.sh 2>/dev/null || true
elif [[ -x /usr/local/bin/maialinux-boot-setup.sh ]]; then
    sudo /usr/local/bin/maialinux-boot-setup.sh 2>/dev/null || true
fi
if [[ -x /usr/local/bin/maialinux-wallpaper.sh ]]; then
    /usr/local/bin/maialinux-wallpaper.sh auto 2>/dev/null || true
elif [[ -x /etc/maialinux-runtime/maialinux-wallpaper.sh ]]; then
    /etc/maialinux-runtime/maialinux-wallpaper.sh auto 2>/dev/null || true
fi
if [[ -d /etc/maialinux-runtime/include ]] && [[ ! -f /usr/include/stdio.h ]]; then
    sudo cp -af /etc/maialinux-runtime/include/. /usr/include/ 2>/dev/null || true
fi
if [[ -f /etc/maialinux-runtime/lib/libwayland-egl.so.1.0.0 ]]; then
    sudo cp -af --remove-destination /etc/maialinux-runtime/lib/libwayland-egl.so* /usr/lib/aarch64-linux-gnu/ 2>/dev/null || true
    sudo ldconfig 2>/dev/null || true
fi
TARGET_USER="ark"
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo 1000)"
TARGET_GID="$(id -g "$TARGET_USER" 2>/dev/null || echo 1000)"

if [[ -f /etc/maialinux-runtime/openbox-lxqt-rc.xml ]]; then
    sudo cp -f /etc/maialinux-runtime/openbox-lxqt-rc.xml /home/ark/.config/openbox/lxqt-rc.xml 2>/dev/null || true
    sudo chown "${TARGET_UID}:${TARGET_GID}" /home/ark/.config/openbox/lxqt-rc.xml 2>/dev/null || true
fi
if [[ -f /etc/maialinux-runtime/pcmanfm-qt-settings.conf ]]; then
    sudo cp -f /etc/maialinux-runtime/pcmanfm-qt-settings.conf /home/ark/.config/pcmanfm-qt/lxqt/settings.conf 2>/dev/null || true
    sudo chown "${TARGET_UID}:${TARGET_GID}" /home/ark/.config/pcmanfm-qt/lxqt/settings.conf 2>/dev/null || true
fi

# Ensure virtual keyboard layout with numeric & programming symbols is in place
if [[ -f /home/ark/.matchbox/keyboard.xml ]]; then
    sudo cp -f /home/ark/.matchbox/keyboard.xml /usr/share/matchbox-keyboard/keyboard.xml 2>/dev/null || true
fi

# Prevent screensaver error when pressing Power button or suspending
sudo sed -i 's/^OnlyShowIn=LXQt;/#OnlyShowIn=LXQt;\nHidden=true/' /etc/xdg/autostart/lxqt-xscreensaver-autostart.desktop 2>/dev/null || true
if [[ ! -f /usr/local/bin/xscreensaver ]]; then
    printf '#!/bin/sh\nexit 0\n' | sudo tee /usr/local/bin/xscreensaver >/dev/null 2>&1 || true
    sudo chmod 755 /usr/local/bin/xscreensaver 2>/dev/null || true
fi
if [[ ! -f /usr/local/bin/xscreensaver-command ]]; then
    printf '#!/bin/sh\nexit 0\n' | sudo tee /usr/local/bin/xscreensaver-command >/dev/null 2>&1 || true
    sudo chmod 755 /usr/local/bin/xscreensaver-command 2>/dev/null || true
fi

if [[ -f /etc/maialinux-runtime/bin/hello-rg353v ]] && [[ ! -f /home/ark/projects/hello-c/hello-rg353v ]]; then
    sudo cp -f /etc/maialinux-runtime/bin/hello-rg353v /home/ark/projects/hello-c/hello-rg353v 2>/dev/null || true
    sudo cp -f /etc/maialinux-runtime/bin/sdl2-demo /home/ark/projects/hello-sdl2/sdl2-demo 2>/dev/null || true
    sudo chown -R "${TARGET_UID}:${TARGET_GID}" /home/ark/projects 2>/dev/null || true
fi

# 1. If invoked from SSH or systemd while EmulationStation is running standalone,
#    pause EmulationStation so it releases DRM master on /dev/dri/card0.
RESTART_ES_AFTER=false
RESTART_OGA_EVENTS_AFTER=false
if [[ "${1:-}" == "--service" ]] || [[ "${1:-}" == "--standalone" ]]; then
    if systemctl is-active --quiet emulationstation 2>/dev/null; then
        echo "Stopping EmulationStation service for standalone desktop session..."
        sudo systemctl stop emulationstation 2>/dev/null || true
        RESTART_ES_AFTER=true
        sleep 1
    fi
fi

# 1b. Stop the global hotkey daemon while in LXQt to avoid Start+Select lockups.
if systemctl is-active --quiet oga_events 2>/dev/null; then
    echo "Stopping oga_events during LXQt session..."
    sudo systemctl stop oga_events 2>/dev/null || true
    RESTART_OGA_EVENTS_AFTER=true
fi

# 2. Enable 2GB swapfile
sudo /usr/local/bin/maialinux-swap.sh enable || true

# 3. Export X11 / Qt5 / GTK3 / Compiler environment variables
export XDG_SESSION_TYPE="x11"
export XDG_CURRENT_DESKTOP="LXQt"
export QT_QPA_PLATFORM="xcb"
export QT_QPA_PLATFORMTHEME="lxqt"
export QT_AUTO_SCREEN_SCALE_FACTOR="0"
export QT_SCALE_FACTOR="1"
export GDK_BACKEND="x11"
export LD_LIBRARY_PATH="/etc/maialinux-runtime/lib:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH:-}"
export C_INCLUDE_PATH="/etc/maialinux-runtime/include:/etc/maialinux-runtime/include/aarch64-linux-gnu:/usr/include/aarch64-linux-gnu:/usr/include"
export CPLUS_INCLUDE_PATH="/etc/maialinux-runtime/include/c++/9:/etc/maialinux-runtime/include/aarch64-linux-gnu/c++/9:/etc/maialinux-runtime/include:/etc/maialinux-runtime/include/aarch64-linux-gnu:/usr/include/aarch64-linux-gnu:/usr/include"
export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
export HOTKEY="l3"

# 4. Launch gptokeyb controller-to-mouse/keyboard mapper in background
GPTOKEYB_SUPERVISOR_PID=""
GPTOKEYB_STOP_FLAG="/tmp/maialinux-gptokeyb.stop"
if [[ -x "$GPTOKEYB_BIN" ]] && [[ -f "$GPTOKEYB_CONF" ]]; then
    sudo pkill -f "gptokeyb.*desktop.gptk" 2>/dev/null || true
    rm -f "$GPTOKEYB_STOP_FLAG" 2>/dev/null || true
    (
        while [[ ! -f "$GPTOKEYB_STOP_FLAG" ]]; do
            sudo SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt" \
                "$GPTOKEYB_BIN" -1 "openbox" -c "$GPTOKEYB_CONF" >/dev/null 2>&1 || true
            [[ -f "$GPTOKEYB_STOP_FLAG" ]] && break
            # Some firmware combos can terminate gptokeyb; restart it quickly.
            sleep 0.4
        done
    ) &
    GPTOKEYB_SUPERVISOR_PID=$!
    echo "Started gptokeyb supervisor (PID: $GPTOKEYB_SUPERVISOR_PID)"
fi

# 5. Start Xorg + LXQt session (do NOT pass -logfile when Xorg runs setuid-root with elevated privileges)
if ! pgrep -x "Xorg" >/dev/null 2>&1; then
    sudo rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true
fi

# Release a remaining splash before handing the display to Xorg.
sudo plymouth quit 2>/dev/null || true
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
startx /usr/bin/startlxqt -- "$X_DISPLAY" "$X_VT" >> "$LOG_FILE" 2>&1
SESSION_STATUS=$?
if [[ "$SESSION_STATUS" -ne 0 ]]; then
    echo "LXQt failed (status $SESSION_STATUS). See $LOG_FILE"
fi
# Keep the Xorg diagnostics across reboot, including a root-owned server log.
for xlog in /var/log/Xorg.1.log "${HOME:-/home/ark}/.local/share/xorg/Xorg.1.log"; do
    if [[ -r "$xlog" ]]; then
        cp "$xlog" "$LOG_DIR/Xorg.1.log" || true
    fi
done

# 6. Cleanup on session exit
echo "Cleaning up MaiaLinux session..."
pkill -f "matchbox-keyboard" 2>/dev/null || true
pkill -x "onboard" 2>/dev/null || true
touch "$GPTOKEYB_STOP_FLAG" 2>/dev/null || true
if [[ -n "$GPTOKEYB_SUPERVISOR_PID" ]]; then
    kill "$GPTOKEYB_SUPERVISOR_PID" 2>/dev/null || true
fi
sudo pkill -f "gptokeyb.*desktop.gptk" 2>/dev/null || true

printf "\033c" > "$CUR_TTY" 2>/dev/null || true
echo "Returning to Gaming Mode..." > "$CUR_TTY" 2>/dev/null || true

if [[ "$RESTART_ES_AFTER" == "true" ]]; then
    sudo systemctl start emulationstation 2>/dev/null || true
fi
if [[ "$RESTART_OGA_EVENTS_AFTER" == "true" ]]; then
    sudo systemctl start oga_events 2>/dev/null || true
fi

exit "$SESSION_STATUS"
