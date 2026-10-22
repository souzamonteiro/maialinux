#!/usr/bin/env bash
# maialinux-healthcheck.sh
# Comprehensive diagnostic and verification suite for MaiaLinux on Anbernic RG353V.

set -uo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0

pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; ((PASS++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL++)); }

echo "============================================================"
echo "  MaiaLinux RG353V Reproducible Distribution Health Check"
echo "============================================================"
echo "Architecture : $(uname -m)"
echo "OS Release   : $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
echo ""

echo "1. GPU & Library Integrity (ArkOS Mali Bifrost G52 + Mesa):"
for arch_dir in /usr/lib/aarch64-linux-gnu /usr/lib/arm-linux-gnueabihf; do
    if [[ -f "$arch_dir/libmali-bifrost-g52-g2p0-gbm.so" ]]; then
        pass "$arch_dir/libmali-bifrost-g52-g2p0-gbm.so present"
    else
        fail "$arch_dir/libmali-bifrost-g52-g2p0-gbm.so missing"
    fi
    for sym in libMali.so libEGL.so.1 libGLESv2.so.2 libgbm.so.1 libwayland-egl.so.1; do
        if [[ -L "$arch_dir/$sym" ]] && [[ -e "$arch_dir/$sym" ]]; then
            pass "$arch_dir/$sym -> $(readlink "$arch_dir/$sym")"
        else
            fail "$arch_dir/$sym broken or not a symlink"
        fi
    done
done

LDCONFIG_WARNINGS=$(/sbin/ldconfig -v 2>&1 | grep "is not a symbolic link" || true)
if [[ -z "$LDCONFIG_WARNINGS" ]]; then
    pass "ldconfig has 0 broken symlink warnings"
else
    warn "ldconfig reported warnings: $LDCONFIG_WARNINGS"
fi

echo ""
echo "2. X11 & LXQt Desktop Environment:"
for cmd in Xorg startx startlxqt openbox pcmanfm-qt qterminal featherpad geany matchbox-keyboard onboard; do
    if command -v "$cmd" >/dev/null 2>&1; then
        pass "Command '$cmd' installed ($(command -v "$cmd"))"
    else
        fail "Command '$cmd' missing"
    fi
done

if [[ -f /etc/X11/xorg.conf.d/10-rockchip-modesetting.conf ]]; then
    pass "Rockchip modesetting Xorg config present"
else
    fail "Rockchip modesetting Xorg config missing"
fi

if [[ -f /etc/X11/Xwrapper.config ]] && grep -q "needs_root_rights=yes" /etc/X11/Xwrapper.config; then
    pass "Xwrapper.config configured with needs_root_rights=yes"
else
    fail "Xwrapper.config missing or misconfigured"
fi

echo ""
echo "3. Development Toolchain & Libraries (C/C++, Python3, SDL2, GTK3, Qt5):"
for cmd in gcc g++ make cmake gdb git pkg-config tmux htop python3 pip3 sdl2-config; do
    if command -v "$cmd" >/dev/null 2>&1; then
        pass "Dev tool '$cmd' available"
    else
        fail "Dev tool '$cmd' missing"
    fi
done

for pkg in sdl2 gtk+-3.0 Qt5Core Qt5Widgets; do
    if pkg-config --exists "$pkg" 2>/dev/null; then
        pass "pkg-config library '$pkg' ($(pkg-config --modversion "$pkg")) ready"
    else
        fail "pkg-config library '$pkg' missing"
    fi
done

if python3 -c "import tkinter, pygame" >/dev/null 2>&1; then
    pass "Python3 modules 'tkinter' and 'pygame' importable"
else
    warn "Python3 tkinter or pygame module could not be imported"
fi

echo ""
echo "4. Controls, Swap, Launchers & Example Projects:"
if [[ -x /opt/inttools/gptokeyb ]] && [[ -f /etc/maialinux/desktop.gptk ]]; then
    pass "Gamepad mapper (gptokeyb + desktop.gptk) ready"
else
    fail "Gamepad mapper missing"
fi

if [[ -f /swapfile ]]; then
    pass "Swap file /swapfile present ($(du -h /swapfile | cut -f1))"
else
    warn "Swap file /swapfile not created yet (will be created on first launch or boot)"
fi

for script in /usr/local/bin/start-maialinux.sh /usr/local/bin/maialinux-keyboard-toggle /usr/local/bin/switch-boot-mode.sh /roms/tools/Launch-MaiaLinux-LXQt.sh /opt/system/Tools/Launch-MaiaLinux-LXQt.sh; do
    if [[ -x "$script" ]]; then
        pass "Launcher script '$script' executable"
    else
        fail "Launcher script '$script' missing or not executable"
    fi
done

echo ""
echo "============================================================"
echo -e "Summary: ${GREEN}${PASS} PASSED${NC}, ${YELLOW}${WARN} WARNINGS${NC}, ${RED}${FAIL} FAILED${NC}"
echo "============================================================"

[[ "$FAIL" -eq 0 ]]
