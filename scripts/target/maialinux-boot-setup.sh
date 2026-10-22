#!/usr/bin/env bash
# maialinux-boot-setup.sh
# Runs as root at boot (via /boot/firstboot.sh) and during desktop launch to ensure:
# 1. Rockchip U-Boot & Kernel DRM logo partition (/dev/mmcblk1p2 / resource) has MaiaLinux logo.bmp & logo_kernel.bmp
# 2. Plymouth boot screen uses the MaiaLinux graphical theme (4:3 / 16:9 auto)
# 3. Both 640x480 and 1920x1080 wallpapers are available in /usr/share/backgrounds/maialinux and ~/Pictures/Wallpapers
# 4. PCManFM-Qt LXQt settings and EmulationStation themes are synced

set -uo pipefail

RUNTIME_DIR="/etc/maialinux-runtime"

# 1. Flash U-Boot + Kernel DRM resource.img to the Rockchip 'resource' partition (Partition 2) once
if [[ -f "${RUNTIME_DIR}/boot/resource.img" ]] && [[ ! -f "${RUNTIME_DIR}/boot/.resource_flashed_v1" ]]; then
    RES_DEV=""
    if [[ -b /dev/disk/by-partlabel/resource ]]; then
        RES_DEV="/dev/disk/by-partlabel/resource"
    elif [[ -b /dev/mmcblk1p2 ]]; then
        RES_DEV="/dev/mmcblk1p2"
    elif [[ -b /dev/mmcblk0p2 ]]; then
        RES_DEV="/dev/mmcblk0p2"
    fi

    if [[ -n "$RES_DEV" ]]; then
        dd if="${RUNTIME_DIR}/boot/resource.img" of="$RES_DEV" bs=512 conv=fsync 2>/dev/null && \
            touch "${RUNTIME_DIR}/boot/.resource_flashed_v1" 2>/dev/null || true
    fi
fi

# 2. Install Plymouth graphical theme (4:3 640x480 + 16:9 HDMI auto-detect)
if [[ -d "${RUNTIME_DIR}/plymouth/maialinux" ]]; then
    mkdir -p /usr/share/plymouth/themes/maialinux 2>/dev/null || true
    cp -rf "${RUNTIME_DIR}/plymouth/maialinux/." /usr/share/plymouth/themes/maialinux/ 2>/dev/null || true
    ln -sf /usr/share/plymouth/themes/maialinux/maialinux.plymouth /usr/share/plymouth/themes/default.plymouth 2>/dev/null || true
fi
if [[ -f "${RUNTIME_DIR}/plymouth/text.plymouth" ]]; then
    cp -f "${RUNTIME_DIR}/plymouth/text.plymouth" /usr/share/plymouth/themes/text.plymouth 2>/dev/null || true
fi

# 3. Install wallpapers (640x480 and 1920x1080 HDMI) to /usr/share/backgrounds/maialinux and /home/ark/Pictures/Wallpapers
if [[ -d "${RUNTIME_DIR}/wallpapers" ]]; then
    mkdir -p /usr/share/backgrounds/maialinux /home/ark/Pictures/Wallpapers 2>/dev/null || true
    cp -f "${RUNTIME_DIR}/wallpapers/"*.png /usr/share/backgrounds/maialinux/ 2>/dev/null || true
    cp -f "${RUNTIME_DIR}/wallpapers/"*.png /home/ark/Pictures/Wallpapers/ 2>/dev/null || true
    chown -R 1002:1002 /home/ark/Pictures 2>/dev/null || true
fi

# 4. Ensure PCManFM-Qt LXQt wallpaper configuration and Desktop entries are active
if [[ -f "${RUNTIME_DIR}/pcmanfm-qt-settings.conf" ]]; then
    mkdir -p /home/ark/.config/pcmanfm-qt/lxqt 2>/dev/null || true
    cp -f "${RUNTIME_DIR}/pcmanfm-qt-settings.conf" /home/ark/.config/pcmanfm-qt/lxqt/settings.conf 2>/dev/null || true
    chown -R 1002:1002 /home/ark/.config/pcmanfm-qt 2>/dev/null || true
fi
if [[ -d "${RUNTIME_DIR}/desktop-entries" ]]; then
    mkdir -p /home/ark/Desktop /usr/local/share/applications 2>/dev/null || true
    install -m 755 "${RUNTIME_DIR}/desktop-entries/"*.desktop /home/ark/Desktop/ 2>/dev/null || true
    install -m 755 "${RUNTIME_DIR}/desktop-entries/"*.desktop /usr/local/share/applications/ 2>/dev/null || true
    chown -R 1002:1002 /home/ark/Desktop 2>/dev/null || true
fi

# 5. Sync EmulationStation maialinux-4x3 and maialinux-16x9 theme files into es-theme-nes-box
ES_THEME_DIR="/roms/themes/es-theme-nes-box"
if [[ -d "${RUNTIME_DIR}/emulationstation" ]] && [[ -d "$ES_THEME_DIR" ]]; then
    cp -rf "${RUNTIME_DIR}/emulationstation/." "$ES_THEME_DIR/" 2>/dev/null || true
    chown -R 1002:1002 "$ES_THEME_DIR" 2>/dev/null || true
fi
