#!/usr/bin/env bash
# restore-boot-partition2.sh
# Safely restores Partition 2 (resource partition) on /dev/sdb2
# from the authentic, working dArkOS image partition.

set -euo pipefail

DEV="${1:-/dev/sdb2}"
SRC="/home/roberto/projects/maialinux/config/boot/resource_darkos_original.img"

if [[ ! -f "$SRC" ]]; then
    echo "ERROR: Source $SRC not found!" >&2
    exit 1
fi

if [[ ! -b "$DEV" ]]; then
    echo "ERROR: Device $DEV not found!" >&2
    exit 1
fi

echo "Restoring authentic partition 2 to $DEV..."
sudo dd if="$SRC" of="$DEV" bs=1M conv=fsync status=progress
sync
echo "Partition 2 successfully restored to original working state!"

