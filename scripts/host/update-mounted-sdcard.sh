#!/usr/bin/env bash
# update-mounted-sdcard.sh
# Quickly updates a mounted Anbernic RG353V MaiaLinux SD card in the current user's media directory
# WITHOUT requiring sudo on the host PC, by writing to user-writable paths (/etc/maialinux-runtime,
# /opt/system/Tools, /roms/tools, /home/ark, and in-place to /usr/bin/emulationstation/emulationstation.sh [mode 0777])
# and hooking maialinux-boot-setup.sh into the boot sequence.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CURRENT_USER="${USER:-$(id -un 2>/dev/null || echo root)}"
MEDIA_BASE="${MEDIA_BASE:-}"
if [[ -z "$MEDIA_BASE" ]]; then
    for candidate in "/media/$CURRENT_USER" "/run/media/$CURRENT_USER" "/media/${SUDO_USER:-$CURRENT_USER}" "/run/media/${SUDO_USER:-$CURRENT_USER}"; do
        [[ -d "$candidate" ]] && { MEDIA_BASE="$candidate"; break; }
done
    [[ -n "$MEDIA_BASE" ]] || MEDIA_BASE="/media/$CURRENT_USER"
fi
ROOTFS="${1:-}"
BOOTFS="${2:-}"

# Auto-detect physical SD card mountpoints (/dev/mmcblk* or /dev/sd*) even if a loop device is mounted
if [[ -z "$ROOTFS" ]]; then
    SD_ROOT_MNT="$(lsblk -nr -o NAME,FSTYPE,MOUNTPOINT | awk '$1 ~ /^(mmcblk|sd)/ && ($2 == "ext4" || $2 == "btrfs") && $3 != "/" && $3 != "" {print $3; exit}')"
    if [[ -n "$SD_ROOT_MNT" ]]; then
        ROOTFS="$SD_ROOT_MNT"
    else
        ROOTFS="$MEDIA_BASE/ROOTFS"
    fi
fi
if [[ -z "$BOOTFS" ]]; then
    SD_BOOT_MNT="$(lsblk -nr -o NAME,FSTYPE,MOUNTPOINT | awk '$1 ~ /^(mmcblk|sd)/ && $2 == "vfat" && $3 != "/boot/efi" && $3 != "" {print $3; exit}')"
    if [[ -n "$SD_BOOT_MNT" ]]; then
        BOOTFS="$SD_BOOT_MNT"
    else
        for candidate in "$MEDIA_BASE/BOOT" "$MEDIA_BASE/boot" "$MEDIA_BASE/BOOT1" "$MEDIA_BASE/boot1" "$MEDIA_BASE/dArkOS_Fat"; do
            if [[ -d "$candidate" ]]; then
                BOOTFS="$candidate"
                break
            fi
        done
        [[ -n "$BOOTFS" ]] || BOOTFS="$MEDIA_BASE/BOOT"
    fi
fi

EASYROMS="${3:-}"
if [[ -z "$EASYROMS" ]]; then
    for candidate in "$MEDIA_BASE/EASYROMS" "$MEDIA_BASE/easyroms"; do
        if [[ -d "$candidate" ]]; then
            EASYROMS="$candidate"
            break
        fi
    done
fi

if [[ "$(df -P "$ROOTFS" 2>/dev/null | awk 'NR==2 {print $1}')" == /dev/loop* ]]; then
    echo "Error: $ROOTFS is currently a QEMU loop mount, not the physical SD card. Please close QEMU and insert the physical SD card." >&2
    exit 1
fi

if [[ ! -d "$ROOTFS/home/ark" ]]; then
    echo "Error: SD card rootfs not found at $ROOTFS (please insert the physical SD card first)." >&2
    exit 1
fi

echo "==> Updating MaiaLinux on mounted SD card ($ROOTFS)..."

