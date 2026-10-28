#!/usr/bin/env bash
# build-release-2.0.0.sh
# Generates the official MaiaLinux 2.0.0 release artifacts:
#   1) distro/MaiaLinux-RG353V-v2.0.0-sdcard.img.xz
#   2) distro/MaiaLinux-RG353V-v2.0.0-sdcard.img.xz.sha256
#   3) distro/MaiaLinux-RG353V-v2.0.0-qemu.qcow2
#   4) distro/MaiaLinux-RG353V-v2.0.0-qemu.qcow2.sha256
#
# Clones directly from the verified, working SD card mounted at /dev/sdb (or specified block device).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DISTRO_DIR="$REPO_ROOT/distro"
mkdir -p "$DISTRO_DIR"

DEVICE="${1:-}"

# 1. Auto-detect SD card device from mounted partitions if not provided
if [[ -z "$DEVICE" ]]; then
    for cand in $(findmnt -n -o SOURCE /media/$USER/ROOTFS /media/$USER/BOOT /media/roberto/ROOTFS /media/roberto/BOOT 2>/dev/null || true); do
        cand_disk="$(lsblk -no PKNAME "$cand" 2>/dev/null || true)"
        if [[ -n "$cand_disk" ]]; then
            DEVICE="/dev/$cand_disk"
            break
        fi
    done
fi
[[ -n "$DEVICE" ]] || DEVICE="/dev/sdb"

if [[ ! -b "$DEVICE" ]]; then
    echo "Error: Target SD card device '$DEVICE' not found." >&2
    exit 1
fi

echo "============================================================"
echo "  MaiaLinux 2.0.0 Release Builder"
echo "  Source Device : $DEVICE"
echo "  Output Dir    : $DISTRO_DIR"
echo "============================================================"

# Ensure all buffers are flushed to disk before reading
echo "==> Syncing disk buffers..."
sync

SDCARD_XZ="$DISTRO_DIR/MaiaLinux-RG353V-v2.0.0-sdcard.img.xz"
QEMU_QCOW2="$DISTRO_DIR/MaiaLinux-RG353V-v2.0.0-qemu.qcow2"

# 2. Find boundary sectors
# Partitions:
# p1 (uboot), p2 (resource), p3 (BOOT), p4 (ROOTFS), p5 (EASYROMS)
# We capture everything up to the end of ROOTFS + 500MB of EASYROMS (total ~11 GB)
# so the image fits onto any standard 16GB, 32GB or 64GB card, and firstboot expands it.
PART4_START="$(lsblk -bno START "${DEVICE}4" 2>/dev/null || lsblk -bno START "${DEVICE}p4" 2>/dev/null || echo 237568)"
PART4_SECTORS="$(lsblk -bno SECTORS "${DEVICE}4" 2>/dev/null || lsblk -bno SECTORS "${DEVICE}p4" 2>/dev/null || echo 20967505)"
PART4_DEV="${DEVICE}4"
[[ -b "$PART4_DEV" ]] || PART4_DEV="${DEVICE}p4"

PART5_START="$(lsblk -bno START "${DEVICE}5" 2>/dev/null || lsblk -bno START "${DEVICE}p5" 2>/dev/null || echo 21207040)"
# Capture 600,000 sectors (~300MB) of partition 5 which holds maialinux launchers & themes
CAPTURED_SECTORS=$(( PART5_START + 614400 ))

echo "==> Capturing $CAPTURED_SECTORS sectors ($(( CAPTURED_SECTORS * 512 / 1024 / 1024 )) MB) from $DEVICE..."

# 3. Build QEMU QCOW2 from Partition 4 (ROOTFS)
echo "==> Generating compressed QEMU rootfs ($QEMU_QCOW2)..."
if [[ -b "$PART4_DEV" ]]; then
    qemu-img convert -p -f raw -O qcow2 -c "$PART4_DEV" "${QEMU_QCOW2}.tmp"
    mv -f "${QEMU_QCOW2}.tmp" "$QEMU_QCOW2"
    (cd "$DISTRO_DIR" && sha256sum "$(basename "$QEMU_QCOW2")" > "$(basename "$QEMU_QCOW2").sha256")
    echo "==> QEMU image created: $QEMU_QCOW2 ($(du -h "$QEMU_QCOW2" | cut -f1))"
fi

# 4. Stream compressed SD Card Image (.img.xz)
echo "==> Streaming SD Card image to $SDCARD_XZ (xz -T0 -1)..."
dd if="$DEVICE" bs=4M count=$(( CAPTURED_SECTORS * 512 / (4 * 1024 * 1024) + 1 )) status=progress | xz -T0 -1 > "${SDCARD_XZ}.tmp"
sync
mv -f "${SDCARD_XZ}.tmp" "$SDCARD_XZ"
(cd "$DISTRO_DIR" && sha256sum "$(basename "$SDCARD_XZ")" > "$(basename "$SDCARD_XZ").sha256")
echo "==> SD Card image created: $SDCARD_XZ ($(du -h "$SDCARD_XZ" | cut -f1))"

echo "============================================================"
echo "  Release Artifacts Generated Successfully!"
echo "============================================================"
ls -lh "$DISTRO_DIR"/MaiaLinux-RG353V-v2.0.0*

