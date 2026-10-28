#!/usr/bin/env bash
# restore-sdcard-image.sh
# Restores the MaiaLinux SD‑card image (compressed .xz) onto the physical SD card.
# Usage: ./restore-sdcard-image.sh [path/to/MaiaLinux‑RG353V‑v2.0.0‑sdcard.img.xz]
# If no argument is given, the script looks for the latest .xz image under the distro folder.

set -euo pipefail

# Find image file
if [[ $# -ge 1 ]]; then
  IMG_XZ="$1"
else
  IMG_XZ=$(ls -1 /home/roberto/projects/maialinux/distro/*.img.xz | sort -V | tail -n1)
fi

if [[ ! -f "$IMG_XZ" ]]; then
  echo "Error: image file not found: $IMG_XZ"
  exit 1
fi

# Determine the SD‑card block device (first mmcblk or sd with size > 2G)
DEVICE=""
for dev in /dev/mmcblk* /dev/sd*; do
  if [[ -b "$dev" ]]; then
    # Check size (bytes) – ignore partitions like p1, p2
    if [[ "$dev" =~ [0-9]$ ]]; then
      continue
    fi
    SIZE=$(blockdev --getsize64 "$dev" || echo 0)
    if (( SIZE > 2000000000 )); then
      DEVICE="$dev"
      break
    fi
  fi
done

if [[ -z "$DEVICE" ]]; then
  echo "Error: could not auto‑detect SD‑card block device. Provide it manually as second argument."
  exit 1
fi

echo "Detected SD‑card device: $DEVICE"

# Confirm with user
read -p "This will erase all data on $DEVICE. Continue? [y/N] " ans
if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

# Ensure the device is not mounted
if mount | grep -q "^$DEVICE"; then
  echo "Unmounting any mounted partitions on $DEVICE..."
  sudo umount ${DEVICE}* || true
fi

# Decompress and write
echo "Restoring image…"
# Use xz to stream decompress directly to dd
xz -dc "$IMG_XZ" | sudo dd of="$DEVICE" bs=4M status=progress conv=fsync

sync

echo "Restore complete. You can now insert the SD‑card into the device and boot."

