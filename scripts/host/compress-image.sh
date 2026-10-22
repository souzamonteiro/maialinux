#!/usr/bin/env bash
# compress-image.sh
# Compresses an SD Card block device or .img file to a distributable .img.xz file.

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: sudo $0 <source_device_or_img> <destination.img.xz>"
    echo "Example: sudo $0 /dev/sdb MaiaLinux_RG353V_v1.0.img.xz"
    exit 1
fi

SOURCE="$1"
DEST="$2"

if [[ $EUID -ne 0 ]]; then
    echo "Error: Run with sudo to read block devices." >&2
    exit 1
fi

if [[ -b "$SOURCE" ]]; then
    SIZE=$(blockdev --getsize64 "$SOURCE")
else
    SIZE=$(stat -c%s "$SOURCE")
fi

echo "Compressing $SOURCE ($(numfmt --to=iec-i --suffix=B "$SIZE")) -> $DEST..."
if command -v pv >/dev/null 2>&1; then
    dd if="$SOURCE" bs=4M 2>/dev/null | pv -s "$SIZE" | xz -6 -T0 > "$DEST"
else
    dd if="$SOURCE" bs=4M status=progress | xz -6 -T0 > "$DEST"
fi

chmod 644 "$DEST"
echo "Done: $DEST ($(du -h "$DEST" | cut -f1))"
