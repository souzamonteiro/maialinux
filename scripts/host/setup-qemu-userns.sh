#!/usr/bin/env bash
# Optional Ubuntu host setup. Requires explicit administrator approval.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="$REPO_ROOT/config/apparmor/maialinux-bwrap"
TARGET=/etc/apparmor.d/maialinux-bwrap
if [[ "$EUID" -ne 0 ]]; then
    echo "Run once with administrator approval: sudo $0" >&2
    exit 1
fi
command -v apparmor_parser >/dev/null
apparmor_parser -Q -T "$SOURCE"
if [[ -f "$TARGET" ]] && ! cmp -s "$SOURCE" "$TARGET"; then
    echo "An existing different profile is present at $TARGET; inspect it before replacing it." >&2
    exit 1
fi
install -m644 "$SOURCE" "$TARGET"
apparmor_parser -r "$TARGET"
echo "Bubblewrap profile installed. Run the QEMU launcher without sudo."
