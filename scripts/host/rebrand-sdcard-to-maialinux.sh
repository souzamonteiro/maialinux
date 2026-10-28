#!/usr/bin/env bash
# rebrand-sdcard-to-maialinux.sh
# Applies all MaiaLinux 2.0.0 configurations to the mounted SD card:
# 1. Main carousel entry for LXQt Desktop in EmulationStation
# 2. EmulationStation wallpaper and theme restoration (es-theme-nes-box)
# 3. System-wide upgrade of references from 1.0.0 to 2.0.0
# 4. Replacement of user-facing dArkOS / ArkOS references with MaiaLinux
# 5. U-Boot and Kernel DRM boot logo/wallpaper installation

set -euo pipefail

FAT_DIR="/media/roberto/dArkOS_Fat"
ROOTFS_DIR="/media/roberto/ROOTFS"
EASYROMS_DIR="/media/roberto/EASYROMS"
REPO_DIR="/home/roberto/projects/maialinux"

echo "=== Verifying mount points ==="
for dir in "$FAT_DIR" "$ROOTFS_DIR" "$EASYROMS_DIR"; do
    if [[ ! -d "$dir" ]]; then
        echo "ERROR: Directory $dir is not mounted!" >&2
        exit 1
    fi
done

echo "=== 1. Setting up EmulationStation Main Carousel Entry for LXQt ==="
# 1a. Create ROM directories in EASYROMS (which mounts at /roms on target)
mkdir -p "$EASYROMS_DIR/maialinux"
mkdir -p "$EASYROMS_DIR/ports"
mkdir -p "$EASYROMS_DIR/tools"

# 1b. Install Launcher script in maialinux, ports, tools, and opt/system
cp -f "$REPO_DIR/scripts/target/start-maialinux.sh" "$EASYROMS_DIR/maialinux/Launch MaiaLinux (LXQt).sh"
cp -f "$REPO_DIR/scripts/target/start-maialinux.sh" "$EASYROMS_DIR/ports/Launch MaiaLinux (LXQt).sh"
cp -f "$REPO_DIR/scripts/target/start-maialinux.sh" "$EASYROMS_DIR/tools/Launch MaiaLinux (LXQt).sh"
cp -f "$REPO_DIR/scripts/target/start-maialinux.sh" "$ROOTFS_DIR/opt/system/Launch MaiaLinux (LXQt).sh"
cp -f "$REPO_DIR/scripts/target/start-maialinux.sh" "$ROOTFS_DIR/opt/system/Tools/Launch MaiaLinux (LXQt).sh"

chmod +x "$EASYROMS_DIR/maialinux/Launch MaiaLinux (LXQt).sh"
chmod +x "$EASYROMS_DIR/ports/Launch MaiaLinux (LXQt).sh"
chmod +x "$EASYROMS_DIR/tools/Launch MaiaLinux (LXQt).sh"
chmod +x "$ROOTFS_DIR/opt/system/Launch MaiaLinux (LXQt).sh"
chmod +x "$ROOTFS_DIR/opt/system/Tools/Launch MaiaLinux (LXQt).sh"

# 1c. Add gamelist.xml for maialinux system
cat > "$EASYROMS_DIR/maialinux/gamelist.xml" << 'EOF'
<?xml version="1.0"?>
<gameList>
	<game>
		<path>./Launch MaiaLinux (LXQt).sh</path>
		<name>Launch MaiaLinux (LXQt Desktop)</name>
		<desc>Start the MaiaLinux 2.0.0 LXQt desktop environment with development tools (Geany IDE, QTerminal, Python 3, C/C++ compiler, Mali GPU acceleration).</desc>
		<image>./maialinux.png</image>
		<releasedate>20261027T000000</releasedate>
		<developer>MaiaLinux Project</developer>
		<publisher>MaiaLinux</publisher>
		<genre>Desktop Environment</genre>
		<players>1</players>
	</game>
</gameList>
EOF

# Copy game icon image
cp -f "$REPO_DIR/images/logo-kernel-rg353-640x480.png" "$EASYROMS_DIR/maialinux/maialinux.png"

