#!/usr/bin/env bash
# maialinux-boot-setup.sh
# Runs as root at boot (via emulationstation.sh / maialinux-boot-setup.service) and during desktop launch:
# 1. Draws the 640x480 32bpp BGRA MaiaLinux splash image directly to /dev/fb0 during boot
# 2. Flashes Rockchip U-Boot & Kernel DRM resource.img (logo.bmp + logo_kernel.bmp + rk-kernel.dtb) to Partition 2 (/dev/mmcblk1p2)
# 3. Installs Plymouth graphical theme (4:3 / 16:9 auto) + /etc/plymouth/plymouthd.conf + plymouth.ignore-udev
# 4. Syncs /etc/maialinux-runtime/scripts/* into /usr/local/bin/
# 5. Installs both 640x480 and 1920x1080 wallpapers and EmulationStation themes

set -uo pipefail

RUNTIME_DIR="/etc/maialinux-runtime"
ACTION="${1:-sync}"

# 0. Draw 640x480 32bpp BGRA splash directly to /dev/fb0 when called at boot
if [[ "$ACTION" == "--boot-splash" ]] || [[ "$ACTION" == "boot" ]]; then
    if [[ -c /dev/fb0 ]] && [[ -f "${RUNTIME_DIR}/boot/splash_640x480_bgra32.raw" ]]; then
        let fb_w=$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null | cut -d, -f1 || echo 640)
        if [[ "${fb_w:-640}" -le 640 ]]; then
            printf "\033[?25l" > /dev/tty1 2>/dev/null || true
            dd if="${RUNTIME_DIR}/boot/splash_640x480_bgra32.raw" of=/dev/fb0 bs=4K status=none 2>/dev/null || true
        fi
    fi
fi

# 1. Sync target scripts from /etc/maialinux-runtime/scripts to /usr/local/bin
if [[ -d "${RUNTIME_DIR}/scripts" ]]; then
    for s in "${RUNTIME_DIR}/scripts/"*; do
        if [[ -f "$s" ]]; then
            install -m 755 "$s" "/usr/local/bin/$(basename "$s")" 2>/dev/null || true
        fi
    done
fi

# 2. Flash U-Boot + Kernel DRM resource.img to the Rockchip 'resource' partition (Partition 2)
if [[ -f "${RUNTIME_DIR}/boot/resource.img" ]] && [[ ! -f "${RUNTIME_DIR}/boot/.resource_flashed_v2" ]]; then
    FLASHED=0
    for dev in /dev/mmcblk1p2 /dev/mmcblk0p2 /dev/disk/by-partlabel/resource; do
        if [[ -b "$dev" ]]; then
            # Verify existing partition starts with RSCE header before overwriting
            HDR="$(dd if="$dev" bs=4 count=1 status=none 2>/dev/null || true)"
            if [[ "$HDR" == "RSCE" ]]; then
                dd if="${RUNTIME_DIR}/boot/resource.img" of="$dev" bs=512 conv=fsync status=none 2>/dev/null && FLASHED=1 || true
            fi
        fi
    done
    if [[ -d /boot/extlinux ]]; then
        cp -f "${RUNTIME_DIR}/boot/logo.bmp" /boot/logo.bmp 2>/dev/null || true
        cp -f "${RUNTIME_DIR}/boot/logo_kernel.bmp" /boot/logo_kernel.bmp 2>/dev/null || true
        if ! grep -q "plymouth.ignore-udev" /boot/extlinux/extlinux.conf 2>/dev/null; then
            sed -i 's/splash/splash plymouth.ignore-udev/g' /boot/extlinux/extlinux.conf 2>/dev/null || true
        fi
    fi
    if [[ "$FLASHED" -eq 1 ]]; then
        touch "${RUNTIME_DIR}/boot/.resource_flashed_v2" 2>/dev/null || true
    fi
fi

# 3. Install Plymouth graphical theme (4:3 640x480 + 16:9 HDMI auto-detect) and plymouthd.conf
if [[ -d "${RUNTIME_DIR}/plymouth/maialinux" ]]; then
    mkdir -p /usr/share/plymouth/themes/maialinux /etc/plymouth 2>/dev/null || true
    cp -rf "${RUNTIME_DIR}/plymouth/maialinux/." /usr/share/plymouth/themes/maialinux/ 2>/dev/null || true
    ln -sf /usr/share/plymouth/themes/maialinux/maialinux.plymouth /usr/share/plymouth/themes/default.plymouth 2>/dev/null || true
    ln -sf /usr/share/plymouth/themes/maialinux/maialinux.plymouth /etc/alternatives/default.plymouth 2>/dev/null || true
    cat > /etc/plymouth/plymouthd.conf 2>/dev/null << 'EOF' || true
