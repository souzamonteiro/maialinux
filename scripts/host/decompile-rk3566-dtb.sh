#!/usr/bin/env bash
# decompile-rk3566-dtb.sh
# Shortcut to decompile /media/roberto/BOOT/rk3566-353v.dtb to dts/rk3566-OC.dts

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DTB_INPUT="${1:-}"
DTS_OUTPUT="${2:-$REPO_ROOT/dts/rk3566-OC.dts}"
exec "$SCRIPT_DIR/rk3566-dtb-tool.sh" decompile "$DTB_INPUT" "$DTS_OUTPUT"

