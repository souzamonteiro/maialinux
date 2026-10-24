#!/usr/bin/env bash
# run-qemu-image.sh
# Launches the MaiaLinux QEMU release artifact (distro/MaiaLinux-RG353V-v1.0.0-qemu.qcow2).
# Supports two modes:
#   --gui  (default): 640x480 ARM64 LXQt graphical desktop via Xephyr + bwrap + qemu-aarch64-static
#          Automatically mounts the QCOW2 image via udisksctl (rootless, no sudo required!) if no SD card is mounted.
#   --vm   (full-system ARM64 VM): Opens a graphical qemu-system-aarch64 window

set -euo pipefail

# Bubblewrap must map the desktop user's UID, not root, into the guest.
# Mapping root drops its host DAC override and cannot traverse /media/$USER.
if [[ "$EUID" -eq 0 ]]; then
    if [[ "${SUDO_UID:-0}" != 0 ]]; then
        USER_ENV=("DISPLAY=${DISPLAY:-}" "XDG_RUNTIME_DIR=/run/user/$SUDO_UID")
        for name in XAUTHORITY QCOW2_IMG KERNEL_IMG INITRD_IMG QEMU_RAW_CACHE_DIR; do
            if [[ -v "$name" ]]; then
                USER_ENV+=("$name=${!name}")
            fi
        done
        echo "Running the QEMU desktop as the original user (sudo is unnecessary)."
        exec sudo -H -u "#$SUDO_UID" -- env "${USER_ENV[@]}" bash "${BASH_SOURCE[0]}" "$@"
    fi
    echo "Run this launcher from your normal desktop user, without sudo." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/MaiaLinux-RG353V-v1.0.0-qemu.qcow2" ]]; then
    DISTRO_DIR="$SCRIPT_DIR"
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || pwd)"
else
    REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    DISTRO_DIR="$REPO_ROOT/distro"
fi

QCOW2_IMG="${QCOW2_IMG:-$DISTRO_DIR/MaiaLinux-RG353V-v1.0.0-qemu.qcow2}"
KERNEL_IMG="${KERNEL_IMG:-}"
INITRD_IMG="${INITRD_IMG:-}"
QEMU_RAW_CACHE_DIR="${QEMU_RAW_CACHE_DIR:-$HOME/.cache/maialinux-qemu}"
CURRENT_USER="${USER:-$(id -un 2>/dev/null || echo root)}"
MEDIA_BASE="${MEDIA_BASE:-}"
if [[ -z "$MEDIA_BASE" ]]; then
    for candidate in "/media/$CURRENT_USER" "/run/media/$CURRENT_USER" "/media/${SUDO_USER:-$CURRENT_USER}" "/run/media/${SUDO_USER:-$CURRENT_USER}"; do
        if [[ -d "$candidate" ]]; then
            MEDIA_BASE="$candidate"
            break
        fi
    done
    [[ -n "$MEDIA_BASE" ]] || MEDIA_BASE="/media/$CURRENT_USER"
fi
MODE="${1:---gui}"

mkdir -p "$QEMU_RAW_CACHE_DIR"
for candidate in "$QEMU_RAW_CACHE_DIR" /tmp/maialinux-qemu-cache; do
    if mkdir -p "$candidate" 2>/dev/null && [[ -w "$candidate" ]]; then
        free_kib=$(df -Pk "$candidate" 2>/dev/null | awk 'NR==2 {print $4}')
        if [[ -n "$free_kib" && "$free_kib" -ge 4194304 ]]; then
            QEMU_RAW_CACHE_DIR="$candidate"
            break
        fi
    fi
done

if [[ ! -d "$QEMU_RAW_CACHE_DIR" || ! -w "$QEMU_RAW_CACHE_DIR" ]]; then
    QEMU_RAW_CACHE_DIR="/tmp/maialinux-qemu-cache"
    mkdir -p "$QEMU_RAW_CACHE_DIR"
fi

if [[ "$MODE" == "--auto" ]]; then
    MODE="--gui"
fi

