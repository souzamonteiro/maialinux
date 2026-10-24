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

log_step "1/9 Backing up MaiaLinux base Mali Bifrost G52 GPU drivers"
mkdir -p /opt/maialinux /etc/maialinux
install -m 755 "$REPO_ROOT/scripts/target/fix-mali-symlinks.sh" /usr/local/bin/fix-mali-symlinks.sh
/usr/local/bin/fix-mali-symlinks.sh --backup

# Remove base-image dpkg path-exclude on /usr/lib/{aarch64-linux-gnu,arm-linux-gnueabihf} if present
# so dev libraries and headers unpack cleanly; fix-mali-symlinks.sh restores Mali blobs afterwards.
if [[ -f /etc/dpkg/dpkg.cfg.d/excludes ]]; then
    mv /etc/dpkg/dpkg.cfg.d/excludes /opt/maialinux/dpkg-excludes.bak
fi

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

log_step "3/9 Resolving base-system libmali / libwayland-egl1 dpkg conflict"
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

# Base image strips /usr/include/* while leaving *-dev packages marked as installed.
# Detect any installed *-dev package with missing /usr/include headers and reinstall it.
log_info "Checking for stripped /usr/include headers from base image..."
MISSING_HEADER_PKGS=()
for pkg in $(dpkg-query -W -f='${Package}\n' '*-dev' 2>/dev/null); do
    while IFS= read -r hdr; do
        if [[ -n "$hdr" && ! -e "$hdr" ]]; then
            MISSING_HEADER_PKGS+=("$pkg")
            break
        fi
    done < <(dpkg -L "$pkg" 2>/dev/null | grep '^/usr/include/')
done

