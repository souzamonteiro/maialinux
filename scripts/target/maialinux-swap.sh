#!/usr/bin/env bash
# maialinux-swap.sh
# Manages the 2GB swap file on the root ext4 partition (/swapfile) for MaiaLinux.

set -euo pipefail

SWAP_FILE="${SWAP_FILE:-/swapfile}"
SWAP_SIZE_MB="${SWAP_SIZE_MB:-2048}"

log_info() { echo -e "\033[0;32m[SWAP]\033[0m $1"; }
log_warn() { echo -e "\033[1;33m[SWAP]\033[0m $1"; }

ensure_swap_file() {
    if [[ ! -f "$SWAP_FILE" ]]; then
        log_info "Creating ${SWAP_SIZE_MB}MB swap file at $SWAP_FILE..."
        if command -v fallocate >/dev/null 2>&1; then
            fallocate -l "${SWAP_SIZE_MB}M" "$SWAP_FILE" || dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE_MB" status=progress
        else
            dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE_MB" status=progress
        fi
        chmod 600 "$SWAP_FILE"
        mkswap "$SWAP_FILE"
        log_info "Swap file created and formatted."
    else
        chmod 600 "$SWAP_FILE"
        if ! file "$SWAP_FILE" | grep -qi "swap"; then
            mkswap "$SWAP_FILE"
        fi
    fi
}

enable_swap() {
    ensure_swap_file
    if swapon --show 2>/dev/null | grep -q "^$SWAP_FILE "; then
        log_info "Swap $SWAP_FILE is already active."
    else
        swapon "$SWAP_FILE" || log_warn "Could not activate swap (may be running inside chroot)."
    fi
    sysctl -w vm.swappiness=10 >/dev/null 2>&1 || true
}

disable_swap() {
    if swapon --show 2>/dev/null | grep -q "^$SWAP_FILE "; then
        swapoff "$SWAP_FILE" || true
        log_info "Swap $SWAP_FILE deactivated."
    fi
}

status_swap() {
    echo "=== MaiaLinux Swap Status ==="
    swapon --show || true
    free -h
}

case "${1:-enable}" in
    create)  ensure_swap_file ;;
    enable)  enable_swap ;;
    disable) disable_swap ;;
    status)  status_swap ;;
    *)
        echo "Usage: $0 {create|enable|disable|status}"
        exit 1
        ;;
esac
