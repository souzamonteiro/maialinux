#!/usr/bin/env bash
# Deploy a kernel Image to BOOT1 with backup and automatic rollback on verification failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DEFAULT_BOOT1="/media/${SUDO_USER:-$USER}/BOOT1"
SOURCE_IMAGE="${1:-}"
BOOT1_MOUNT="${2:-$DEFAULT_BOOT1}"
ASSUME_YES="no"
ROOTFS_MOUNT="/media/${SUDO_USER:-$USER}/root1"
FORCE_DEPLOY="no"

usage() {
    cat <<'EOF'
Usage:
    scripts/host/deploy-boot1-image-safe.sh <new-image-path> [boot1-mount] [options]

Examples:
  scripts/host/deploy-boot1-image-safe.sh distro/Image /media/roberto/BOOT1
  scripts/host/deploy-boot1-image-safe.sh distro/Image --yes
    scripts/host/deploy-boot1-image-safe.sh distro/Image /media/roberto/BOOT1 --rootfs /media/roberto/root1

Notes:
  - Requires BOOT1 mounted and containing the existing Image file.
  - Creates backup at backups/boot-YYYYmmdd-HHMMSS/Image.before
  - On failed verification, restores backup automatically.
    - If <new-image-path>.meta exists, kernel/module compatibility is checked against rootfs.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --yes)
            ASSUME_YES="yes"
            shift
            ;;
        --rootfs)
            ROOTFS_MOUNT="${2:-}"
            shift 2
            ;;
        --force)
            FORCE_DEPLOY="yes"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -z "$SOURCE_IMAGE" || "$SOURCE_IMAGE" == "--yes" ]]; then
    usage >&2
    exit 1
fi

if [[ ! -f "$SOURCE_IMAGE" ]]; then
    echo "Error: source image not found: $SOURCE_IMAGE" >&2
    exit 1
fi

if [[ ! -d "$BOOT1_MOUNT" ]]; then
    echo "Error: BOOT1 mount not found: $BOOT1_MOUNT" >&2
    exit 1
fi

TARGET_IMAGE="$BOOT1_MOUNT/Image"
if [[ ! -f "$TARGET_IMAGE" ]]; then
    echo "Error: target Image not found at $TARGET_IMAGE" >&2
    exit 1
fi

SOURCE_REAL="$(readlink -f "$SOURCE_IMAGE")"
TARGET_REAL="$(readlink -f "$TARGET_IMAGE")"

if [[ ! -w "$TARGET_IMAGE" ]]; then
    echo "Error: target Image is not writable: $TARGET_IMAGE" >&2
    echo "Hint: run with sudo if BOOT1 is root-owned." >&2
    exit 1
fi

BACKUP_DIR="$REPO_ROOT/backups/boot-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
BACKUP_IMAGE="$BACKUP_DIR/Image.before"
cp -f "$TARGET_IMAGE" "$BACKUP_IMAGE"

echo "Source : $SOURCE_IMAGE"
echo "Target : $TARGET_IMAGE"
echo "Backup : $BACKUP_IMAGE"

echo "Current target hash:"
sha256sum "$TARGET_IMAGE"

echo "New image hash:"
sha256sum "$SOURCE_IMAGE"

if [[ "$ASSUME_YES" != "yes" ]]; then
    read -r -p "Type DEPLOY to continue: " CONFIRM
    if [[ "$CONFIRM" != "DEPLOY" ]]; then
        echo "Cancelled."
        exit 1
    fi
fi

META_FILE="${SOURCE_IMAGE}.meta"
if [[ "$FORCE_DEPLOY" != "yes" ]] && [[ -d "$ROOTFS_MOUNT/lib/modules" ]]; then
    expected_release=""

    if [[ -f "$META_FILE" ]]; then
        expected_release="$(grep '^kernel_release=' "$META_FILE" | head -n1 | cut -d '=' -f2-)"
    fi

    if [[ -z "$expected_release" ]]; then
        expected_release="$(strings -a "$SOURCE_IMAGE" 2>/dev/null | grep -m1 '^Linux version ' | awk '{print $3}' || true)"
    fi

    if [[ -n "$expected_release" ]] && [[ ! -d "$ROOTFS_MOUNT/lib/modules/$expected_release" ]]; then
        echo "Error: kernel/module mismatch detected." >&2
        echo "Image expects modules: $expected_release" >&2
        echo "Rootfs has modules: $(ls -1 "$ROOTFS_MOUNT/lib/modules" 2>/dev/null | tr '\n' ' ')" >&2
        echo "Refusing deploy to avoid black screen/boot failure." >&2
        echo "Use --force only if you intentionally deploy an incompatible kernel." >&2
        exit 1
    fi
fi

if [[ "$SOURCE_REAL" == "$TARGET_REAL" ]]; then
    echo "Source and target are the same file. Verification-only mode complete."
    echo "Backup preserved at: $BACKUP_IMAGE"
    exit 0
fi

rollback() {
    echo "Attempting rollback from backup..."
    cp -f "$BACKUP_IMAGE" "$TARGET_IMAGE"
    sync
    if cmp -s "$BACKUP_IMAGE" "$TARGET_IMAGE"; then
        echo "Rollback complete and verified."
    else
        echo "Rollback failed: target does not match backup." >&2
        exit 1
    fi
}

if ! cp -f "$SOURCE_IMAGE" "$TARGET_IMAGE"; then
    echo "Deploy failed while copying new image." >&2
    rollback
    exit 1
fi

sync

if cmp -s "$SOURCE_IMAGE" "$TARGET_IMAGE"; then
    echo "Deploy complete and verified."
    echo "Boot backup preserved at: $BACKUP_IMAGE"
else
    echo "Verification failed after deploy." >&2
    rollback
    exit 1
fi