if [[ ${#MISSING_HEADER_PKGS[@]} -gt 0 ]]; then
    log_info "Restoring stripped headers for ${#MISSING_HEADER_PKGS[@]} -dev packages..."
    apt-get install -y --reinstall "${MISSING_HEADER_PKGS[@]}"
fi

# Ensure display managers (lightdm/sddm/gdm) are disabled so they don't fight EmulationStation
for dm in lightdm sddm gdm gdm3 lxdm; do
    systemctl disable "$dm" 2>/dev/null || true
    systemctl stop "$dm" 2>/dev/null || true
done

log_step "5/9 Restoring MaiaLinux base Mali Bifrost G52 GPU drivers and fixing library symlinks"
/usr/local/bin/fix-mali-symlinks.sh --restore

log_step "6/9 Installing Xorg, LXQt (640x480), Openbox, Geany, and Controller configurations"
mkdir -p /etc/X11/xorg.conf.d
rm -f /etc/X11/xorg.conf /etc/X11/xorg.conf.d/10-modesetting.conf /etc/X11/xorg.conf.d/10-fbdev.conf
install -m 644 "$REPO_ROOT/config/xorg/10-rockchip-modesetting.conf" /etc/X11/xorg.conf.d/10-rockchip-modesetting.conf
install -m 644 "$REPO_ROOT/config/xorg/20-touchscreen.conf" /etc/X11/xorg.conf.d/20-touchscreen.conf
install -m 644 "$REPO_ROOT/config/xorg/Xwrapper.config" /etc/X11/Xwrapper.config

# Install controller mapping for desktop
install -m 644 "$REPO_ROOT/config/controls/desktop.gptk" /etc/maialinux/desktop.gptk
rm -f /etc/systemd/logind.conf.d/maialinux-powerkey.conf 2>/dev/null || true

# Install target management & launcher scripts
install -Dm755 "$REPO_ROOT/scripts/target/maialinux-start-es.sh" /usr/local/bin/maialinux-start-es.sh
install -Dm644 "$REPO_ROOT/config/systemd/emulationstation.service.d/maialinux.conf" /etc/systemd/system/emulationstation.service.d/maialinux.conf
install -m 755 "$REPO_ROOT/config/keyboard/maialinux-keyboard-toggle" /usr/local/bin/maialinux-keyboard-toggle
install -m 755 "$REPO_ROOT/scripts/target/maialinux-swap.sh" /usr/local/bin/maialinux-swap.sh
install -m 755 "$REPO_ROOT/scripts/target/start-maialinux.sh" /usr/local/bin/start-maialinux.sh
install -m 755 "$REPO_ROOT/scripts/target/maialinux-return-to-es" /usr/local/bin/maialinux-return-to-es
install -m 755 "$REPO_ROOT/scripts/target/switch-boot-mode.sh" /usr/local/bin/switch-boot-mode.sh
install -m 755 "$REPO_ROOT/scripts/target/maialinux-wallpaper.sh" /usr/local/bin/maialinux-wallpaper.sh
install -m 755 "$REPO_ROOT/scripts/target/maialinux-boot-setup.sh" /usr/local/bin/maialinux-boot-setup.sh
install -m 755 "$REPO_ROOT/scripts/target/maialinux-healthcheck.sh" /usr/local/bin/maialinux-healthcheck.sh

# Install EmulationStation Tools menu entries (both /roms/tools and /opt/system/Tools)
for tools_dir in /roms/tools /opt/system/Tools; do
    mkdir -p "$tools_dir"
    install -m 755 "$REPO_ROOT/scripts/target/start-maialinux.sh" "$tools_dir/Launch-MaiaLinux-LXQt.sh"
    install -m 755 "$REPO_ROOT/scripts/target/switch-boot-mode.sh" "$tools_dir/Switch-Boot-Mode.sh"
    install -m 755 "$REPO_ROOT/scripts/target/maialinux-wallpaper.sh" "$tools_dir/Switch-Wallpaper-4x3-HDMI.sh"
done

# Install Wallpapers (640x480 4:3 and 1920x1080 16:9 HDMI), Boot Splash, Plymouth & EmulationStation themes
mkdir -p /etc/maialinux-runtime/wallpapers \
         /etc/maialinux-runtime/boot \
         /etc/maialinux-runtime/plymouth \
         /etc/maialinux-runtime/emulationstation \
         /usr/share/backgrounds/maialinux \
         "$TARGET_HOME/Pictures/Wallpapers"
cp -rf "$REPO_ROOT/config/wallpapers/"*.png /etc/maialinux-runtime/wallpapers/
cp -rf "$REPO_ROOT/images/"*.png /etc/maialinux-runtime/wallpapers/ 2>/dev/null || true
cp -f "$REPO_ROOT/config/wallpapers/MaiaLinux_at_Neon_Twilight_640x480.png" /etc/maialinux-runtime/wallpaper.png
cp -rf "$REPO_ROOT/config/boot/"* /etc/maialinux-runtime/boot/
cp -rf "$REPO_ROOT/config/plymouth/"* /etc/maialinux-runtime/plymouth/
cp -rf "$REPO_ROOT/config/emulationstation/"* /etc/maialinux-runtime/emulationstation/
if [[ -d /roms/launchimages ]]; then
    [[ ! -f /roms/launchimages/loading.jpg.orig && -f /roms/launchimages/loading.jpg ]] && cp -f /roms/launchimages/loading.jpg /roms/launchimages/loading.jpg.orig
    cp -f "$REPO_ROOT/config/boot/loading.jpg" /roms/launchimages/loading.jpg
    cp -f "$REPO_ROOT/config/boot/loading-640x480.jpg" /roms/launchimages/loading-640x480.jpg
    cp -f "$REPO_ROOT/config/boot/loading-1920x1080.jpg" /roms/launchimages/loading-1920x1080.jpg
fi
/usr/local/bin/maialinux-boot-setup.sh || true

# Configure user 'ark' groups
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
install -m 755 "$REPO_ROOT/config/desktop-entries/maialinux-wallpaper.desktop" /usr/local/share/applications/maialinux-wallpaper.desktop
install -m 755 "$REPO_ROOT/config/desktop-entries/return-to-es.desktop" /usr/local/share/applications/return-to-es.desktop

log_step "7/9 Installing & compiling starter development projects in ~/projects"
cp -rf "$REPO_ROOT/examples/"* "$TARGET_HOME/projects/"

make -C "$TARGET_HOME/projects/hello-c" clean all
make -C "$TARGET_HOME/projects/hello-sdl2" clean all

chown -R "${TARGET_UID}:${TARGET_GID}" "$TARGET_HOME/.config" "$TARGET_HOME/Desktop" "$TARGET_HOME/projects" /roms/tools /opt/system/Tools 2>/dev/null || true

log_step "8/9 Configuring Swap (2GB), SSH server, and Dual-Mode Boot"
if [[ "${SKIP_SWAP_CREATE:-0}" != "1" ]]; then
    /usr/local/bin/maialinux-swap.sh create
fi

ssh-keygen -A >/dev/null 2>&1 || true
echo "${TARGET_USER}:arkos" | chpasswd || true
systemctl enable ssh 2>/dev/null || true
install -m 644 "$REPO_ROOT/config/systemd/maialinux-desktop.service" /etc/systemd/system/maialinux-desktop.service
systemctl disable maialinux-desktop.service 2>/dev/null || true
systemctl enable emulationstation.service 2>/dev/null || true

log_step "9/9 Running MaiaLinux Health Check"
/usr/local/bin/maialinux-healthcheck.sh
log_info "MaiaLinux installation completed successfully!"
