#!/usr/bin/env bash
# maialinux-wallpaper.sh
# Switches or auto-selects the MaiaLinux wallpaper between 640x480 (4:3 DSI panel)
# and 1920x1080 (16:9 HDMI output) across LXQt and EmulationStation.

set -uo pipefail

WALLPAPER_DIR="/etc/maialinux-runtime/wallpapers"
WP_4X3="${WALLPAPER_DIR}/MaiaLinux_at_Neon_Twilight_640x480.png"
WP_16X9="${WALLPAPER_DIR}/MaiaLinux_at_Neon_Twilight_1920x1080.png"
ACTIVE_WP="/etc/maialinux-runtime/wallpaper.png"
STATE_FILE="/etc/maialinux-runtime/wallpaper-mode"

MODE="${1:-toggle}"

detect_hdmi() {
    if [[ -f /sys/class/drm/card0-HDMI-A-1/status ]] && grep -qi "^connected" /sys/class/drm/card0-HDMI-A-1/status 2>/dev/null; then
        return 0
    fi
    if command -v xrandr >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
        if xrandr 2>/dev/null | grep -E "HDMI.* connected" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

if [[ "$MODE" == "toggle" ]]; then
    CUR="4x3"
    [[ -f "$STATE_FILE" ]] && CUR="$(cat "$STATE_FILE" 2>/dev/null || echo "4x3")"
    if [[ "$CUR" == "4x3" ]]; then
        MODE="16x9"
    else
        MODE="4x3"
    fi
elif [[ "$MODE" == "auto" ]]; then
    if detect_hdmi; then
        MODE="16x9"
    else
        MODE="4x3"
    fi
fi

if [[ "$MODE" == "16x9" || "$MODE" == "hdmi" || "$MODE" == "1080p" ]]; then
    TARGET_WP="$WP_16X9"
    ES_COLOR="green"
    MODE_LABEL="16x9 (1920x1080 HDMI)"
    echo "16x9" > "$STATE_FILE" 2>/dev/null || sudo tee "$STATE_FILE" >/dev/null <<< "16x9" || true
else
    TARGET_WP="$WP_4X3"
    ES_COLOR="blue"
    MODE_LABEL="4x3 (640x480 RG353V)"
    echo "4x3" > "$STATE_FILE" 2>/dev/null || sudo tee "$STATE_FILE" >/dev/null <<< "4x3" || true
fi

if [[ -f "$TARGET_WP" ]]; then
    cp -f "$TARGET_WP" "$ACTIVE_WP" 2>/dev/null || sudo cp -f "$TARGET_WP" "$ACTIVE_WP" 2>/dev/null || true
fi

# Update live LXQt desktop if running inside X11
if [[ -n "${DISPLAY:-}" ]] && command -v pcmanfm-qt >/dev/null 2>&1; then
    pcmanfm-qt --set-wallpaper="$ACTIVE_WP" --wallpaper-mode=stretch 2>/dev/null &
fi

# Also update EmulationStation color subset (blue = MaiaLinux 4:3, green = MaiaLinux 16:9 HDMI)
ES_CFG="/home/ark/.emulationstation/es_settings.cfg"
if [[ -f "$ES_CFG" ]]; then
    sudo sed -i "s|<string name=\"subset.Color\" value=\"[^\"]*\" />|<string name=\"subset.Color\" value=\"${ES_COLOR}\" />|g" "$ES_CFG" 2>/dev/null || true
fi

echo "MaiaLinux Wallpaper set to: ${MODE_LABEL}"
