#!/usr/bin/env bash
# chroot-run.sh
# Safely enters an ARM64 ArkOS rootfs from an x86_64 Linux host using qemu-aarch64-static.
# Automatically mounts/unmounts /proc, /sys, /dev, /dev/pts, sets up DNS, and prevents
# systemd services from attempting to start inside the chroot during apt installations.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: sudo $0 <rootfs_path> [command...]"
    echo "Example: sudo $0 /media/roberto/root /bin/bash"
    exit 1
fi

ROOTFS="$(realpath "$1")"
shift
CMD=("${@:-/bin/bash}")

if [[ $EUID -ne 0 ]]; then
    echo "Error: chroot-run.sh must be run with sudo." >&2
    exit 1
fi

if [[ ! -d "$ROOTFS/usr/bin" ]]; then
    echo "Error: '$ROOTFS' does not appear to be a valid Linux rootfs." >&2
    exit 1
fi

QEMU_BIN="$(command -v qemu-aarch64-static || true)"
if [[ -z "$QEMU_BIN" ]]; then
    echo "Error: qemu-aarch64-static not found on host. Install 'qemu-user-static'." >&2
    exit 1
fi

cleanup() {
    set +e
    rm -f "$ROOTFS/usr/sbin/policy-rc.d"
    if [[ -f "$ROOTFS/etc/resolv.conf.maialinux.bak" ]] || [[ -L "$ROOTFS/etc/resolv.conf.maialinux.bak" ]]; then
        rm -f "$ROOTFS/etc/resolv.conf"
        mv "$ROOTFS/etc/resolv.conf.maialinux.bak" "$ROOTFS/etc/resolv.conf"
    fi
    umount -lf "$ROOTFS/dev/pts" 2>/dev/null || true
    umount -lf "$ROOTFS/dev" 2>/dev/null || true
    umount -lf "$ROOTFS/sys" 2>/dev/null || true
    umount -lf "$ROOTFS/proc" 2>/dev/null || true
}
trap cleanup EXIT

# 1. Install qemu-aarch64-static binary into target rootfs
cp -f "$QEMU_BIN" "$ROOTFS/usr/bin/qemu-aarch64-static"
chmod 755 "$ROOTFS/usr/bin/qemu-aarch64-static"

# 2. Mount virtual filesystems
mount -t proc /proc "$ROOTFS/proc"
mount -t sysfs /sys "$ROOTFS/sys"
mount --bind /dev "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"

# 3. Configure DNS resolution inside chroot
if [[ -e "$ROOTFS/etc/resolv.conf" ]] || [[ -L "$ROOTFS/etc/resolv.conf" ]]; then
    mv "$ROOTFS/etc/resolv.conf" "$ROOTFS/etc/resolv.conf.maialinux.bak"
fi
cat > "$ROOTFS/etc/resolv.conf" << 'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

# 4. Prevent apt from starting background services inside chroot
cat > "$ROOTFS/usr/sbin/policy-rc.d" << 'EOF'
#!/bin/sh
exit 101
EOF
chmod 755 "$ROOTFS/usr/sbin/policy-rc.d"

# 5. Execute command inside ARM64 chroot
chroot "$ROOTFS" /usr/bin/qemu-aarch64-static "${CMD[@]}"
