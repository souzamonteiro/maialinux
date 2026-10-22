#!/usr/bin/env bash
# build-image.sh
# Builds a reproducible, ready-to-flash MaiaLinux .img (and optional .img.xz)
# starting from a stock ArkOS RG353V .img file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 2 ]]; then
    echo "Usage: sudo $0 <source_arkos.img> <output_maialinux.img> [--xz]"
    echo "Example: sudo $0 /home/roberto/projects/Anbernic/RG353V/ArkOS_RG353V_v2.0_02092025.img ./MaiaLinux_RG353V_v1.0.img --xz"
    exit 1
fi

SRC_IMG="$1"
OUT_IMG="$2"
COMPRESS_XZ="${3:-}"

if [[ $EUID -ne 0 ]]; then
    echo "Error: build-image.sh must be run with sudo." >&2
    exit 1
fi

if [[ ! -f "$SRC_IMG" ]]; then
    echo "Error: Source image '$SRC_IMG' does not exist." >&2
    exit 1
fi

echo "==> Copying base image '$SRC_IMG' -> '$OUT_IMG'..."
cp --reflink=auto -f "$SRC_IMG" "$OUT_IMG"

# Check free space on partition 4; expand image by +2.5GB if root partition is tight
echo "==> Expanding image by 3GB to accommodate LXQt, dev tools, and swapfile..."
truncate -s +3G "$OUT_IMG"

LOOP_DEV=""
MNT_ROOT="$(mktemp -d /tmp/maialinux-img-root.XXXXXX)"

cleanup() {
    set +e
    sync
    umount -lf "$MNT_ROOT" 2>/dev/null || true
    rmdir "$MNT_ROOT" 2>/dev/null || true
    if [[ -n "$LOOP_DEV" ]]; then
        losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
}
trap cleanup EXIT

LOOP_DEV="$(losetup -Pf --show "$OUT_IMG")"
echo "==> Attached loop device: $LOOP_DEV"

# Resize partition 4 (root) to use the newly added space
parted -s "$LOOP_DEV" resizepart 4 100% || true
partprobe "$LOOP_DEV" || true
e2fsck -fy "${LOOP_DEV}p4" || true
resize2fs "${LOOP_DEV}p4"

mount "${LOOP_DEV}p4" "$MNT_ROOT"
echo "==> Mounted ${LOOP_DEV}p4 at $MNT_ROOT"

# Install MaiaLinux into the mounted image
"$SCRIPT_DIR/install-to-sdcard.sh" "$MNT_ROOT"

# Unmount and detach before optional compression
umount "$MNT_ROOT"
losetup -d "$LOOP_DEV"
LOOP_DEV=""

if [[ "$COMPRESS_XZ" == "--xz" ]]; then
    echo "==> Compressing '$OUT_IMG' to '${OUT_IMG}.xz'..."
    xz -9 -T0 -k -v "$OUT_IMG"
    echo "==> Created '${OUT_IMG}.xz'"
fi

echo "==> Image build complete: $OUT_IMG"
