#!/usr/bin/env bash
# stage-vendor-libs.sh
# Copies vendor-specific runtime libraries required for reproducible distribution builds.

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
ROOTFS="${1:-$MEDIA_BASE/root1}"
VENDOR_DIR="$REPO_ROOT/vendor"

usage() {
  cat <<'EOF'
Usage:
  scripts/host/stage-vendor-libs.sh [rootfs_mount]

Examples:
  scripts/host/stage-vendor-libs.sh /media/$USER/root1
  make stage-vendor-libs ROOTFS=/media/$USER/root1

Copies required runtime/vendor blobs into:
  vendor/mali/aarch64/
  vendor/mali/armhf/   (if available)
  vendor/runtime/lib/
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

MALI_AARCH64_SRC="$ROOTFS/usr/lib/aarch64-linux-gnu/libmali-bifrost-g52-g2p0-gbm.so"
MALI_ARMHF_SRC="$ROOTFS/usr/lib/arm-linux-gnueabihf/libmali-bifrost-g52-g2p0-gbm.so"
WAYLAND_EGL_SRC="$ROOTFS/etc/maialinux-runtime/lib/libwayland-egl.so.1.0.0"

MALI_AARCH64_DST="$VENDOR_DIR/mali/aarch64/libmali-bifrost-g52-g2p0-gbm.so"
MALI_ARMHF_DST="$VENDOR_DIR/mali/armhf/libmali-bifrost-g52-g2p0-gbm.so"
WAYLAND_EGL_DST="$VENDOR_DIR/runtime/lib/libwayland-egl.so.1.0.0"

if [[ ! -d "$ROOTFS" ]]; then
  echo "Error: rootfs path not found: $ROOTFS" >&2
  exit 1
fi

mkdir -p "$(dirname "$MALI_AARCH64_DST")" "$(dirname "$MALI_ARMHF_DST")" "$(dirname "$WAYLAND_EGL_DST")"

if [[ ! -f "$MALI_AARCH64_SRC" ]]; then
  echo "Error: missing Mali aarch64 blob: $MALI_AARCH64_SRC" >&2
  exit 1
fi

if [[ ! -f "$WAYLAND_EGL_SRC" ]]; then
  echo "Error: missing Wayland EGL runtime shim: $WAYLAND_EGL_SRC" >&2
  exit 1
fi

cp -f "$MALI_AARCH64_SRC" "$MALI_AARCH64_DST"
if [[ -f "$MALI_ARMHF_SRC" ]]; then
  cp -f "$MALI_ARMHF_SRC" "$MALI_ARMHF_DST"
fi
cp -f "$WAYLAND_EGL_SRC" "$WAYLAND_EGL_DST"

if [[ "$(stat -Lc%s "$MALI_AARCH64_DST")" -lt 1000000 ]]; then
  echo "Error: staged Mali blob looks invalid (size < 1 MiB): $MALI_AARCH64_DST" >&2
  exit 1
fi

manifest="$VENDOR_DIR/vendor-libs-manifest.txt"
{
  echo "generated_at=$(date -Iseconds)"
  echo "rootfs_source=$ROOTFS"
  echo "mali_aarch64=$MALI_AARCH64_DST"
  echo "mali_aarch64_sha256=$(sha256sum "$MALI_AARCH64_DST" | awk '{print $1}')"
  if [[ -f "$MALI_ARMHF_DST" ]]; then
    echo "mali_armhf=$MALI_ARMHF_DST"
    echo "mali_armhf_sha256=$(sha256sum "$MALI_ARMHF_DST" | awk '{print $1}')"
  fi
  echo "wayland_egl=$WAYLAND_EGL_DST"
  echo "wayland_egl_sha256=$(sha256sum "$WAYLAND_EGL_DST" | awk '{print $1}')"
} > "$manifest"

echo "==> Vendor runtime libraries staged in $VENDOR_DIR"
echo "    Manifest: $manifest"
