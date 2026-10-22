#!/usr/bin/env bash
# update-mounted-sdcard.sh
# Quickly updates a mounted Anbernic RG353V ArkOS/MaiaLinux SD card (/media/$USER/root and /media/$USER/BOOT)
# WITHOUT requiring sudo on the host PC, by writing to user-writable paths (/etc/maialinux-runtime,
# /opt/system/Tools, /roms/tools, /home/ark, and /usr/bin/emulationstation/emulationstation.sh [mode 0777])
# and hooking maialinux-boot-setup.sh into the boot sequence.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOTFS="${1:-/media/${USER:-roberto}/root}"
BOOTFS="${2:-/media/${USER:-roberto}/BOOT}"

if [[ ! -d "$ROOTFS/home/ark" ]]; then
    echo "Error: SD card rootfs not found at $ROOTFS (please insert the physical SD card first)." >&2
    exit 1
fi

echo "==> Updating MaiaLinux on mounted SD card ($ROOTFS)..."

RUNTIME_DIR="$ROOTFS/etc/maialinux-runtime"
mkdir -p "$RUNTIME_DIR/scripts" \
         "$RUNTIME_DIR/boot" \
         "$RUNTIME_DIR/plymouth" \
         "$RUNTIME_DIR/wallpapers" \
         "$RUNTIME_DIR/emulationstation" \
         "$RUNTIME_DIR/desktop-entries" 2>/dev/null || true

# 1. Copy target scripts into /etc/maialinux-runtime/scripts and /etc/maialinux-runtime/
cp -f "$REPO_ROOT/scripts/target/"*.sh "$RUNTIME_DIR/scripts/"
cp -f "$REPO_ROOT/scripts/target/maialinux-return-to-es" "$RUNTIME_DIR/scripts/"
cp -f "$REPO_ROOT/config/keyboard/maialinux-keyboard-toggle" "$RUNTIME_DIR/scripts/"
cp -f "$REPO_ROOT/scripts/target/maialinux-boot-setup.sh" "$RUNTIME_DIR/maialinux-boot-setup.sh"
cp -f "$REPO_ROOT/scripts/target/maialinux-wallpaper.sh" "$RUNTIME_DIR/maialinux-wallpaper.sh"
chmod +x "$RUNTIME_DIR/scripts/"* "$RUNTIME_DIR/maialinux-boot-setup.sh" "$RUNTIME_DIR/maialinux-wallpaper.sh" 2>/dev/null || true

# Also copy directly to /usr/local/bin if writable
for s in "$RUNTIME_DIR/scripts/"*; do
    cp -f "$s" "$ROOTFS/usr/local/bin/$(basename "$s")" 2>/dev/null || true
done

# 2. Update EmulationStation Tools launchers (fixes Xorg -logfile elevated privileges error)
for tools_dir in "$ROOTFS/opt/system/Tools" "$ROOTFS/roms/tools"; do
    if [[ -d "$tools_dir" ]]; then
        cp -f "$REPO_ROOT/scripts/target/start-maialinux.sh" "$tools_dir/Launch-MaiaLinux-LXQt.sh"
        cp -f "$REPO_ROOT/scripts/target/switch-boot-mode.sh" "$tools_dir/Switch-Boot-Mode.sh"
        cp -f "$REPO_ROOT/scripts/target/maialinux-wallpaper.sh" "$tools_dir/Switch-Wallpaper-4x3-HDMI.sh"
        chmod +x "$tools_dir/Launch-MaiaLinux-LXQt.sh" "$tools_dir/Switch-Boot-Mode.sh" "$tools_dir/Switch-Wallpaper-4x3-HDMI.sh" 2>/dev/null || true
    fi
done

# 3. Copy boot splash images (resource.img, BMPs, and 640x480 32bpp BGRA framebuffer raw splash), Plymouth, and Wallpapers
cp -rf "$REPO_ROOT/config/boot/"* "$RUNTIME_DIR/boot/"
cp -rf "$REPO_ROOT/config/plymouth/"* "$RUNTIME_DIR/plymouth/"
cp -rf "$REPO_ROOT/config/wallpapers/"*.png "$RUNTIME_DIR/wallpapers/"
cp -rf "$REPO_ROOT/config/emulationstation/"* "$RUNTIME_DIR/emulationstation/"
cp -rf "$REPO_ROOT/config/desktop-entries/"*.desktop "$RUNTIME_DIR/desktop-entries/"
cp -f "$REPO_ROOT/config/lxqt/pcmanfm-qt-settings.conf" "$RUNTIME_DIR/pcmanfm-qt-settings.conf"
cp -f "$REPO_ROOT/config/lxqt/openbox-lxqt-rc.xml" "$RUNTIME_DIR/openbox-lxqt-rc.xml"
rm -f "$RUNTIME_DIR/boot/.resource_flashed_v1" "$RUNTIME_DIR/boot/.resource_flashed_v2" 2>/dev/null || true

if [[ -d "$ROOTFS/roms/themes/es-theme-nes-box" ]]; then
    cp -rf "$REPO_ROOT/config/emulationstation/." "$ROOTFS/roms/themes/es-theme-nes-box/" 2>/dev/null || true
fi
if [[ -d "$ROOTFS/roms/launchimages" ]]; then
    cp -f "$REPO_ROOT/config/boot/loading.jpg" "$ROOTFS/roms/launchimages/loading.jpg" 2>/dev/null || true
fi

# 4. Hook maialinux-boot-setup.sh into /usr/bin/emulationstation/emulationstation.sh (mode 0777, runs on every boot!)
for es_sh in "$ROOTFS/usr/bin/emulationstation/emulationstation.sh" "$ROOTFS/usr/bin/emulationstation/emulationstation.sh.es"; do
    if [[ -w "$es_sh" ]] && ! grep -q "maialinux-boot-setup.sh" "$es_sh"; then
        sed -i '2i # MaiaLinux Boot & Splash Setup Hook\nif [ -x /etc/maialinux-runtime/maialinux-boot-setup.sh ]; then sudo /etc/maialinux-runtime/maialinux-boot-setup.sh --boot-splash >/dev/null 2>&1 || true; fi' "$es_sh"
        echo "==> Hooked maialinux-boot-setup.sh into $(basename "$es_sh")"
    fi
done

# 5. Update BOOT FAT32 partition if mounted
if [[ -d "$BOOTFS" ]]; then
    cp -f "$REPO_ROOT/config/boot/logo.bmp" "$BOOTFS/logo.bmp" 2>/dev/null || true
    cp -f "$REPO_ROOT/config/boot/logo_kernel.bmp" "$BOOTFS/logo_kernel.bmp" 2>/dev/null || true
    cp -f "$REPO_ROOT/config/boot/resource.img" "$BOOTFS/resource.img" 2>/dev/null || true
    if [[ -w "$BOOTFS/extlinux/extlinux.conf" ]] && ! grep -q "plymouth.ignore-udev" "$BOOTFS/extlinux/extlinux.conf"; then
        sed -i 's/splash/splash plymouth.ignore-udev/g' "$BOOTFS/extlinux/extlinux.conf"
    fi
    echo "==> Updated BOOT partition at $BOOTFS"
fi

sync
echo "==> SD card updated successfully! Safe to eject and boot on the Anbernic RG353V."
