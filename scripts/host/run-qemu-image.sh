#!/usr/bin/env bash
# run-qemu-image.sh
# Launches the MaiaLinux QEMU release artifact (distro/MaiaLinux-RG353V-v1.0.0-qemu.qcow2).
# Supports two modes:
#   --gui  (default if mounted rootfs is available): 640x480 ARM64 LXQt graphical desktop via Xephyr + bwrap + qemu-aarch64-static
#   --vm   (full-system ARM64 VM): Boots the Linux kernel + MaiaLinux QCOW2 disk in qemu-system-aarch64

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/MaiaLinux-RG353V-v1.0.0-qemu.qcow2" ]]; then
    DISTRO_DIR="$SCRIPT_DIR"
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || pwd)"
else
    REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    DISTRO_DIR="$REPO_ROOT/distro"
fi

QCOW2_IMG="${QCOW2_IMG:-$DISTRO_DIR/MaiaLinux-RG353V-v1.0.0-qemu.qcow2}"
KERNEL_IMG="${KERNEL_IMG:-$DISTRO_DIR/Image}"
INITRD_IMG="${INITRD_IMG:-$DISTRO_DIR/uInitrd}"
MODE="${1:---auto}"

if [[ "$MODE" == "--auto" ]]; then
    if [[ -d "/media/roberto/root/usr/bin" ]] && [[ -x "$REPO_ROOT/scripts/host/test-qemu-desktop.sh" ]]; then
        MODE="--gui"
    else
        MODE="--vm"
    fi
fi

if [[ "$MODE" == "--gui" ]]; then
    ROOTFS_PATH="${2:-/media/roberto/root}"
    if [[ ! -d "$ROOTFS_PATH/usr/bin" ]]; then
        echo "Mounting $QCOW2_IMG to /tmp/maialinux-qcow2-mnt for 640x480 GUI simulation..."
        mkdir -p /tmp/maialinux-qcow2-mnt
        if command -v guestmount >/dev/null 2>&1; then
            guestmount -a "$QCOW2_IMG" -m /dev/sda /tmp/maialinux-qcow2-mnt
            trap 'guestunmount /tmp/maialinux-qcow2-mnt 2>/dev/null || true' EXIT
            ROOTFS_PATH="/tmp/maialinux-qcow2-mnt"
        else
            echo "Note: For rootless 640x480 Xephyr GUI from QCOW2 without a mounted SD card, install 'libguestfs-tools' (guestmount) or use '--vm'."
            exit 1
        fi
    fi
    exec "$REPO_ROOT/scripts/host/test-qemu-desktop.sh" "$ROOTFS_PATH" --interactive
elif [[ "$MODE" == "--vm" ]]; then
    if [[ ! -f "$QCOW2_IMG" ]]; then
        echo "Error: QEMU image not found at $QCOW2_IMG" >&2
        exit 1
    fi
    if ! command -v qemu-system-aarch64 >/dev/null 2>&1; then
        echo "Error: qemu-system-aarch64 is not installed. Run: sudo apt install qemu-system-arm" >&2
        exit 1
    fi
    echo "============================================================"
    echo "  Starting MaiaLinux ARM64 Full-System VM (qemu-system-aarch64)"
    echo "  Disk   : $QCOW2_IMG"
    echo "  Kernel : $KERNEL_IMG"
    echo "  Exit   : Press Ctrl+A then X"
    echo "============================================================"
    KERNEL_ARGS=()
    if [[ -f "$KERNEL_IMG" ]]; then
        KERNEL_ARGS+=(-kernel "$KERNEL_IMG" -append "root=/dev/vda rw rootwait console=ttyAMA0,115200 systemd.unit=multi-user.target")
    fi
    if [[ -f "$INITRD_IMG" ]]; then
        KERNEL_ARGS+=(-initrd "$INITRD_IMG")
    fi
    exec qemu-system-aarch64 \
        -M virt \
        -cpu cortex-a55 \
        -smp 4 \
        -m 2048 \
        -drive file="$QCOW2_IMG",format=qcow2,if=virtio \
        -device virtio-gpu-pci,xres=640,yres=480 \
        -device usb-ehci \
        -device usb-kbd \
        -device usb-mouse \
        -nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22 \
        -nographic \
        "${KERNEL_ARGS[@]}"
else
    echo "Usage: $0 [--gui [rootfs_path] | --vm]"
    exit 1
fi
