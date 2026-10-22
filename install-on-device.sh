#!/usr/bin/env bash
# install-on-device.sh
# Reproducible installer for MaiaLinux on Anbernic RG353V (ArkOS Ubuntu 19.10 Eoan aarch64).
# Can run either:
#   1) Inside a QEMU user-mode chroot on an x86_64 host PC (fast, offline-capable SD card / .img build)
#   2) Directly on the Anbernic RG353V console via SSH

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="ark"
TARGET_UID="1002"
TARGET_GID="1002"
TARGET_HOME="/home/${TARGET_USER}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_step() { echo -e "\n${BLUE}==> $1${NC}"; }
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    echo "Error: install-on-device.sh must be run as root (use sudo)." >&2
    exit 1
fi

log_step "1/9 Backing up ArkOS Mali Bifrost G52 GPU drivers"
mkdir -p /opt/maialinux /etc/maialinux
install -m 755 "$REPO_ROOT/scripts/target/fix-mali-symlinks.sh" /usr/local/bin/fix-mali-symlinks.sh
/usr/local/bin/fix-mali-symlinks.sh --backup

log_step "2/9 Configuring Ubuntu 19.10 (Eoan) old-releases APT repositories"
if [[ ! -f /etc/apt/sources.list.orig ]]; then
    cp -a /etc/apt/sources.list /etc/apt/sources.list.orig 2>/dev/null || true
fi

cat > /etc/apt/sources.list << 'EOF'
deb http://old-releases.ubuntu.com/ubuntu/ eoan main restricted universe multiverse
deb http://old-releases.ubuntu.com/ubuntu/ eoan-updates main restricted universe multiverse
deb http://old-releases.ubuntu.com/ubuntu/ eoan-security main restricted universe multiverse
EOF

cat > /etc/apt/apt.conf.d/99maialinux << 'EOF'
Acquire::Retries "3";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
APT::Get::AllowUnauthenticated "true";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
Dpkg::Options {
   "--force-confdef";
   "--force-confold";
   "--force-overwrite";
};
EOF

apt-get update

log_step "3/9 Resolving ArkOS libmali / libwayland-egl1 dpkg conflict"
# ArkOS ships a custom package 'libmali-rk-bifrost-g31-rxp0-wayland-gbm' that claims
# libwayland-egl.so.1 and blocks standard X11/GTK3/Qt5/LXQt packages from installing.
# Since we backed up the real G52 GBM binary and restore all symlinks after apt finishes,
# we safely remove the conflicting package metadata first.
rm -f /lib/aarch64-linux-gnu/libwayland-egl.so* /usr/lib/aarch64-linux-gnu/libwayland-egl.so* 2>/dev/null || true
if dpkg -s libmali-rk-bifrost-g31-rxp0-wayland-gbm >/dev/null 2>&1; then
    dpkg --remove --force-all libmali-rk-bifrost-g31-rxp0-wayland-gbm || true
fi
apt-get install -f -y
apt-get install -y --reinstall libwayland-egl1 libwayland-client0 libwayland-cursor0 libwayland-server0 libwayland-dev

log_step "4/9 Installing Xorg, LXQt, Virtual Keyboards, Geany IDE, and Dev Toolchains"
PACKAGES=(
    # X11 Server & Drivers
    xorg
    xserver-xorg
    xserver-xorg-core
    xserver-xorg-legacy
    xserver-xorg-video-modesetting
    xserver-xorg-video-fbdev
    xserver-xorg-input-libinput
    xinit
    x11-xserver-utils
    x11-utils
    xinput
    xterm
    dbus-x11

    # LXQt Desktop Environment & Window Manager
    lxqt-core
    lxqt-session
    lxqt-panel
    lxqt-config
    lxqt-qtplugin
    lxqt-globalkeys
    lxqt-notificationd
    lxqt-policykit
    openbox
    obconf-qt
    pcmanfm-qt
    qterminal
    featherpad
    geany
    papirus-icon-theme
    adwaita-icon-theme
    gnome-themes-extra
    qt5-gtk-platformtheme
    xdg-utils
    scrot
    imagemagick

    # Virtual Keyboards for 640x480 Touchscreen / Controller
    matchbox-keyboard
    onboard
    at-spi2-core

    # C/C++ & System Development Tools
    build-essential
    gcc
    g++
    make
    cmake
    gdb
    git
    pkg-config
    tmux
    htop
    nano
    vim
    curl
    wget
    rsync
    openssh-server

    # Python 3 Development Stack
    python3
    python3-pip
    python3-venv
    python3-dev
    python3-tk
    python3-pygame
    python3-evdev

    # Graphics & Game Development Libraries (SDL2, GTK3, Qt5, OpenGL ES / DRM)
    libsdl2-dev
    libsdl2-image-dev
    libsdl2-mixer-dev
    libsdl2-ttf-dev
    libsdl2-gfx-dev
    libsdl2-net-dev
    libgtk-3-dev
    qtbase5-dev
    libqt5svg5-dev
    libgl1-mesa-dri
    libgl1-mesa-dev
    libegl1-mesa-dev
    libgles2-mesa-dev
    libgbm-dev
    libdrm-dev
    mesa-utils
)

