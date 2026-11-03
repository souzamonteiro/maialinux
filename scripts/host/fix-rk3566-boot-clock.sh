#!/usr/bin/env bash
# fix-rk3566-boot-clock.sh
# One-shot shortcut to apply the 1.416GHz CPU stability clock fix to the
# mounted RG353V BOOT partition and MaiaLinux repository.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/rk3566-dtb-tool.sh" fix "$@"

