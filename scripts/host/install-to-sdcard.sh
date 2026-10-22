#!/usr/bin/env bash
# install-to-sdcard.sh
# Installs MaiaLinux onto a mounted ArkOS SD Card (default: /media/roberto/root)
# using QEMU user-mode emulation (qemu-aarch64-static) at full host PC speed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROOTFS="${1:-/media/roberto/root}"

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

# Copy repository into /opt/maialinux inside target rootfs for reproducibility
mkdir -p "$ROOTFS/opt/maialinux"
rsync -a --delete --exclude '.git' "$REPO_ROOT/" "$ROOTFS/opt/maialinux/"

# Run the installer inside the ARM64 chroot
"$SCRIPT_DIR/chroot-run.sh" "$ROOTFS" /bin/bash /opt/maialinux/install-on-device.sh

sync
echo ""
echo "============================================================"
echo "  MaiaLinux SD Card installation finished and synced!"
echo "============================================================"
