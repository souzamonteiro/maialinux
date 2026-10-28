#!/usr/bin/env bash
# Safely transplant partition 3 (BOOT FAT) from a dArkOS image into the mounted SD BOOT partition.
# This is for black-screen differential diagnosis while preserving ROOTFS customizations.

set -euo pipefail

IMG_PATH="${1:-/home/roberto/projects/Anbernic/RG353V/dArkOS/dArkOS_RG353v_trixie_08282026.img}"
BOOT_MNT="${2:-/media/roberto/BOOT1}"
BOOT_DEV="${3:-}"

if [[ $EUID -ne 0 ]]; then
  echo "Error: run as root (sudo)." >&2
  echo "Usage: sudo $0 [darkos_image] [boot_mountpoint] [boot_device]" >&2
  exit 1
fi

if [[ ! -f "$IMG_PATH" ]]; then
  echo "Error: image not found: $IMG_PATH" >&2
  exit 1
fi

mkdir -p "$BOOT_MNT"

if [[ ! -d "$BOOT_MNT" ]]; then
  echo "Error: BOOT mountpoint could not be created: $BOOT_MNT" >&2
  exit 1
fi

HOST_ROOT_DEV="$(findmnt -n -o SOURCE / 2>/dev/null || true)"

if [[ -n "$BOOT_DEV" ]]; then
  :
else
  mapfile -t CANDIDATES < <(lsblk -dnr -o NAME,TYPE,FSTYPE,MOUNTPOINTS /dev/sd* /dev/mmcblk* 2>/dev/null | awk '$2 == "part" && $3 == "vfat" && $4 == "" {print "/dev/" $1}')

  if [[ ${#CANDIDATES[@]} -gt 0 ]]; then
    for cand in "${CANDIDATES[@]}"; do
      if [[ "$cand" =~ ^/dev/sd[b-z][0-9]+$ || "$cand" =~ ^/dev/mmcblk[0-9]+p[0-9]+$ ]]; then
        BOOT_DEV="$cand"
        break
      fi
    done
  fi
fi

if [[ -z "$BOOT_DEV" ]]; then
  echo "Error: could not resolve BOOT block device from SD card scan." >&2
  echo "Pass the SD BOOT partition explicitly as the 3rd argument, for example:" >&2
  echo "  sudo $0 $IMG_PATH $BOOT_MNT /dev/sdb3" >&2
  exit 1
fi

if [[ "$BOOT_DEV" == "$HOST_ROOT_DEV" ]]; then
  echo "Error: refusing to write to host root device: $BOOT_DEV" >&2
  echo "Selected a disk that is not the removable BOOT partition. Use the SD BOOT partition explicitly:" >&2
  echo "  sudo $0 $IMG_PATH $BOOT_MNT /dev/sdb3" >&2
  exit 1
fi

if [[ ! "$BOOT_DEV" =~ ^/dev/(sd[b-z][0-9]+|mmcblk[0-9]+p[0-9]+)$ ]]; then
  echo "Error: unexpected BOOT device: $BOOT_DEV" >&2
  echo "Expected removable SD partition like /dev/sdb3 or /dev/mmcblk1p3." >&2
  exit 1
fi

# Match partition 3 line even when sfdisk prints an absolute image path.
PART3_LINE="$(sfdisk -d "$IMG_PATH" | awk -F':' '$1 ~ /\.img3[[:space:]]*$/ {print $0; exit}')"
if [[ -z "$PART3_LINE" ]]; then
  echo "Error: could not find partition 3 layout in image: $IMG_PATH" >&2
  exit 1
fi

START_SECTOR="$(echo "$PART3_LINE" | sed -n 's/.*start= *\([0-9]\+\).*/\1/p')"
SIZE_SECTORS="$(echo "$PART3_LINE" | sed -n 's/.*size= *\([0-9]\+\).*/\1/p')"

if [[ -z "$START_SECTOR" || -z "$SIZE_SECTORS" ]]; then
  echo "Error: could not parse partition 3 start/size from image layout." >&2
  echo "$PART3_LINE" >&2
  exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/home/roberto/projects/maialinux/backups/boot-partition-test-$TS"
mkdir -p "$BACKUP_DIR"

echo "============================================================"
echo " BOOT Transplant Test"
echo " Image       : $IMG_PATH"
echo " BOOT mount  : $BOOT_MNT"
echo " BOOT device : $BOOT_DEV"
echo " P3 start    : $START_SECTOR"
echo " P3 size     : $SIZE_SECTORS sectors"
echo " Backup dir  : $BACKUP_DIR"
echo "============================================================"

echo "[1/5] Backing up current BOOT partition..."
dd if="$BOOT_DEV" of="$BACKUP_DIR/boot-before.img" bs=4M status=progress conv=fsync
cp -f "$BOOT_MNT/extlinux/extlinux.conf" "$BACKUP_DIR/extlinux.before.conf" 2>/dev/null || true

echo "[2/5] Extracting BOOT partition from source image..."
dd if="$IMG_PATH" of="$BACKUP_DIR/boot-from-darkos.img" bs=512 skip="$START_SECTOR" count="$SIZE_SECTORS" status=progress

echo "[3/5] Unmounting BOOT mountpoint if needed..."
if findmnt -n "$BOOT_MNT" >/dev/null 2>&1; then
  umount "$BOOT_MNT"
fi

echo "[4/5] Writing source BOOT onto SD BOOT partition..."
dd if="$BACKUP_DIR/boot-from-darkos.img" of="$BOOT_DEV" bs=4M status=progress conv=fsync
sync

echo "[5/5] Remounting BOOT and showing resulting extlinux.conf..."
mkdir -p "$BOOT_MNT"
mount -o rw "$BOOT_DEV" "$BOOT_MNT"
ls -la "$BOOT_MNT" | sed -n '1,120p'
echo "--- extlinux.conf (after transplant) ---"
sed -n '1,120p' "$BOOT_MNT/extlinux/extlinux.conf"

echo "DONE: BOOT transplant completed."
echo "If needed, rollback with: dd if=$BACKUP_DIR/boot-before.img of=$BOOT_DEV bs=4M conv=fsync"