if [[ "$MODE" == "--gui" ]]; then
    ROOTFS_PATH="${2:-}"
    if [[ -n "$ROOTFS_PATH" ]] && [[ ! -d "$ROOTFS_PATH/usr/bin" ]]; then
        ROOTFS_PATH=""
    fi

    desktop_rootfs_ok() {
        local path="${1:-}"
        [[ -n "$path" ]] || return 1
        [[ -d "$path/usr/bin" ]] || return 1
        [[ -x "$path/usr/bin/startlxqt" || -d "$path/usr/share/lxqt" || -d "$path/etc/xdg/lxqt" ]] || return 1
        return 0
    }

    if [[ -z "$ROOTFS_PATH" ]]; then
        for candidate in "$MEDIA_BASE/root" "$MEDIA_BASE/root1" "$MEDIA_BASE/MAIALINUX_QEMU" "$MEDIA_BASE/MAIALINUX_QEMU_ROOT" "/media/${CURRENT_USER}/root" "/media/${CURRENT_USER}/root1"; do
            if desktop_rootfs_ok "$candidate"; then
                ROOTFS_PATH="$candidate"
                break
            fi
        done
    fi

    if [[ -z "$ROOTFS_PATH" ]] || ! desktop_rootfs_ok "$ROOTFS_PATH"; then
        if [[ ! -f "$QCOW2_IMG" ]]; then
            echo "Error: QEMU image not found at $QCOW2_IMG" >&2
            exit 1
        fi
        CACHE_KEY="$(stat -c '%s-%Y' "$QCOW2_IMG")"
        RAW_SHM="$QEMU_RAW_CACHE_DIR/maialinux-rootfs-${CACHE_KEY}.raw"
        if [[ ! -f "$RAW_SHM" ]]; then
            echo "==> Preparing QEMU rootfs cache ($RAW_SHM) from $QCOW2_IMG ..."
            if ! qemu-img convert -p -f qcow2 -O raw "$QCOW2_IMG" "$RAW_SHM.tmp"; then
                rm -f "$RAW_SHM.tmp"
                echo "Could not prepare the image cache. Set QEMU_RAW_CACHE_DIR to a filesystem with enough free space." >&2
                exit 1
            fi
            mv "$RAW_SHM.tmp" "$RAW_SHM"
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
            # Wait briefly in case a stale or unrelated mount is present. Only accept a desktop image.
            for _ in 1 2 3 4; do
                MNT_PT="$(lsblk -no MOUNTPOINT "$LOOP_DEV" 2>/dev/null | head -n1 || true)"
                if [[ -n "$MNT_PT" ]] && desktop_rootfs_ok "$MNT_PT"; then
                    ROOTFS_PATH="$MNT_PT"
                    break
                fi
                sleep 0.4
            done
            if [[ -z "$ROOTFS_PATH" ]] || ! desktop_rootfs_ok "$ROOTFS_PATH"; then
                udisksctl mount -b "$LOOP_DEV" >/dev/null 2>&1 || true
                MNT_PT="$(lsblk -no MOUNTPOINT "$LOOP_DEV" 2>/dev/null | head -n1 || true)"
                if [[ -n "$MNT_PT" ]] && desktop_rootfs_ok "$MNT_PT"; then
                    ROOTFS_PATH="$MNT_PT"
                fi
            fi
        elif command -v guestmount >/dev/null 2>&1; then
            mkdir -p /tmp/maialinux-qcow2-mnt
            guestmount -r -a "$QCOW2_IMG" -m /dev/sda /tmp/maialinux-qcow2-mnt
            trap 'guestunmount /tmp/maialinux-qcow2-mnt 2>/dev/null || true' EXIT
            if desktop_rootfs_ok "/tmp/maialinux-qcow2-mnt"; then
                ROOTFS_PATH="/tmp/maialinux-qcow2-mnt"
            fi
        fi
    fi

    if [[ -z "$ROOTFS_PATH" ]] || ! desktop_rootfs_ok "$ROOTFS_PATH"; then
        echo "Error: Could not mount a valid MaiaLinux LXQt rootfs from $QCOW2_IMG" >&2
        echo "Hint: a mounted loop image under ${MEDIA_BASE}/MAIALINUX_QEMU is not the full desktop image and lacks startlxqt." >&2
        exit 1
    fi

    TEST_SCRIPT="$REPO_ROOT/scripts/host/test-qemu-desktop.sh"
    if [[ -f "$DISTRO_DIR/qemu-support/scripts/host/test-qemu-desktop.sh" ]]; then
        TEST_SCRIPT="$DISTRO_DIR/qemu-support/scripts/host/test-qemu-desktop.sh"
    fi
    exec "$TEST_SCRIPT" "$ROOTFS_PATH" --interactive
elif [[ "$MODE" == "--vm" ]]; then
    if [[ -z "$KERNEL_IMG" || ! -f "$KERNEL_IMG" ]]; then
        echo "Full-system mode requires KERNEL_IMG pointing to an ARM64 kernel with QEMU virt support." >&2
        echo "Use --gui for the distributed desktop image; the RG353V kernel is for the handheld." >&2
        exit 1
    fi
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
