#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  scripts/host/flash-darkos-rg353v-sdcard.sh [archive_001] [device]

Examples:
  scripts/host/flash-darkos-rg353v-sdcard.sh \
    /home/roberto/projects/Anbernic/RG353V/dArkOS/dArkOS_RG353v_trixie_08282026.img.7z.001 \
    /dev/sdb

  scripts/host/flash-darkos-rg353v-sdcard.sh --yes

Options:
  --archive <path>   Path to the split archive part .7z.001
  --device <path>    SD card device, e.g. /dev/sdb
  --yes             Skip the confirmation prompt
  -h, --help        Show this help

Notes:
  - The script auto-detects the split archive and extracts the .img if needed.
  - It will unmount any mounted partitions on the target device before writing.
  - This is a destructive operation.
EOF
}

ARCHIVE_PATH=""
DEVICE=""
ASSUME_YES="no"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)
      ARCHIVE_PATH="${2:-}"
      shift 2
      ;;
    --device)
      DEVICE="${2:-}"
      shift 2
      ;;
    --yes)
      ASSUME_YES="yes"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$ARCHIVE_PATH" ]]; then
        ARCHIVE_PATH="$1"
      elif [[ -z "$DEVICE" ]]; then
        DEVICE="$1"
      else
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$DEVICE" ]]; then
  for candidate in /dev/sdb /dev/sdc /dev/mmcblk0 /dev/mmcblk1; do
    if [[ -b "$candidate" ]]; then
      DEVICE="$candidate"
      break
    fi
  done
fi

if [[ -z "$ARCHIVE_PATH" ]]; then
  for candidate in \
    "$REPO_ROOT/../Anbernic/RG353V/dArkOS"/*.img.7z.001 \
    "$REPO_ROOT/../Anbernic/RG353V/dArkOS"/*.img.7z \
    "$REPO_ROOT/../Anbernic/RG353V/dArkOS"/*; do
    if [[ -f "$candidate" && "$candidate" == *.img.7z.001 ]]; then
      ARCHIVE_PATH="$candidate"
      break
    fi
  done
fi

if [[ -z "$ARCHIVE_PATH" ]]; then
  echo "Error: split archive .img.7z.001 not found." >&2
  echo "Looked in common paths under: $REPO_ROOT/../Anbernic/RG353V/dArkOS" >&2
  exit 1
fi

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "Error: archive not found: $ARCHIVE_PATH" >&2
  exit 1
fi

if [[ -z "$DEVICE" || ! -b "$DEVICE" ]]; then
  echo "Error: target device not found or invalid: ${DEVICE:-<unset>}" >&2
  exit 1
fi

if [[ "$DEVICE" =~ ^/dev/(loop|nvme|mmcblk.*p|sd[a-z]+[0-9]+)$ ]] || [[ "$DEVICE" == /dev/root ]]; then
  echo "Refusing to write to a mounted or non-removable device: $DEVICE" >&2
  exit 1
fi

ARCHIVE_DIR="$(cd "$(dirname "$ARCHIVE_PATH")" && pwd)"
BASE_NAME="$(basename "$ARCHIVE_PATH")"
IMG_NAME="${BASE_NAME%.7z.001}.img"
IMG_PATH="$ARCHIVE_DIR/$IMG_NAME"

if [[ ! -f "$IMG_PATH" ]]; then
  echo "==> Extracting archive: $ARCHIVE_PATH"
  7z x -y -o"$ARCHIVE_DIR" "$ARCHIVE_PATH"
fi

if [[ ! -f "$IMG_PATH" ]]; then
  echo "Error: extracted image not found at $IMG_PATH" >&2
  exit 1
fi

SIZE_BYTES="$(stat -c '%s' "$IMG_PATH")"
printf 'Archive: %s\n' "$ARCHIVE_PATH"
printf 'Image  : %s\n' "$IMG_PATH"
printf 'Target : %s\n' "$DEVICE"
printf 'Size   : %s bytes (%s GiB)\n' "$SIZE_BYTES" "$(awk -v b="$SIZE_BYTES" 'BEGIN { printf "%.2f", b/1024/1024/1024 }')"

if [[ "$ASSUME_YES" != "yes" ]]; then
  read -r -p "This will overwrite $DEVICE. Type WRITE-TO-SDCARD to continue: " CONFIRM
  if [[ "$CONFIRM" != "WRITE-TO-SDCARD" ]]; then
    echo "Cancelled."
    exit 1
  fi
fi

for mp in $(lsblk -nr -o MOUNTPOINT "$DEVICE" 2>/dev/null | awk 'NF'); do
  if [[ "$mp" != "" ]]; then
    echo "==> Unmounting $mp"
    sudo umount -l "$mp" || true
  fi
done

sudo dd if="$IMG_PATH" of="$DEVICE" bs=4M status=progress conv=fsync
sync

printf '\n==> Flash complete.\n'
printf 'Device: %s\n' "$DEVICE"
printf 'Image : %s\n' "$IMG_PATH"
printf 'You can now reinsert the SD card and boot it in the RG353V.\n'