# 1d. Add maialinux system into es_systems.cfg if not present
ES_SYSTEMS="$ROOTFS_DIR/etc/emulationstation/es_systems.cfg"
if ! grep -q "<name>maialinux</name>" "$ES_SYSTEMS"; then
    echo "Adding maialinux system to es_systems.cfg..."
    python3 -c "
with open('$ES_SYSTEMS', 'r', encoding='utf-8') as f:
    content = f.read()

target = '<systemList xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">'
replacement = target + '''
	<system>
		<name>maialinux</name>
		<fullname>MaiaLinux Desktop</fullname>
		<path>/roms/maialinux/</path>
		<extension>.sh .SH</extension>
		<command>sudo perfmax %GOVERNOR% %ROM%; %ROM%; sudo perfnorm</command>
		<platform>pc</platform>
		<theme>maialinux</theme>
		<manufacturer>Maia Platform</manufacturer>
		<release>2026</release>
		<hardware>computer</hardware>
	</system>'''

if target in content:
    new_content = content.replace(target, replacement, 1)
    with open('$ES_SYSTEMS', 'w', encoding='utf-8') as f:
        f.write(new_content)
    print('Successfully inserted maialinux system into es_systems.cfg')
else:
    print('ERROR: Target header not found in es_systems.cfg')
"
fi