RUNTIME_DIR="$ROOTFS/etc/maialinux-runtime"
MAIALINUX_ETC_DIR="$ROOTFS/etc/maialinux"
TARGET_UID="$(grep -E '^ark:' "$ROOTFS/etc/passwd" 2>/dev/null | cut -d: -f3 || echo 1000)"
TARGET_GID="$(grep -E '^ark:' "$ROOTFS/etc/passwd" 2>/dev/null | cut -d: -f4 || echo 1000)"
mkdir -p "$RUNTIME_DIR/scripts" \
         "$RUNTIME_DIR/boot" \
         "$RUNTIME_DIR/plymouth" \
         "$RUNTIME_DIR/wallpapers" \
         "$RUNTIME_DIR/emulationstation" \
         "$RUNTIME_DIR/desktop-entries" \
         "$MAIALINUX_ETC_DIR" 2>/dev/null || true

# 1. Copy target scripts into /etc/maialinux-runtime/scripts and /etc/maialinux-runtime/
cp -f "$REPO_ROOT/scripts/target/"*.sh "$RUNTIME_DIR/scripts/"
cp -f "$REPO_ROOT/scripts/target/maialinux-return-to-es" "$RUNTIME_DIR/scripts/"
cp -f "$REPO_ROOT/config/keyboard/maialinux-keyboard-toggle" "$RUNTIME_DIR/scripts/"
cp -f "$REPO_ROOT/scripts/target/maialinux-boot-setup.sh" "$RUNTIME_DIR/maialinux-boot-setup.sh"
cp -f "$REPO_ROOT/config/systemd/emulationstation.service.d/maialinux.conf" "$RUNTIME_DIR/emulationstation.conf"
cp -f "$REPO_ROOT/scripts/target/maialinux-wallpaper.sh" "$RUNTIME_DIR/maialinux-wallpaper.sh"
cp -f "$REPO_ROOT/config/controls/desktop.gptk" "$MAIALINUX_ETC_DIR/desktop.gptk"
chmod +x "$RUNTIME_DIR/scripts/"* "$RUNTIME_DIR/maialinux-boot-setup.sh" "$RUNTIME_DIR/maialinux-wallpaper.sh" 2>/dev/null || true

# Also copy directly to /usr/local/bin if writable
for s in "$RUNTIME_DIR/scripts/"*; do
    cp -f "$s" "$ROOTFS/usr/local/bin/$(basename "$s")" 2>/dev/null || true
    chmod +x "$ROOTFS/usr/local/bin/$(basename "$s")" 2>/dev/null || true
done

# 2. Update EmulationStation Tools launchers (fixes Xorg -logfile elevated privileges error)
# Note: On ArkOS, /opt/system is mode 0777, while /opt/system/Tools may be 0755 owned by UID 1002.
if [[ -d "$ROOTFS/opt/system/Tools" ]] && [[ ! -w "$ROOTFS/opt/system/Tools" ]] && [[ -w "$ROOTFS/opt/system" ]]; then
    mkdir -p "$ROOTFS/opt/system/Tools.new"
    cp -rf "$ROOTFS/opt/system/Tools/." "$ROOTFS/opt/system/Tools.new/"
    chmod -R 777 "$ROOTFS/opt/system/Tools.new" 2>/dev/null || true
    mv "$ROOTFS/opt/system/Tools" "$ROOTFS/opt/system/.Tools.old.$$"
    mv "$ROOTFS/opt/system/Tools.new" "$ROOTFS/opt/system/Tools"
    rm -rf "$ROOTFS/opt/system/.Tools.old.$$" 2>/dev/null || true
fi

