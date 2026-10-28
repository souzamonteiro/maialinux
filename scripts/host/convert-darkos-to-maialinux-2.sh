#!/usr/bin/env bash
# Convert a mounted dArkOS RG353V SD card into MaiaLinux 2.0.0.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CURRENT_USER="${USER:-$(id -un 2>/dev/null || echo root)}"
MEDIA_BASE="${MEDIA_BASE:-}"

if [[ -z "$MEDIA_BASE" ]]; then
    for candidate in "/media/$CURRENT_USER" "/run/media/$CURRENT_USER" "/media/${SUDO_USER:-$CURRENT_USER}" "/run/media/${SUDO_USER:-$CURRENT_USER}"; do
        [[ -d "$candidate" ]] && { MEDIA_BASE="$candidate"; break; }
    done
    [[ -n "$MEDIA_BASE" ]] || MEDIA_BASE="/media/$CURRENT_USER"
fi

BOOTFS="${1:-}"
if [[ -z "$BOOTFS" ]]; then
    for candidate in "$MEDIA_BASE/dArkOS_Fat" "$MEDIA_BASE/BOOT" "$MEDIA_BASE/BOOT1" "$MEDIA_BASE/boot"; do
        [[ -d "$candidate" ]] && { BOOTFS="$candidate"; break; }
    done
    [[ -n "$BOOTFS" ]] || BOOTFS="$MEDIA_BASE/BOOT"
fi

ROOTFS="${2:-}"
if [[ -z "$ROOTFS" ]]; then
    for candidate in "$MEDIA_BASE/ROOTFS" "$MEDIA_BASE/root" "$MEDIA_BASE/rootfs"; do
        [[ -d "$candidate" ]] && { ROOTFS="$candidate"; break; }
    done
    [[ -n "$ROOTFS" ]] || ROOTFS="$MEDIA_BASE/ROOTFS"
fi

EASYROMS="${4:-}"
if [[ -z "$EASYROMS" ]]; then
    for candidate in "$MEDIA_BASE/EASYROMS" "$MEDIA_BASE/easyroms"; do
        [[ -d "$candidate" ]] && { EASYROMS="$candidate"; break; }
    done
fi

BUNDLE_DIR="${3:-$REPO_ROOT/distro/kernel-rg353v-5.10}"

if [[ ! -d "$BUNDLE_DIR" ]]; then
    if [[ -d "$REPO_ROOT/$BUNDLE_DIR" ]]; then
        BUNDLE_DIR="$REPO_ROOT/$BUNDLE_DIR"
    elif [[ -d "$REPO_ROOT/distro/$BUNDLE_DIR" ]]; then
        BUNDLE_DIR="$REPO_ROOT/distro/$BUNDLE_DIR"
    fi
fi

if [[ $EUID -ne 0 ]]; then
    echo "Error: run with sudo: sudo $0 [boot_mount] [rootfs_mount] [bundle_dir]" >&2
    exit 1
fi

if [[ ! -d "$BOOTFS" ]] || [[ ! -d "$ROOTFS/home/ark" ]]; then
    echo "Error: expected mounted BOOT and ROOTFS. Got BOOTFS=$BOOTFS ROOTFS=$ROOTFS" >&2
    exit 1
fi

echo "============================================================"
echo "  Convert dArkOS SD -> MaiaLinux 2.0.0"
echo "  BOOTFS     : $BOOTFS"
echo "  ROOTFS     : $ROOTFS"
echo "  KERNEL BDL : $BUNDLE_DIR"
echo "============================================================"

# 1) Enforce BOOT volume label
BOOT_DEV=""
if findmnt -n --mountpoint "$BOOTFS" >/dev/null 2>&1; then
    BOOT_DEV="$(findmnt -n -o SOURCE --mountpoint "$BOOTFS" 2>/dev/null || true)"
else
    BOOT_DEV="$(blkid -t LABEL=BOOT -o device 2>/dev/null | head -n1 || true)"
fi

if [[ -z "$BOOT_DEV" ]]; then
    echo "Error: could not determine BOOT partition device. Mount the BOOT FAT partition at $BOOTFS and retry." >&2
    exit 1
fi

ROOT_DEV="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
if [[ -n "$ROOT_DEV" && "$BOOT_DEV" == "$ROOT_DEV" ]]; then
    echo "Error: refusing to use host root device as BOOT partition ($BOOT_DEV)." >&2
    exit 1
fi

if [[ ! "$BOOT_DEV" =~ ^/dev/(sd[b-z][0-9]+|mmcblk[0-9]+p[0-9]+)$ ]]; then
    echo "Error: BOOT device $BOOT_DEV is not an expected removable SD partition (/dev/sdXn or /dev/mmcblknpN)." >&2
    exit 1
fi

EXISTING_BOOT_MNT="$(findmnt -n -o TARGET --source "$BOOT_DEV" 2>/dev/null | head -n1 || true)"
if [[ -n "$EXISTING_BOOT_MNT" && "$EXISTING_BOOT_MNT" != "$BOOTFS" ]]; then
    BOOTFS="$EXISTING_BOOT_MNT"
fi

if ! findmnt -n --mountpoint "$BOOTFS" >/dev/null 2>&1; then
    mkdir -p "$BOOTFS"
    mount -t vfat -o rw,uid=1000,gid=1000,umask=0022 "$BOOT_DEV" "$BOOTFS"
fi

if [[ "$(findmnt -n -o FSTYPE --mountpoint "$BOOTFS" 2>/dev/null || true)" != "vfat" ]]; then
    echo "Error: BOOT mountpoint $BOOTFS is not vfat. Check mounted SD card partitions and retry." >&2
    exit 1
fi

fatlabel "$BOOT_DEV" BOOT || true

# 2) Deploy MaiaLinux kernel bundle
"$SCRIPT_DIR/deploy-rg353v-kernel4-bundle-safe.sh" "$BUNDLE_DIR" "$BOOTFS" "$ROOTFS" --yes

# 3) Update runtime hooks, tools, boot assets
"$SCRIPT_DIR/update-mounted-sdcard.sh" "$ROOTFS" "$BOOTFS" "${EASYROMS:-}"

# 4) Install LXQt/dev stack and MaiaLinux device runtime in chroot
"$SCRIPT_DIR/install-to-sdcard.sh" "$ROOTFS" "$BOOTFS"

# 5) Rebrand all user-visible text from dArkOS/ArkOS to MaiaLinux
"$SCRIPT_DIR/rebrand-sdcard-to-maialinux.sh" "$ROOTFS" "$BOOTFS"

sync
echo "============================================================"
echo "  MaiaLinux 2.0.0 conversion finished successfully"
echo "============================================================"