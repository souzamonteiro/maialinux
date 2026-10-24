#!/usr/bin/env bash
# Deploy a RG353V kernel bundle (Image + rk3566.dtb + modules archive)
# to mounted BOOT1/rootfs with rollback on failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BUNDLE_DIR="${1:-$REPO_ROOT/distro/kernel-rg353v-4.19.172}"
BOOTFS="${2:-/media/${SUDO_USER:-$USER}/BOOT1}"
ROOTFS="${3:-/media/${SUDO_USER:-$USER}/root1}"
ASSUME_YES="no"
FORCE_DEPLOY="no"

usage() {
  cat <<'EOF'
Usage:
  scripts/host/deploy-rg353v-kernel4-bundle-safe.sh [bundle_dir] [boot1_mount] [rootfs_mount] [options]

Examples:
  scripts/host/deploy-rg353v-kernel4-bundle-safe.sh
  scripts/host/deploy-rg353v-kernel4-bundle-safe.sh distro/kernel-rg353v-4.19.172 /media/$USER/BOOT1 /media/$USER/root1 --yes

Options:
  --yes       Skip interactive confirmation
  --force     Skip compatibility checks
  -h, --help  Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      ASSUME_YES="yes"
      shift
      ;;
    --force)
      FORCE_DEPLOY="yes"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "Error: bundle directory not found: $BUNDLE_DIR" >&2
  exit 1
fi

IMAGE_SRC="$BUNDLE_DIR/Image"
DTB_SRC="$BUNDLE_DIR/rk3566.dtb"
META_FILE="$BUNDLE_DIR/bundle.meta"

if [[ ! -f "$IMAGE_SRC" || ! -f "$DTB_SRC" || ! -f "$META_FILE" ]]; then
  echo "Error: bundle is incomplete. Expected Image, rk3566.dtb, and bundle.meta in $BUNDLE_DIR" >&2
  exit 1
fi

KERNEL_RELEASE="$(grep '^kernel_release=' "$META_FILE" | head -n1 | cut -d '=' -f2-)"
MODULES_ARCHIVE_NAME="$(grep '^modules_archive=' "$META_FILE" | head -n1 | cut -d '=' -f2-)"
MODULES_SRC="$BUNDLE_DIR/$MODULES_ARCHIVE_NAME"

if [[ -z "$KERNEL_RELEASE" || -z "$MODULES_ARCHIVE_NAME" || ! -f "$MODULES_SRC" ]]; then
  echo "Error: invalid bundle metadata or modules archive missing." >&2
  exit 1
fi

if [[ ! -d "$BOOTFS" || ! -d "$ROOTFS" ]]; then
  echo "Error: mount path not found. BOOTFS=$BOOTFS ROOTFS=$ROOTFS" >&2
  exit 1
fi

TARGET_IMAGE="$BOOTFS/Image"
TARGET_DTB="$BOOTFS/rk3566.dtb"
TARGET_MODULES_DIR="$ROOTFS/lib/modules/$KERNEL_RELEASE"

if [[ ! -f "$TARGET_IMAGE" || ! -f "$TARGET_DTB" ]]; then
  echo "Error: expected BOOT1 files not found (Image/rk3566.dtb) at $BOOTFS" >&2
  exit 1
fi

if [[ "$FORCE_DEPLOY" != "yes" ]]; then
  if [[ -d "$ROOTFS/lib/modules" ]]; then
    echo "Rootfs module releases present: $(ls -1 "$ROOTFS/lib/modules" 2>/dev/null | tr '\n' ' ')"
  fi
fi

echo "Bundle   : $BUNDLE_DIR"
echo "BOOTFS   : $BOOTFS"
echo "ROOTFS   : $ROOTFS"
echo "Release  : $KERNEL_RELEASE"

if [[ "$ASSUME_YES" != "yes" ]]; then
  read -r -p "Type DEPLOY to continue: " CONFIRM
  if [[ "$CONFIRM" != "DEPLOY" ]]; then
    echo "Cancelled."
    exit 1
  fi
fi

BACKUP_DIR="$REPO_ROOT/backups/kernel-bundle-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp -f "$TARGET_IMAGE" "$BACKUP_DIR/Image.before"
cp -f "$TARGET_DTB" "$BACKUP_DIR/rk3566.dtb.before"
MODULES_BACKUP_MODE="none"

if [[ -d "$TARGET_MODULES_DIR" ]]; then
  MODULES_BACKUP_MODE="existing"
  mkdir -p "$BACKUP_DIR/modules"
  cp -a "$TARGET_MODULES_DIR" "$BACKUP_DIR/modules/"
fi

DEPLOY_DONE="no"
rollback() {
  if [[ "$DEPLOY_DONE" == "yes" ]]; then
    return
  fi
  echo "Deploy failed, rolling back..."
  cp -f "$BACKUP_DIR/Image.before" "$TARGET_IMAGE"
  cp -f "$BACKUP_DIR/rk3566.dtb.before" "$TARGET_DTB"

  if [[ "$MODULES_BACKUP_MODE" == "existing" ]]; then
    rm -rf "$TARGET_MODULES_DIR"
    cp -a "$BACKUP_DIR/modules/$(basename "$TARGET_MODULES_DIR")" "$TARGET_MODULES_DIR"
  else
    rm -rf "$TARGET_MODULES_DIR"
  fi
  sync
  echo "Rollback complete."
}
trap rollback ERR INT TERM

TMP_EXTRACT_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_EXTRACT_DIR"
}
trap cleanup EXIT

tar -C "$TMP_EXTRACT_DIR" -xf "$MODULES_SRC"
EXTRACTED_MODULES_DIR="$TMP_EXTRACT_DIR/lib/modules/$KERNEL_RELEASE"
if [[ ! -d "$EXTRACTED_MODULES_DIR" ]]; then
  echo "Error: modules archive does not contain lib/modules/$KERNEL_RELEASE" >&2
  exit 1
fi

mkdir -p "$ROOTFS/lib/modules"
rm -rf "$TARGET_MODULES_DIR"
cp -a "$EXTRACTED_MODULES_DIR" "$TARGET_MODULES_DIR"

cp -f "$DTB_SRC" "$TARGET_DTB"
cp -f "$IMAGE_SRC" "$TARGET_IMAGE"
sync

cmp -s "$IMAGE_SRC" "$TARGET_IMAGE"
cmp -s "$DTB_SRC" "$TARGET_DTB"

if [[ ! -d "$TARGET_MODULES_DIR" ]]; then
  echo "Error: modules directory missing after deploy." >&2
  exit 1
fi

DEPLOY_DONE="yes"
trap - ERR INT TERM
echo "Deploy complete and verified."
echo "Backup preserved at: $BACKUP_DIR"