for tools_dir in "$ROOTFS/opt/system/Tools" "$ROOTFS/roms/tools" "${EASYROMS:-}/tools"; do
    if [[ -n "$tools_dir" && -d "$tools_dir" && -w "$tools_dir" ]]; then
        cp -f "$REPO_ROOT/scripts/target/start-maialinux.sh" "$tools_dir/Launch-MaiaLinux-LXQt.sh"
        cp -f "$REPO_ROOT/scripts/target/switch-boot-mode.sh" "$tools_dir/Switch-Boot-Mode.sh"
        cp -f "$REPO_ROOT/scripts/target/maialinux-wallpaper.sh" "$tools_dir/Switch-Wallpaper-4x3-HDMI.sh"
        chmod 755 "$tools_dir" 2>/dev/null || true
        chmod +x "$tools_dir/Launch-MaiaLinux-LXQt.sh" "$tools_dir/Switch-Boot-Mode.sh" "$tools_dir/Switch-Wallpaper-4x3-HDMI.sh" 2>/dev/null || true
        chown -R "${TARGET_UID}:${TARGET_GID}" "$tools_dir" 2>/dev/null || true
    fi
done

# Also place directly in /opt/system so they are immediately visible in the main Options menu
if [[ -d "$ROOTFS/opt/system" && -w "$ROOTFS/opt/system" ]]; then
    cp -f "$REPO_ROOT/scripts/target/start-maialinux.sh" "$ROOTFS/opt/system/Launch MaiaLinux (LXQt).sh"
    cp -f "$REPO_ROOT/scripts/target/switch-boot-mode.sh" "$ROOTFS/opt/system/Switch Boot Mode.sh"
    cp -f "$REPO_ROOT/scripts/target/maialinux-wallpaper.sh" "$ROOTFS/opt/system/Switch Wallpaper.sh"
    chmod +x "$ROOTFS/opt/system/Launch MaiaLinux (LXQt).sh" "$ROOTFS/opt/system/Switch Boot Mode.sh" "$ROOTFS/opt/system/Switch Wallpaper.sh" 2>/dev/null || true
    chown "${TARGET_UID}:${TARGET_GID}" "$ROOTFS/opt/system/Launch MaiaLinux (LXQt).sh" "$ROOTFS/opt/system/Switch Boot Mode.sh" "$ROOTFS/opt/system/Switch Wallpaper.sh" 2>/dev/null || true
fi

# 3. Copy boot splash images (resource.img, BMPs, and 640x480 32bpp BGRA framebuffer raw splash), Plymouth, and Wallpapers
cp -rf "$REPO_ROOT/config/boot/"* "$RUNTIME_DIR/boot/"
cp -rf "$REPO_ROOT/config/plymouth/"* "$RUNTIME_DIR/plymouth/"
cp -rf "$REPO_ROOT/config/wallpapers/"*.png "$RUNTIME_DIR/wallpapers/"
cp -rf "$REPO_ROOT/config/emulationstation/"* "$RUNTIME_DIR/emulationstation/"
cp -rf "$REPO_ROOT/config/desktop-entries/"*.desktop "$RUNTIME_DIR/desktop-entries/"
cp -f "$REPO_ROOT/config/lxqt/pcmanfm-qt-settings.conf" "$RUNTIME_DIR/pcmanfm-qt-settings.conf"
cp -f "$REPO_ROOT/config/lxqt/openbox-lxqt-rc.xml" "$RUNTIME_DIR/openbox-lxqt-rc.xml"
rm -f "$ROOTFS/etc/systemd/logind.conf.d/maialinux-powerkey.conf" "$RUNTIME_DIR/logind-powerkey.conf" 2>/dev/null || true

# Install desktop shortcuts
mkdir -p "$ROOTFS/home/ark/Desktop" 2>/dev/null || true
cp -f "$REPO_ROOT/config/desktop-entries/"*.desktop "$ROOTFS/home/ark/Desktop/" 2>/dev/null || true
chmod +x "$ROOTFS/home/ark/Desktop/"*.desktop 2>/dev/null || true
chown -R "${TARGET_UID}:${TARGET_GID}" "$ROOTFS/home/ark/Desktop" 2>/dev/null || true

if [[ -d "$ROOTFS/roms/themes/es-theme-nes-box" ]]; then
    cp -rf "$REPO_ROOT/config/emulationstation/." "$ROOTFS/roms/themes/es-theme-nes-box/" 2>/dev/null || true
