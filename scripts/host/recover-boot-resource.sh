#!/usr/bin/env bash
# Restore only the Rockchip resource partition; preserve rootfs and user files.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOURCE="${1:-}"
if [[ "$EUID" -ne 0 || ! -b "$RESOURCE" ]]; then
    echo "Usage: sudo $0 /dev/<SD-resource-partition>" >&2
    exit 1
fi
PARENT="$(lsblk -ndo PKNAME "$RESOURCE")"
PARTNO="$(cat "/sys/class/block/$(basename "$RESOURCE")/partition")"
SIZE="$(blockdev --getsize64 "$RESOURCE")"
if [[ -z "$PARENT" || "$PARTNO" != 2 || "$SIZE" != 4194304 ]]; then
    echo "Refusing: expected the 4 MiB resource partition (partition 2)." >&2
    exit 1
fi
HEADER="$(dd if="$RESOURCE" bs=4 count=1 status=none)"
if [[ "$HEADER" != RSCE ]]; then
    echo "Refusing: target has no Rockchip resource header." >&2
    exit 1
fi
ORIGINAL="$REPO_ROOT/config/boot/resource.img.orig"
if [[ ! -f "$ORIGINAL" || "$(head -c 4 "$ORIGINAL")" != RSCE ]]; then
    echo "Original resource image missing or invalid." >&2
    exit 1
fi
lsblk -o NAME,SIZE,MODEL,MOUNTPOINTS "/dev/$PARENT"
echo "Only $RESOURCE will be restored; rootfs and games are preserved."
read -r -p "Type the full partition path to confirm: " CONFIRM
[[ "$CONFIRM" == "$RESOURCE" ]] || exit 1
BACKUP_DIR="$REPO_ROOT/backups/boot-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
dd if="$RESOURCE" of="$BACKUP_DIR/resource-before.img" bs=1M status=none
# Pad the original resource to the partition size, clearing the custom entries.
truncate -s "$SIZE" "$BACKUP_DIR/resource-restored.img"
dd if="$ORIGINAL" of="$BACKUP_DIR/resource-restored.img" conv=notrunc status=none
dd if="$BACKUP_DIR/resource-restored.img" of="$RESOURCE" bs=1M conv=fsync status=progress
cmp "$RESOURCE" "$BACKUP_DIR/resource-restored.img"
echo "Resource restored and verified. Backup: $BACKUP_DIR"
echo "Before booting, update the installed boot-setup script to prevent automatic reflashing."
