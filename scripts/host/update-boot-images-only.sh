#!/usr/bin/env bash
# Update only boot/splash image assets on a mounted SD card.
# This script intentionally does NOT modify BOOT1/Image (kernel).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOTFS="${1:-}"
BOOTFS="${2:-}"

CURRENT_USER="${USER:-$(id -un 2>/dev/null || echo root)}"
MEDIA_BASE="${MEDIA_BASE:-}"
if [[ -z "$MEDIA_BASE" ]]; then
    for candidate in "/media/$CURRENT_USER" "/run/media/$CURRENT_USER" "/media/${SUDO_USER:-$CURRENT_USER}" "/run/media/${SUDO_USER:-$CURRENT_USER}"; do
        [[ -d "$candidate" ]] && { MEDIA_BASE="$candidate"; break; }
done
    [[ -n "$MEDIA_BASE" ]] || MEDIA_BASE="/media/$CURRENT_USER"
fi

if [[ -z "$ROOTFS" ]]; then
    SD_ROOT_MNT="$(lsblk -nr -o NAME,FSTYPE,MOUNTPOINT | awk '$1 ~ /^(mmcblk|sd)/ && $2 == "ext4" && $3 != "/" && $3 != "" {print $3; exit}')"
    if [[ -n "$SD_ROOT_MNT" ]]; then
        ROOTFS="$SD_ROOT_MNT"
    else
        ROOTFS="$MEDIA_BASE/root1"
    fi
fi

if [[ -z "$BOOTFS" ]]; then
    SD_BOOT_MNT="$(lsblk -nr -o NAME,FSTYPE,MOUNTPOINT | awk '$1 ~ /^(mmcblk|sd)/ && $2 == "vfat" && $3 != "/boot/efi" && $3 != "" {print $3; exit}')"
    if [[ -n "$SD_BOOT_MNT" ]]; then
        BOOTFS="$SD_BOOT_MNT"
    else
        BOOTFS="$MEDIA_BASE/BOOT1"
    fi
fi

if [[ ! -d "$ROOTFS/home/ark" ]]; then
    echo "Error: ArkOS rootfs not found at $ROOTFS" >&2
    exit 1
fi

if [[ ! -d "$BOOTFS" ]]; then
    echo "Error: BOOT partition not found at $BOOTFS" >&2
    exit 1
fi

echo "==> Updating logo-only assets"
echo "    ROOTFS: $ROOTFS"
echo "    BOOTFS: $BOOTFS"

# 1) BOOT partition bitmaps used by boot flow on this stack.
cp -f "$REPO_ROOT/config/boot/logo.bmp" "$BOOTFS/logo.bmp"
cp -f "$REPO_ROOT/config/boot/logo_kernel.bmp" "$BOOTFS/logo_kernel.bmp"

# 2) EmulationStation launch splash.
if [[ -d "$ROOTFS/roms/launchimages" ]]; then
    cp -f "$REPO_ROOT/config/boot/loading.jpg" "$ROOTFS/roms/launchimages/loading.jpg"
fi

# 3) Runtime mirror for maialinux-boot-setup consumption.
mkdir -p "$ROOTFS/etc/maialinux-runtime/boot"
cp -f "$REPO_ROOT/config/boot/logo.bmp" "$ROOTFS/etc/maialinux-runtime/boot/logo.bmp"
cp -f "$REPO_ROOT/config/boot/logo_kernel.bmp" "$ROOTFS/etc/maialinux-runtime/boot/logo_kernel.bmp"
cp -f "$REPO_ROOT/config/boot/loading.jpg" "$ROOTFS/etc/maialinux-runtime/boot/loading.jpg"

# Safety assertion: do not touch kernel image.
if [[ -f "$BOOTFS/Image" ]]; then
    echo "==> Kernel image preserved: $BOOTFS/Image"
fi

sync
echo "==> Logo-only update complete. Kernel version unchanged."