[Daemon]
Theme=maialinux
ShowDelay=0
DeviceTimeout=5
EOF
    cat > /usr/share/plymouth/plymouthd.defaults 2>/dev/null << 'EOF' || true
[Daemon]
Theme=maialinux
ShowDelay=0
DeviceTimeout=5
EOF
fi
if [[ -f "${RUNTIME_DIR}/plymouth/text.plymouth" ]]; then
    cp -f "${RUNTIME_DIR}/plymouth/text.plymouth" /usr/share/plymouth/themes/text.plymouth 2>/dev/null || true
    cp -f "${RUNTIME_DIR}/plymouth/text.plymouth" /usr/share/plymouth/themes/ubuntu-text/ubuntu-text.plymouth 2>/dev/null || true
fi

# 4. Install early systemd boot splash service so /dev/fb0 displays MaiaLinux splash at early boot
if [[ ! -f /etc/systemd/system/maialinux-boot-splash.service ]]; then
    cat > /etc/systemd/system/maialinux-boot-splash.service 2>/dev/null << 'EOF' || true
[Unit]
Description=MaiaLinux Framebuffer & Boot Splash Setup
DefaultDependencies=no
After=systemd-udevd.service
Before=plymouth-start.service emulationstation.service

[Service]
Type=oneshot
User=root
ExecStart=/etc/maialinux-runtime/maialinux-boot-setup.sh --boot-splash
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target multi-user.target
EOF
    ln -sf /etc/systemd/system/maialinux-boot-splash.service /etc/systemd/system/sysinit.target.wants/maialinux-boot-splash.service 2>/dev/null || true
    ln -sf /etc/systemd/system/maialinux-boot-splash.service /etc/systemd/system/multi-user.target.wants/maialinux-boot-splash.service 2>/dev/null || true
fi

# 5. Install wallpapers (640x480 and 1920x1080 HDMI) to /usr/share/backgrounds/maialinux and /home/ark/Pictures/Wallpapers
if [[ -d "${RUNTIME_DIR}/wallpapers" ]]; then
    mkdir -p /usr/share/backgrounds/maialinux /home/ark/Pictures/Wallpapers 2>/dev/null || true
    cp -f "${RUNTIME_DIR}/wallpapers/"*.png /usr/share/backgrounds/maialinux/ 2>/dev/null || true
    cp -f "${RUNTIME_DIR}/wallpapers/"*.png /home/ark/Pictures/Wallpapers/ 2>/dev/null || true
    chown -R 1002:1002 /home/ark/Pictures 2>/dev/null || true
fi

# 6. Ensure PCManFM-Qt LXQt wallpaper configuration and Desktop entries are active
if [[ -f "${RUNTIME_DIR}/pcmanfm-qt-settings.conf" ]] && [[ ! -f /home/ark/.config/pcmanfm-qt/lxqt/.maialinux_wp_init ]]; then
    mkdir -p /home/ark/.config/pcmanfm-qt/lxqt 2>/dev/null || true
    cp -f "${RUNTIME_DIR}/pcmanfm-qt-settings.conf" /home/ark/.config/pcmanfm-qt/lxqt/settings.conf 2>/dev/null || true
    touch /home/ark/.config/pcmanfm-qt/lxqt/.maialinux_wp_init 2>/dev/null || true
    chown -R 1002:1002 /home/ark/.config/pcmanfm-qt 2>/dev/null || true
fi
if [[ -d "${RUNTIME_DIR}/desktop-entries" ]]; then
    mkdir -p /home/ark/Desktop /usr/local/share/applications 2>/dev/null || true
    install -m 755 "${RUNTIME_DIR}/desktop-entries/"*.desktop /home/ark/Desktop/ 2>/dev/null || true
    install -m 755 "${RUNTIME_DIR}/desktop-entries/"*.desktop /usr/local/share/applications/ 2>/dev/null || true
    chown -R 1002:1002 /home/ark/Desktop 2>/dev/null || true
fi

# 7. Sync EmulationStation maialinux-4x3 and maialinux-16x9 theme files into es-theme-nes-box
ES_THEME_DIR="/roms/themes/es-theme-nes-box"
if [[ -d "${RUNTIME_DIR}/emulationstation" ]] && [[ -d "$ES_THEME_DIR" ]]; then
    cp -rf "${RUNTIME_DIR}/emulationstation/." "$ES_THEME_DIR/" 2>/dev/null || true
    chown -R 1002:1002 "$ES_THEME_DIR" 2>/dev/null || true
fi
