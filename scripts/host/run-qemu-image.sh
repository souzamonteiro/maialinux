#!/usr/bin/env bash
# run-qemu-image.sh
# Launches the MaiaLinux QEMU release artifact (distro/MaiaLinux-RG353V-v1.0.0-qemu.qcow2).
# Supports two modes:
#   --gui  (default): 640x480 ARM64 LXQt graphical desktop via Xephyr + bwrap + qemu-aarch64-static
#          Automatically mounts the QCOW2 image via udisksctl (rootless, no sudo required!) if no SD card is mounted.
#   --vm   (full-system ARM64 VM): Opens a graphical qemu-system-aarch64 window

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
MODE="${1:---gui}"

if [[ "$MODE" == "--auto" ]]; then
    MODE="--gui"
fi

if [[ "$MODE" == "--gui" ]]; then
    ROOTFS_PATH="${2:-/media/${USER:-roberto}/root}"
    if [[ ! -d "$ROOTFS_PATH/usr/bin" ]]; then
        if [[ ! -f "$QCOW2_IMG" ]]; then
            echo "Error: QEMU image not found at $QCOW2_IMG" >&2
            exit 1
        fi
        RAW_SHM="/dev/shm/maialinux-rootfs.raw"
        if [[ ! -f "$RAW_SHM" ]]; then
            echo "==> Preparing QEMU rootfs in RAM ($RAW_SHM) from $QCOW2_IMG ..."
            qemu-img convert -p -f qcow2 -O raw "$QCOW2_IMG" "$RAW_SHM"
            /sbin/e2label "$RAW_SHM" MAIALINUX_QEMU 2>/dev/null || true
        fi

        # Check if already attached to a loop device
        LOOP_DEV="$(/sbin/losetup -j "$RAW_SHM" 2>/dev/null | head -n1 | cut -d: -f1 || true)"
        if [[ -z "$LOOP_DEV" ]] && command -v udisksctl >/dev/null 2>&1; then
            echo "==> Mapping $RAW_SHM via udisksctl (no sudo required)..."
            MAP_OUT="$(udisksctl loop-setup -r -f "$RAW_SHM" 2>&1)"
            echo "    $MAP_OUT"
            LOOP_DEV="$(echo "$MAP_OUT" | grep -o '/dev/loop[0-9]\+' | head -n1 || true)"
        fi

        if [[ -n "$LOOP_DEV" ]]; then
            # Wait briefly in case desktop environment auto-mounts the loop device
            for _ in 1 2 3 4; do
                MNT_PT="$(lsblk -no MOUNTPOINT "$LOOP_DEV" 2>/dev/null | head -n1 || true)"
                if [[ -n "$MNT_PT" && -d "$MNT_PT/usr/bin" ]]; then
                    ROOTFS_PATH="$MNT_PT"
                    break
                fi
                sleep 0.4
            done
            if [[ ! -d "$ROOTFS_PATH/usr/bin" ]]; then
                udisksctl mount -b "$LOOP_DEV" >/dev/null 2>&1 || true
                MNT_PT="$(lsblk -no MOUNTPOINT "$LOOP_DEV" 2>/dev/null | head -n1 || true)"
                if [[ -n "$MNT_PT" ]]; then
                    ROOTFS_PATH="$MNT_PT"
                fi
            fi
        elif command -v guestmount >/dev/null 2>&1; then
            mkdir -p /tmp/maialinux-qcow2-mnt
            guestmount -r -a "$QCOW2_IMG" -m /dev/sda /tmp/maialinux-qcow2-mnt
            trap 'guestunmount /tmp/maialinux-qcow2-mnt 2>/dev/null || true' EXIT
            ROOTFS_PATH="/tmp/maialinux-qcow2-mnt"
        fi
    fi

    if [[ ! -d "$ROOTFS_PATH/usr/bin" ]]; then
        echo "Error: Could not mount ARM64 rootfs from $QCOW2_IMG" >&2
        exit 1
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
    echo "============================================================"
    KERNEL_ARGS=()
    if [[ -f "$KERNEL_IMG" ]]; then
        KERNEL_ARGS+=(-kernel "$KERNEL_IMG" -append "root=/dev/vda rw rootwait console=ttyAMA0,115200")
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
        -display gtk \
        -serial stdio \
        -device usb-ehci \
        -device usb-kbd \
        -device usb-mouse \
        -nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22 \
        "${KERNEL_ARGS[@]}"
else
    echo "Usage: $0 [--gui [rootfs_path] | --vm]"
    exit 1
fi