apt-get install -y "${PACKAGES[@]}"

# Ensure display managers (lightdm/sddm/gdm) are disabled so they don't fight EmulationStation
for dm in lightdm sddm gdm gdm3 lxdm; do
    systemctl disable "$dm" 2>/dev/null || true
    systemctl stop "$dm" 2>/dev/null || true
done

log_step "5/9 Restoring ArkOS Mali Bifrost G52 GPU drivers and fixing library symlinks"
/usr/local/bin/fix-mali-symlinks.sh --restore

log_step "6/9 Installing Xorg, LXQt (640x480), Openbox, Geany, and Controller configurations"
mkdir -p /etc/X11/xorg.conf.d
rm -f /etc/X11/xorg.conf /etc/X11/xorg.conf.d/10-modesetting.conf /etc/X11/xorg.conf.d/10-fbdev.conf
install -m 644 "$REPO_ROOT/config/xorg/10-rockchip-modesetting.conf" /etc/X11/xorg.conf.d/10-rockchip-modesetting.conf
install -m 644 "$REPO_ROOT/config/xorg/20-touchscreen.conf" /etc/X11/xorg.conf.d/20-touchscreen.conf
install -m 644 "$REPO_ROOT/config/xorg/Xwrapper.config" /etc/X11/Xwrapper.config

# Install controller mapping for desktop
install -m 644 "$REPO_ROOT/config/controls/desktop.gptk" /etc/maialinux/desktop.gptk

# Install target management & launcher scripts
install -m 755 "$REPO_ROOT/config/keyboard/maialinux-keyboard-toggle" /usr/local/bin/maialinux-keyboard-toggle
install -m 755 "$REPO_ROOT/scripts/target/maialinux-swap.sh" /usr/local/bin/maialinux-swap.sh
install -m 755 "$REPO_ROOT/scripts/target/start-maialinux.sh" /usr/local/bin/start-maialinux.sh
install -m 755 "$REPO_ROOT/scripts/target/maialinux-return-to-es" /usr/local/bin/maialinux-return-to-es
install -m 755 "$REPO_ROOT/scripts/target/switch-boot-mode.sh" /usr/local/bin/switch-boot-mode.sh
install -m 755 "$REPO_ROOT/scripts/target/maialinux-healthcheck.sh" /usr/local/bin/maialinux-healthcheck.sh

# Install EmulationStation Tools menu entries (both /roms/tools and /opt/system/Tools)
for tools_dir in /roms/tools /opt/system/Tools; do
    mkdir -p "$tools_dir"
    install -m 755 "$REPO_ROOT/scripts/target/start-maialinux.sh" "$tools_dir/Launch-MaiaLinux-LXQt.sh"
    install -m 755 "$REPO_ROOT/scripts/target/switch-boot-mode.sh" "$tools_dir/Switch-Boot-Mode.sh"
done

# Configure user 'ark' groups and passwordless sudo for MaiaLinux helper scripts
usermod -aG video,input,render,audio,tty "$TARGET_USER" 2>/dev/null || true

