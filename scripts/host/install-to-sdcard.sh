#!/usr/bin/env bash
# install-to-sdcard.sh
# Installs MaiaLinux onto a mounted ArkOS SD Card in the current user's media directory
# using QEMU user-mode emulation (qemu-aarch64-static) at full host PC speed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CURRENT_USER="${USER:-$(id -un 2>/dev/null || echo root)}"
MEDIA_BASE="${MEDIA_BASE:-}"
if [[ -z "$MEDIA_BASE" ]]; then
    for candidate in "/media/$CURRENT_USER" "/run/media/$CURRENT_USER" "/media/${SUDO_USER:-$CURRENT_USER}" "/run/media/${SUDO_USER:-$CURRENT_USER}"; do
        [[ -d "$candidate" ]] && { MEDIA_BASE="$candidate"; break; }
done
    [[ -n "$MEDIA_BASE" ]] || MEDIA_BASE="/media/$CURRENT_USER"
fi
ROOTFS="${1:-$MEDIA_BASE/root}"

if [[ $EUID -ne 0 ]]; then
    echo "Error: Run with sudo: sudo $0 [rootfs_mount_path]" >&2
    exit 1
fi

if [[ ! -d "$ROOTFS/home/ark" ]]; then
    echo "Error: ArkOS root filesystem not found at '$ROOTFS'." >&2
    exit 1
fi

echo "============================================================"
echo "  MaiaLinux Installer for Mounted SD Card"
echo "  Target Rootfs : $ROOTFS"
echo "  Source Repo   : $REPO_ROOT"
echo "============================================================"

# Copy repository into /opt/maialinux and /roms/tools/MaiaLinux inside target rootfs
mkdir -p "$ROOTFS/opt/maialinux" "$ROOTFS/roms/tools/MaiaLinux"
rsync -a --delete --exclude '.git' "$REPO_ROOT/" "$ROOTFS/opt/maialinux/"
rsync -a --delete --exclude '.git' "$REPO_ROOT/" "$ROOTFS/roms/tools/MaiaLinux/"

# Run the installer inside the ARM64 chroot
"$SCRIPT_DIR/chroot-run.sh" "$ROOTFS" /bin/bash /opt/maialinux/install-on-device.sh

sync
echo ""
echo "============================================================"
echo "  MaiaLinux SD Card installation finished and synced!"
echo "============================================================"
