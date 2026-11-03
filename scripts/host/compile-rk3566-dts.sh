#!/usr/bin/env bash
# compile-rk3566-dts.sh
# Shortcut to compile dts/rk3566-OC.dts to DTB and deploy it.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DTS_INPUT="${1:-$REPO_ROOT/dts/rk3566-OC.dts}"
exec "$SCRIPT_DIR/rk3566-dtb-tool.sh" deploy "$DTS_INPUT"