# Install LXQt, Openbox, PCManFM-Qt, and Geany 640x480 profile for user 'ark'
mkdir -p "$TARGET_HOME/.config/lxqt" \
         "$TARGET_HOME/.config/openbox" \
         "$TARGET_HOME/.config/pcmanfm-qt/lxqt" \
         "$TARGET_HOME/.config/geany" \
         "$TARGET_HOME/.config/autostart" \
         "$TARGET_HOME/Desktop" \
         "$TARGET_HOME/projects" \
         /usr/local/share/applications

install -m 644 "$REPO_ROOT/config/lxqt/lxqt.conf" "$TARGET_HOME/.config/lxqt/lxqt.conf"
install -m 644 "$REPO_ROOT/config/lxqt/panel.conf" "$TARGET_HOME/.config/lxqt/panel.conf"
install -m 644 "$REPO_ROOT/config/lxqt/session.conf" "$TARGET_HOME/.config/lxqt/session.conf"
install -m 644 "$REPO_ROOT/config/lxqt/openbox-lxqt-rc.xml" "$TARGET_HOME/.config/openbox/lxqt-rc.xml"
install -m 644 "$REPO_ROOT/config/lxqt/pcmanfm-qt-settings.conf" "$TARGET_HOME/.config/pcmanfm-qt/lxqt/settings.conf"
install -m 644 "$REPO_ROOT/config/geany/geany.conf" "$TARGET_HOME/.config/geany/geany.conf"

# Install Desktop and Application shortcuts
install -m 755 "$REPO_ROOT/config/desktop-entries/maialinux-keyboard.desktop" /usr/local/share/applications/maialinux-keyboard.desktop
install -m 755 "$REPO_ROOT/config/desktop-entries/return-to-es.desktop" /usr/local/share/applications/return-to-es.desktop
install -m 755 "$REPO_ROOT/config/desktop-entries/maialinux-keyboard.desktop" "$TARGET_HOME/Desktop/maialinux-keyboard.desktop"
install -m 755 "$REPO_ROOT/config/desktop-entries/geany-dev.desktop" "$TARGET_HOME/Desktop/geany-dev.desktop"
install -m 755 "$REPO_ROOT/config/desktop-entries/qterminal-dev.desktop" "$TARGET_HOME/Desktop/qterminal-dev.desktop"
install -m 755 "$REPO_ROOT/config/desktop-entries/maialinux-projects.desktop" "$TARGET_HOME/Desktop/maialinux-projects.desktop"
install -m 755 "$REPO_ROOT/config/desktop-entries/return-to-es.desktop" "$TARGET_HOME/Desktop/return-to-es.desktop"

log_step "7/9 Installing & compiling starter development projects in ~/projects"
cp -rf "$REPO_ROOT/examples/"* "$TARGET_HOME/projects/"

if [[ -f "$TARGET_HOME/projects/hello-c/Makefile" ]]; then
    make -C "$TARGET_HOME/projects/hello-c" clean all || log_warn "Could not precompile hello-c"
fi
if [[ -f "$TARGET_HOME/projects/hello-sdl2/Makefile" ]]; then
    make -C "$TARGET_HOME/projects/hello-sdl2" clean all || log_warn "Could not precompile hello-sdl2"
fi

chown -R "${TARGET_UID}:${TARGET_GID}" "$TARGET_HOME/.config" "$TARGET_HOME/Desktop" "$TARGET_HOME/projects" /roms/tools /opt/system/Tools 2>/dev/null || true

log_step "8/9 Configuring Swap (2GB), SSH server, and Dual-Mode Boot"
if [[ "${SKIP_SWAP_CREATE:-0}" != "1" ]]; then
    /usr/local/bin/maialinux-swap.sh create
fi

# Ensure SSH host keys exist and SSH is enabled
ssh-keygen -A >/dev/null 2>&1 || true
echo "${TARGET_USER}:arkos" | chpasswd || true
systemctl enable ssh 2>/dev/null || true

# Install systemd unit for Desktop-First mode and set default to Dual-Mode (EmulationStation)
install -m 644 "$REPO_ROOT/config/systemd/maialinux-desktop.service" /etc/systemd/system/maialinux-desktop.service
systemctl disable maialinux-desktop.service 2>/dev/null || true
systemctl enable emulationstation.service 2>/dev/null || true

log_step "9/9 Running MaiaLinux Health Check"
/usr/local/bin/maialinux-healthcheck.sh
log_info "MaiaLinux installation completed successfully!"
