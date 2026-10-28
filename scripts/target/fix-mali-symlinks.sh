#!/usr/bin/env bash
# fix-mali-symlinks.sh
# Preserves and restores ArkOS Mali Bifrost G52 GPU drivers (aarch64 & armhf),
# keeps real libwayland-egl.so.1 (so GTK3 apps have wl_egl_window_* symbols),
# converts same-directory absolute symlinks to relative symlinks, and fixes
# duplicate non-symlink shared libraries so ldconfig has zero warnings.

set -euo pipefail

BACKUP_DIR="/opt/maialinux/backup/mali"
AARCH64_DIR="/usr/lib/aarch64-linux-gnu"
ARMHF_DIR="/usr/lib/arm-linux-gnueabihf"

log_info() { echo -e "\033[0;32m[MALI-FIX]\033[0m $1"; }
log_warn() { echo -e "\033[1;33m[MALI-WARN]\033[0m $1"; }

backup_mali() {
    mkdir -p "$BACKUP_DIR/aarch64" "$BACKUP_DIR/armhf"
    if [[ -f "$AARCH64_DIR/libmali-bifrost-g52-g2p0-gbm.so" ]] && (( $(stat -Lc%s "$AARCH64_DIR/libmali-bifrost-g52-g2p0-gbm.so") > 1000000 )); then
        cp -af "$AARCH64_DIR/libmali-bifrost-g52-g2p0-gbm.so" "$BACKUP_DIR/aarch64/"
        log_info "Backed up aarch64 libmali-bifrost-g52-g2p0-gbm.so"
    fi
    if [[ -f "$ARMHF_DIR/libmali-bifrost-g52-g2p0-gbm.so" ]] && (( $(stat -Lc%s "$ARMHF_DIR/libmali-bifrost-g52-g2p0-gbm.so") > 1000000 )); then
        cp -af "$ARMHF_DIR/libmali-bifrost-g52-g2p0-gbm.so" "$BACKUP_DIR/armhf/"
        log_info "Backed up armhf libmali-bifrost-g52-g2p0-gbm.so"
    fi
}

