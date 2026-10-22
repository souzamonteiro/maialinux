#!/usr/bin/env bash
# maialinux-swap.sh
# Manages the 2GB swap file on the root ext4 partition (/swapfile) for MaiaLinux.

set -euo pipefail

SWAP_FILE="${SWAP_FILE:-/swapfile}"
SWAP_SIZE_MB="${SWAP_SIZE_MB:-2048}"

log_info() { echo -e "\033[0;32m[SWAP]\033[0m $1"; }
log_warn() { echo -e "\033[1;33m[SWAP]\033[0m $1"; }

ensure_swap_file() {
    if [[ ! "$SWAP_SIZE_MB" =~ ^[1-9][0-9]*$ ]]; then
        log_warn "SWAP_SIZE_MB must be a positive integer."
        return 1
    fi
    if [[ ! -f "$SWAP_FILE" ]]; then
        local available_kb
        available_kb=$(df -Pk "$(dirname "$SWAP_FILE")" | awk 'NR==2 {print $4}')
        if (( available_kb < (SWAP_SIZE_MB + 512) * 1024 )); then
            log_warn "Insufficient space for ${SWAP_SIZE_MB}MB swap plus 512MB free. Expand root first."
            return 1
        fi
        log_info "Creating ${SWAP_SIZE_MB}MB swap file at $SWAP_FILE..."
        if command -v fallocate >/dev/null 2>&1; then
            if ! fallocate -l "${SWAP_SIZE_MB}M" "$SWAP_FILE"; then
                rm -f "$SWAP_FILE"
                log_warn "Swap allocation failed; removed incomplete file."
                return 1
            fi
        else
            if ! dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE_MB" status=progress; then
                rm -f "$SWAP_FILE"
                return 1
            fi
        fi
        chmod 600 "$SWAP_FILE"
        mkswap "$SWAP_FILE"
        log_info "Swap file created and formatted."
    else
        local current_bytes available_kb needed_kb
        current_bytes=$(stat -c %s "$SWAP_FILE")
        if (( current_bytes < SWAP_SIZE_MB * 1024 * 1024 )); then
            if swapon --noheadings --show=NAME 2>/dev/null | grep -Fxq "$SWAP_FILE"; then
                log_warn "Existing swap is active; keeping its size until it is disabled."
                return 0
            fi
            available_kb=$(df -Pk "$(dirname "$SWAP_FILE")" | awk 'NR==2 {print $4}')
            needed_kb=$((SWAP_SIZE_MB * 1024 - current_bytes / 1024 + 512 * 1024))
            if (( available_kb < needed_kb )); then
                log_warn "Insufficient space to grow existing swap; keeping its size."
                return 0
            fi
            # Allocate the additional blocks before formatting the larger swap.
            fallocate -l "${SWAP_SIZE_MB}M" "$SWAP_FILE" || return 1
            mkswap "$SWAP_FILE"
        fi
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