# 1e. Install maialinux theme into es-theme-nes-box and all other themes on EASYROMS
THEME_SRC="$REPO_DIR/config/emulationstation/maialinux"
for theme_dir in "$EASYROMS_DIR"/themes/*; do
    if [[ -d "$theme_dir" ]]; then
        tname="$(basename "$theme_dir")"
        mkdir -p "$theme_dir/maialinux"
        cp -f "$THEME_SRC/theme.xml" "$theme_dir/maialinux/theme.xml"
        cp -f "$THEME_SRC/system.png" "$theme_dir/maialinux/system.png"
        cp -f "$THEME_SRC/background_icon.png" "$theme_dir/maialinux/background_icon.png"
        echo "Installed maialinux theme into $tname"
    fi
done

echo "=== 2. Restoring MaiaLinux Wallpaper & Fixing Themes Symlink ==="
# Fix broken themes symlink: /home/ark/.emulationstation/themes -> /roms/themes/
ln -sfn /roms/themes/ "$ROOTFS_DIR/home/ark/.emulationstation/themes"

# Copy MaiaLinux wallpapers to es-theme-nes-box
NES_BOX="$EASYROMS_DIR/themes/es-theme-nes-box"
if [[ -d "$NES_BOX" ]]; then
    WP_SRC="$REPO_DIR/config/emulationstation/_inc/images/blue/background.png"
    cp -f "$WP_SRC" "$NES_BOX/_inc/images/background.png"
    cp -f "$WP_SRC" "$NES_BOX/_inc/images/blue/background.png"
    cp -f "$WP_SRC" "$NES_BOX/_inc/images/red/background.png"
    cp -f "$WP_SRC" "$NES_BOX/_inc/images/green/background.png"
    cp -f "$WP_SRC" "$NES_BOX/_inc/images/purple/background.png"
    
    # Also copy layout overlays and xmls
    cp -rf "$REPO_DIR/config/emulationstation/_inc/images/maialinux-4x3" "$NES_BOX/_inc/images/"
    cp -rf "$REPO_DIR/config/emulationstation/_inc/images/maialinux-16x9" "$NES_BOX/_inc/images/"
    cp -f "$REPO_DIR/config/emulationstation/blue.xml" "$NES_BOX/blue.xml"
    cp -f "$REPO_DIR/config/emulationstation/green.xml" "$NES_BOX/green.xml"
    cp -f "$REPO_DIR/config/emulationstation/maialinux-4x3.xml" "$NES_BOX/maialinux-4x3.xml"
    cp -f "$REPO_DIR/config/emulationstation/maialinux-16x9.xml" "$NES_BOX/maialinux-16x9.xml"
    cp -f "$REPO_DIR/config/emulationstation/theme.xml" "$NES_BOX/theme.xml"
fi

# Ensure es_settings.cfg has es-theme-nes-box and blue selected
python3 -c "
cfg = '$ROOTFS_DIR/home/ark/.emulationstation/es_settings.cfg'
with open(cfg, 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if 'name=\"ThemeSet\"' in line:
        new_lines.append('<string name=\"ThemeSet\" value=\"es-theme-nes-box\" />\n')
    elif 'name=\"subset.Color\"' in line:
        new_lines.append('<string name=\"subset.Color\" value=\"blue\" />\n')
    else:
        new_lines.append(line)

with open(cfg, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
print('Verified es_settings.cfg theme and color')
"

echo "=== 3. Updating System Version to MaiaLinux 2.0.0 ==="
# Desktop shortcuts
for df in "$ROOTFS_DIR/home/ark/Desktop"/*.desktop; do
    if [[ -f "$df" ]]; then
        sed -i 's/MaiaLinux 1\.0\.0/MaiaLinux 2.0.0/g' "$df"
    fi
done

echo "=== 4. Replacing dArkOS / ArkOS with MaiaLinux ==="
# 4a. Scripts in opt/system/Advanced
if [[ -f "$ROOTFS_DIR/opt/system/Advanced/Backup dArkOS Settings.sh" ]]; then
    mv -f "$ROOTFS_DIR/opt/system/Advanced/Backup dArkOS Settings.sh" "$ROOTFS_DIR/opt/system/Advanced/Backup MaiaLinux Settings.sh"
fi
if [[ -f "$ROOTFS_DIR/opt/system/Advanced/Restore dArkOS Settings.sh" ]]; then
    mv -f "$ROOTFS_DIR/opt/system/Advanced/Restore dArkOS Settings.sh" "$ROOTFS_DIR/opt/system/Advanced/Restore MaiaLinux Settings.sh"
fi

if [[ -f "$ROOTFS_DIR/opt/system/Advanced/Backup MaiaLinux Settings.sh" ]]; then
    sed -i 's/dArkOS/MaiaLinux/g; s/ArkOS/MaiaLinux/g' "$ROOTFS_DIR/opt/system/Advanced/Backup MaiaLinux Settings.sh"
fi
if [[ -f "$ROOTFS_DIR/opt/system/Advanced/Restore MaiaLinux Settings.sh" ]]; then
    sed -i 's/dArkOS/MaiaLinux/g; s/ArkOS/MaiaLinux/g' "$ROOTFS_DIR/opt/system/Advanced/Restore MaiaLinux Settings.sh"
fi

# 4b. Network Info and System Info
sed -i 's/dArkOS/MaiaLinux/g' "$ROOTFS_DIR/opt/system/Network Info.sh" 2>/dev/null || true
sed -i 's/dArkOS/MaiaLinux/g' "$ROOTFS_DIR/opt/system/System Info.sh" 2>/dev/null || true

# 4c. expandtoexfat.sh on FAT partition
sed -i 's/Firstboot setup of dArkOS/Firstboot setup of MaiaLinux 2.0.0/g; s/load dArkOS/load MaiaLinux 2.0.0/g' "$FAT_DIR/expandtoexfat.sh" 2>/dev/null || true

# 4d. BaRT Recovery Menu inside emulationstation.sh
sed -i 's/Backup dArkOS Settings/Backup MaiaLinux Settings/g; s/Restore dArkOS Settings/Restore MaiaLinux Settings/g' "$ROOTFS_DIR/usr/bin/emulationstation/emulationstation.sh"

echo "=== 5. U-Boot and Kernel DRM Boot Splash & Resource Installation ==="
# Copy BMP files and resource.img to FAT boot partition
cp -f "$REPO_DIR/config/boot/logo.bmp" "$FAT_DIR/logo.bmp"
cp -f "$REPO_DIR/config/boot/logo_kernel.bmp" "$FAT_DIR/logo_kernel.bmp"
cp -f "$REPO_DIR/config/boot/resource.img" "$FAT_DIR/resource.img"

# 5b. Update emulationstation.sh boot hook to execute full branding and resource flashing on next boot
python3 -c "
es_sh = '$ROOTFS_DIR/usr/bin/emulationstation/emulationstation.sh'
with open(es_sh, 'r', encoding='utf-8') as f:
    text = f.read()

# Replace or insert rebranding hook
hook_header = '# MaiaLinux 2.0.0 One-time Finalization Hook'
new_hook = '''# MaiaLinux 2.0.0 One-time Finalization Hook
if [ ! -f /etc/maialinux-2.0.0-rebrand-done ]; then
  sudo touch /etc/maialinux-2.0.0-rebrand-done 2>/dev/null || true
  sudo cp -f \"/opt/system/Launch MaiaLinux (LXQt).sh\" /usr/local/bin/start-maialinux.sh 2>/dev/null || true
  sudo cp -f \"/opt/system/Switch Boot Mode.sh\" /usr/local/bin/switch-boot-mode.sh 2>/dev/null || true
  sudo cp -f \"/opt/system/Switch Wallpaper.sh\" /usr/local/bin/maialinux-wallpaper.sh 2>/dev/null || true
  sudo chown -R ark:ark /home/ark 2>/dev/null || true
  sudo hostnamectl set-hostname maialinux-rg353v 2>/dev/null || true
  sudo sed -i 's/^NAME=.*/NAME=\"MaiaLinux\"/' /etc/os-release 2>/dev/null || true
  sudo sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME=\"MaiaLinux 2.0.0\"/' /etc/os-release 2>/dev/null || true
  sudo sed -i 's/^VERSION=.*/VERSION=\"2.0.0 (trixie)\"/' /etc/os-release 2>/dev/null || true
  echo \"MaiaLinux 2.0.0 (Debian 13 Trixie / Kernel 5.10)\" | sudo tee /etc/maialinux-release >/dev/null 2>&1 || true
  echo -e \"MaiaLinux 2.0.0 (Debian 13 trixie) \\\\n \\\\l\\\\n\" | sudo tee /etc/issue /etc/issue.net >/dev/null 2>&1 || true
  sudo plymouth-set-default-theme maialinux 2>/dev/null || true
  sudo systemctl enable ssh 2>/dev/null || true
  sudo /usr/local/bin/maialinux-swap.sh enable 2>/dev/null || true
  mkdir -p /roms/maialinux 2>/dev/null || true
  cp -f \"/opt/system/Launch MaiaLinux (LXQt).sh\" \"/roms/maialinux/Launch MaiaLinux (LXQt).sh\" 2>/dev/null || true
  chmod +x \"/roms/maialinux/Launch MaiaLinux (LXQt).sh\" 2>/dev/null || true
  ln -sfn /roms/themes /home/ark/.emulationstation/themes 2>/dev/null || true
  # Boot resource partition preserved safely without dangerous overwrites
  # MOTD
  printf '\\nWelcome to MaiaLinux 2.0.0\\nBased on Debian 13 (Trixie) & Kernel 5.10 LTS (%s %s)\\n\\n' \"\$(uname -o)\" \"\$(uname -rm)\" | sudo tee /etc/update-motd.d/00-header >/dev/null 2>&1 || true
  printf '\\n * MaiaLinux Project:           https://github.com/roberto/maialinux\\n * Debian Documentation:        https://www.debian.org/doc/\\n\\n' | sudo tee /etc/update-motd.d/10-help-text >/dev/null 2>&1 || true
  sudo chmod +x /etc/update-motd.d/* 2>/dev/null || true
fi'''

import re
pattern = r'# MaiaLinux 2\.0\.0 One-time Finalization Hook\nif \[ ! -f /etc/maialinux-2\.0\.0-finalized \]; then.*?fi'
if re.search(pattern, text, re.DOTALL):
    text = re.sub(pattern, lambda m: new_hook, text, flags=re.DOTALL)
    print('Replaced existing finalization hook with comprehensive rebranding hook')
else:
    print('Inserting after splash hook...')
    target = 'if [ -x /etc/maialinux-runtime/maialinux-boot-setup.sh ]; then\n  sudo /etc/maialinux-runtime/maialinux-boot-setup.sh --boot-splash >/dev/null 2>&1 || true\nfi'
    text = text.replace(target, target + '\n\n' + new_hook, 1)

with open(es_sh, 'w', encoding='utf-8') as f:
    f.write(text)
"

echo "=== Synchronizing disks ==="
sync
echo "=== MaiaLinux 2.0.0 rebranding and carousel integration complete! ==="