setup_arch_mali_links() {
    local libdir="$1"
    local backup_sub="$2"
    local preferred_blob="libmali-bifrost-g52-g2p0-gbm.so"
    local fallback_blob="libmali-bifrost-g52-g29p1.so"
    local blob=""

    if [[ ! -d "$libdir" ]]; then
        return 0
    fi

    # Prefer g2p0 blob. If it is unavailable but g29p1 exists, use g29p1 as
    # the real blob and create g2p0 compatibility alias for health checks/tools.
    if [[ -f "$libdir/$preferred_blob" ]] && (( $(stat -c%s "$libdir/$preferred_blob" 2>/dev/null || echo 0) > 1000000 )); then
        blob="$preferred_blob"
    elif [[ -f "$libdir/$fallback_blob" ]] && (( $(stat -c%s "$libdir/$fallback_blob" 2>/dev/null || echo 0) > 1000000 )); then
        blob="$fallback_blob"
        ln -sf "$fallback_blob" "$libdir/$preferred_blob"
        log_info "Created compatibility alias $preferred_blob -> $fallback_blob in $libdir"
    elif [[ -f "$BACKUP_DIR/$backup_sub/$preferred_blob" ]]; then
        cp -af --remove-destination "$BACKUP_DIR/$backup_sub/$preferred_blob" "$libdir/$preferred_blob"
        chmod 755 "$libdir/$preferred_blob"
        blob="$preferred_blob"
        log_info "Restored $libdir/$preferred_blob from backup"
    elif [[ -f "$BACKUP_DIR/$backup_sub/$fallback_blob" ]]; then
        cp -af --remove-destination "$BACKUP_DIR/$backup_sub/$fallback_blob" "$libdir/$fallback_blob"
        chmod 755 "$libdir/$fallback_blob"
        ln -sf "$fallback_blob" "$libdir/$preferred_blob"
        blob="$fallback_blob"
        log_info "Restored $libdir/$fallback_blob from backup and linked $preferred_blob"
    else
        log_warn "No suitable Mali blob found in $libdir or backup ($preferred_blob/$fallback_blob)!"
        return 0
    fi

    # Point libMali.so relatively to the Bifrost G52 GBM blob
    ln -sf "$blob" "$libdir/libMali.so"

    # Point GBM / EGL / GLES / OpenCL links relatively to libMali.so.
    # NOTE: Do NOT point libwayland-egl.so* to libMali.so because the G52 GBM blob
    # does not export wl_egl_window_* symbols needed by GTK3 (libgdk-3.so.0).
    local mali_links=(
        "libmali.so"
        "libmali.so.1"
        "libEGL.so"
        "libEGL.so.1"
        "libGLES_CM.so"
        "libGLES_CM.so.1"
        "libGLESv1_CM.so"
        "libGLESv1_CM.so.1"
        "libGLESv1_CM.so.1.1.0"
        "libGLESv2.so"
        "libGLESv2.so.2"
        "libGLESv2.so.2.0.0"
        "libGLESv2.so.2.1.0"
        "libGLESv3.so"
        "libGLESv3.so.3"
        "libgbm.so"
        "libgbm.so.1"
        "libgbm.so.1.0.0"
        "libMaliOpenCL.so"
        "libMaliOpenCL.so.1"
        "libOpenCL.so"
    )

    for link_name in "${mali_links[@]}"; do
        rm -f "$libdir/$link_name"
        ln -sf "libMali.so" "$libdir/$link_name"
    done

    # Convert any absolute symlinks pointing into the same directory into relative symlinks
    # (e.g., libSDL2-2.0.so.0 -> /usr/lib/aarch64-linux-gnu/libSDL2.so)
    for l in "$libdir"/*; do
        if [[ -L "$l" ]]; then
            local target
            target=$(readlink "$l")
            if [[ "$target" == "$libdir/"* ]]; then
                local rel_target="${target#$libdir/}"
                ln -sf "$rel_target" "$l"
            fi
        fi
    done

    log_info "Configured relative Mali GBM/EGL/GLES symlinks in $libdir"
}

fix_duplicate_soname_files() {
    local known_SONAMES=(
        "$AARCH64_DIR/libSDL2_gfx-1.0.so.0"
        "$AARCH64_DIR/libnm.so.0"
        "$ARMHF_DIR/libQt5EglFSDeviceIntegration.so.5"
        "$ARMHF_DIR/libpcre2-16.so.0"
        "$ARMHF_DIR/libQt5OpenGL.so.5"
        "$ARMHF_DIR/libQt5Core.so.5"
        "$ARMHF_DIR/libSDL2_net-2.0.so.0"
        "$ARMHF_DIR/libQt5EglFsKmsSupport.so.5"
        "$ARMHF_DIR/libQt5DBus.so.5"
        "$ARMHF_DIR/libQt5Svg.so.5"
        "$ARMHF_DIR/libQt5XcbQpa.so.5"
        "$ARMHF_DIR/libQt5Network.so.5"
        "$ARMHF_DIR/libQt5Gui.so.5"
        "$ARMHF_DIR/libQt5Widgets.so.5"
        "$ARMHF_DIR/libdouble-conversion.so.3"
    )

    for soname_path in "${known_SONAMES[@]}"; do
        if [[ -f "$soname_path" && ! -L "$soname_path" ]]; then
            local dir
            dir=$(dirname "$soname_path")
            local base
            base=$(basename "$soname_path")
            local versioned
            versioned=$(find "$dir" -maxdepth 1 -name "${base}.*" -type f | sort -V | tail -n 1)
            local size
            size=$(stat -c%s "$soname_path" 2>/dev/null || echo 0)

            if [[ -n "$versioned" ]]; then
                rm -f "$soname_path"
                ln -sf "$(basename "$versioned")" "$soname_path"
                log_info "Converted duplicate file to symlink: $base -> $(basename "$versioned")"
            elif [[ "$size" -lt 100 ]]; then
                rm -f "$soname_path"
                log_info "Removed truncated library file: $soname_path ($size bytes)"
            fi
        fi
    done
}

case "${1:---restore}" in
    --backup)
        backup_mali
        ;;
    --restore|*)
        backup_mali
        setup_arch_mali_links "$AARCH64_DIR" "aarch64"
        setup_arch_mali_links "$ARMHF_DIR" "armhf"
        # Ensure real libwayland-egl1 is intact for GTK3 apps
        apt-get install -y --reinstall libwayland-egl1 libwayland-dev >/dev/null 2>&1 || true
        fix_duplicate_soname_files
        ldconfig
        log_info "ldconfig cache rebuilt cleanly."
        ;;
esac