fi
if [[ -d "$ROOTFS/roms/launchimages" ]]; then
    cp -f "$REPO_ROOT/config/boot/loading.jpg" "$ROOTFS/roms/launchimages/loading.jpg" 2>/dev/null || true
fi

# 4. Hook maialinux-boot-setup.sh into /usr/bin/emulationstation/emulationstation.sh in-place (mode 0777, runs on every boot!)
python3 - "$ROOTFS" << 'PYEOF'
import os, sys

rootfs = sys.argv[1]
hook = (
    "\n# MaiaLinux Boot & Splash Setup Hook\n"
    "if [ -x /etc/maialinux-runtime/maialinux-boot-setup.sh ]; then\n"
    "  sudo /etc/maialinux-runtime/maialinux-boot-setup.sh --boot-splash >/dev/null 2>&1 || true\n"
    "fi\n"
)

for name in ("emulationstation.sh", "emulationstation.sh.es"):
    p = os.path.join(rootfs, "usr/bin/emulationstation", name)
    if os.path.isfile(p) and os.access(p, os.W_OK):
        with open(p, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
        if "maialinux-boot-setup.sh" not in content:
            lines = content.splitlines(True)
            if lines and lines[0].startswith("#!"):
                new_content = lines[0] + hook + "".join(lines[1:])
            else:
                new_content = hook + content
            with open(p, "w", encoding="utf-8") as f:
                f.write(new_content)
            print(f"==> Hooked maialinux-boot-setup.sh into {name}")
PYEOF

# 5. Update BOOT FAT32 partition if mounted
if [[ -d "$BOOTFS" ]]; then
    cp -f "$REPO_ROOT/config/boot/logo.bmp" "$BOOTFS/logo.bmp" 2>/dev/null || true
    cp -f "$REPO_ROOT/config/boot/logo_kernel.bmp" "$BOOTFS/logo_kernel.bmp" 2>/dev/null || true
    # Preserve original boot resources; custom resources require explicit installation.
    if [[ -w "$BOOTFS/extlinux/extlinux.conf" ]]; then
        python3 - "$BOOTFS/extlinux/extlinux.conf" << 'PYEOF'
import sys
from pathlib import Path
p = Path(sys.argv[1])
text = p.read_text() if p.exists() else ""
if "LABEL ArkOS" not in text:
    text = "LABEL ArkOS\n  LINUX /Image\n  FDT /rk3566-353v.dtb\n  APPEND root=/dev/mmcblk1p4 initrd=/uInitrd rootwait rw fsck.repair=yes quiet splash vt.global_cursor_default=0 net.ifnames=0 console=tty1 plymouth.ignore-serial-consoles consoleblank=0 loglevel=5 video=HDMI-A-1:1280x720@60\n"
else:
    text = text.replace("FDT /rk3566-OC.dtb", "FDT /rk3566-353v.dtb")
    text = text.replace("FDT /rk3566.dtb", "FDT /rk3566-353v.dtb")
    text = text.replace("root=UUID=", "root=/dev/mmcblk1p4")
    if "video=HDMI-A-1:1280x720@60" not in text:
        text = text.replace("loglevel=0", "loglevel=5 video=HDMI-A-1:1280x720@60")
    if "plymouth.ignore-udev" not in text:
        text = text.replace("splash", "splash plymouth.ignore-udev")
    if "root=/dev/mmcblk1p4" not in text:
        text = text.replace("APPEND ", "APPEND root=/dev/mmcblk1p4 ")
    if "initrd=/uInitrd" not in text:
        text = text.replace("APPEND root=/dev/mmcblk1p4 ", "APPEND root=/dev/mmcblk1p4 initrd=/uInitrd ")
p.write_text(text)
PYEOF
    fi
    echo "==> Updated BOOT partition at $BOOTFS"
fi

sync
echo "==> SD card updated successfully! Safe to eject and boot on the Anbernic RG353V."
