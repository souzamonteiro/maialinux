#!/usr/bin/env bash
# Safe resource partition flasher for ArkOS/maialinux SD cards.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOURCE_DEV="${1:-/dev/sdb2}"
MODE="${2:-custom}" # custom | original

usage() {
  cat <<'EOF'
Usage:
  scripts/host/flash-resource-safe.sh [/dev/sdX2] [custom|original]

Examples:
  scripts/host/flash-resource-safe.sh /dev/sdb2 custom
  scripts/host/flash-resource-safe.sh /dev/sdb2 original
EOF
}

if [[ "$RESOURCE_DEV" == "-h" || "$RESOURCE_DEV" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$MODE" != "custom" && "$MODE" != "original" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -b "$RESOURCE_DEV" ]]; then
  echo "Error: block device not found: $RESOURCE_DEV" >&2
  exit 1
fi

PARTNO="$(cat "/sys/class/block/$(basename "$RESOURCE_DEV")/partition" 2>/dev/null || true)"
SIZE="$(blockdev --getsize64 "$RESOURCE_DEV")"
if [[ "$PARTNO" != "2" || "$SIZE" != "4194304" ]]; then
  echo "Refusing: expected 4 MiB partition #2 (resource)." >&2
  exit 1
fi

CUSTOM_IMG="$REPO_ROOT/config/boot/resource.img"
ORIG_IMG="$REPO_ROOT/config/boot/resource.img.orig"
SRC_IMG="$CUSTOM_IMG"
if [[ "$MODE" == "original" ]]; then
  SRC_IMG="$ORIG_IMG"
fi

if [[ ! -f "$SRC_IMG" ]]; then
  echo "Error: source image missing: $SRC_IMG" >&2
  exit 1
fi

if [[ "$(head -c 4 "$SRC_IMG")" != "RSCE" ]]; then
  echo "Error: source image is not a valid RSCE resource image: $SRC_IMG" >&2
  exit 1
fi

BACKUP_DIR="$REPO_ROOT/backups/boot-$(date +%Y%m%d-%H%M%S)-resource-${MODE}"
mkdir -p "$BACKUP_DIR"

sudo dd if="$RESOURCE_DEV" of="$BACKUP_DIR/resource-before.img" bs=1M status=none
truncate -s "$SIZE" "$BACKUP_DIR/resource-target-padded.img"
dd if="$SRC_IMG" of="$BACKUP_DIR/resource-target-padded.img" conv=notrunc status=none

sudo dd if="$BACKUP_DIR/resource-target-padded.img" of="$RESOURCE_DEV" bs=1M conv=fsync status=progress
sudo cmp "$RESOURCE_DEV" "$BACKUP_DIR/resource-target-padded.img"

echo "Resource flash OK ($MODE)."
echo "Backup dir: $BACKUP_DIR"
