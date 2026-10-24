# MaiaLinux for Anbernic RG353V

![MaiaLinux](<images/MaiaLinux_ Play_Explore_and_Customize.png>)

**MaiaLinux** is a reproducible Linux desktop and software development distribution layer built on top of **ArkOS (Ubuntu 19.10 Eoan ARM64)** for the **Anbernic RG353V (Rockchip RK3566)** handheld gaming console.

It transforms the RG353V into a complete **pocket Linux computer** featuring **LXQt**, an **On-Screen Virtual Keyboard (Touchscreen + Gamepad)**, **Geany IDE**, **QTerminal**, and **full C/C++, Python 3, SDL2, GTK3, and Qt5 development toolchains**, while preserving **100% compatibility with EmulationStation, RetroArch, and Mali Bifrost G52 GPU hardware acceleration**.

> 📄 See [**RELEASE_NOTES.md**](RELEASE_NOTES.md) for full details on the `v1.0.0` release artifacts.

---

## Key Features

- **Dual-Mode Architecture (Gaming + Software Development)**:
  - Boots into **EmulationStation** by default and lets you launch the **LXQt** desktop at any time from `Options -> Tools -> Launch-MaiaLinux-LXQt`.
  - Includes `Switch-Boot-Mode.sh` (available in the `Tools` menu or via CLI) to toggle between booting into EmulationStation (`es`) or booting directly into the LXQt Desktop (`desktop`).
- **Tailored for Both 640×480 (3.5" IPS 4:3) and 1920×1080 (HDMI 16:9)**:
  - **Custom Bootloader, Kernel DRM & Plymouth Splash**: Packs `logo.bmp` and `logo_kernel.bmp` into the Rockchip `resource` partition (`resource.img` via `resource_tool`) and installs a resolution-aware **Plymouth** graphical boot theme (`4:3` and `16:9` auto-detection), plus MaiaLinux launch splash images (`/roms/launchimages/loading.jpg`).
  - **LXQt & EmulationStation Wallpapers (`4:3` & `16:9` HDMI)**: Includes **MaiaLinux at Neon Twilight** wallpapers for both the built-in `640×480` display and `1920×1080` HDMI output, with automatic HDMI detection on desktop launch and one-click switching (`Wallpaper (4:3 / HDMI)` on the desktop or `Options -> Tools -> Switch-Wallpaper-4x3-HDMI` in EmulationStation).
  - **Compact 640×480 UI**: `24px` single bottom LXQt panel, crisp `8pt/9pt` typography, Catppuccin/Fusion dark theme, and maximized window geometry.
- **Virtual Keyboard + Touchscreen + Physical Gamepad Controls (`gptokeyb`)**:
  - **Touchscreen**: Native multi-touch support via `libinput` (tap to click and type on the on-screen keyboard).
  - **Virtual Keyboard (`matchbox-keyboard` / `onboard`)**: Docked cleanly at the bottom of the screen (`640×160`, `y=296`) with no titlebar; open from the LXQt application menu/panel launcher.
  - **Desktop Gamepad Mapping**:
    - **Left Analog Stick**: Mouse Cursor
    - **L1 / A Button**: Left Mouse Click
    - **R1 / B Button**: Right Mouse Click
    - **Terminal**: Open from panel icon or with `F10`
    - **D-Pad / Right Analog Stick**: Arrow Keys (navigate code and menus)
    - **Start**: Enter | **X**: Backspace | **L2 / R2**: PageUp / PageDown
- **Surgical Mali G52 GPU Preservation (`libmali-bifrost-g52-g2p0-gbm.so`) + Wayland-EGL GTK3 Fix**:
  - Automatically resolves the stock ArkOS `libmali-rk-bifrost-g31-rxp0-wayland-gbm` vs. `libwayland-egl1` package conflict, keeping `libMali.so`, `libEGL.so.1`, `libGLESv2.so.2`, and `libgbm.so.1` pointed to the Mali Bifrost G52 GBM driver for EmulationStation/RetroArch while providing Mesa's `libwayland-egl.so.1` so GTK3 applications (`Geany`, `Onboard`) run cleanly under X11.
  - Restores `/usr/include` development headers stripped from the stock ArkOS base image so native C/C++/SDL2 compilation works out of the box on the handheld.
- **Pre-Installed Development Stack**:
  - **C/C++ & System**: `gcc`, `g++`, `make`, `cmake`, `gdb`, `git`, `pkg-config`, `tmux`, `htop`, `openssh-server`
  - **Python 3**: `python3`, `pip`, `venv`, `tkinter`, `pygame`, `evdev`
  - **Graphics & Game Dev Libraries**: `libsdl2-dev` (`image`, `mixer`, `ttf`, `gfx`, `net`), `libgtk-3-dev`, `qtbase5-dev`, `mesa-utils`
  - **IDEs & Editors**: `Geany` (pre-configured for `640×480`), `FeatherPad`, `Vim`, `Nano`
  - **Starter Projects in `~/projects`**: `hello-c`, `hello-sdl2`, `hello-python-tk`, `hello-pygame`

---

## Quick Start for End Users (Project Site / GitHub Releases)

The compiled, ready-to-install MaiaLinux distribution for the RG353V and the QEMU-ready desktop image are available from the official project site: https://apps.maiaplatform.org/maialinux

> The compiled distribution, ready to be installed on the device and executed in QEMU, can be downloaded from this site.

Download the pre-built release artifacts from the [**GitHub Releases**](../../releases) page (or generate them locally into `distro/` with `make build-distro`):

- **`MaiaLinux-RG353V-v1.0.0-sdcard.img.xz`** — Flashable microSD Card Image for the Anbernic RG353V
- **`MaiaLinux-RG353V-v1.0.0-qemu.qcow2`** — Compressed ARM64 QEMU Image for testing on a PC

### 1. Flashing to a microSD Card (Anbernic RG353V)

1. *(Optional)* Verify the SHA-256 checksum:
   ```bash
   sha256sum -c MaiaLinux-RG353V-v1.0.0-sdcard.img.xz.sha256
   ```
2. Flash **`MaiaLinux-RG353V-v1.0.0-sdcard.img.xz`** to a microSD card (**32GB or larger**, Samsung/SanDisk recommended):
   - **GUI (Windows / macOS / Linux)**: Open [**BalenaEtcher**](https://etcher.balena.io/) or [**Raspberry Pi Imager**](https://www.raspberrypi.com/software/), select `MaiaLinux-RG353V-v1.0.0-sdcard.img.xz` directly (no need to extract first), choose your microSD card, and click **Flash**.
   - **Linux CLI**:
     ```bash
     xzcat MaiaLinux-RG353V-v1.0.0-sdcard.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
     sync
     ```
     *(Replace `/dev/sdX` or `/dev/mmcblkX` with your microSD card block device).*
3. Insert the microSD card into the **TF1/INT** (top) slot of your Anbernic RG353V and power it on. The image provides a 16 GiB root filesystem and preserves the original RG353V boot resources. Extra card capacity remains available for a separately planned partition expansion; boot never rewrites the partition layout automatically.

### 2. Running the QEMU Image on a PC

On Ubuntu hosts, AppArmor may block Bubblewrap with `setting up uid map: Permission denied`.
Inspect the kernel log before changing host policy. The optional
`scripts/host/setup-qemu-userns.sh` installs `config/apparmor/maialinux-bwrap` for
`/usr/bin/bwrap`; it requires explicit administrator approval because the permission
applies to all invocations of that executable. The global restriction remains enabled.

Use the graphical ARM64 desktop simulator on an x86_64 Linux PC as your logged-in desktop user, without `sudo`:

- **Option A — 640×480 Graphical LXQt Desktop Simulator (`qemu-aarch64-static` + `bwrap` + `Xephyr`)**:
  Install host prerequisites (`sudo apt install qemu-user-static bubblewrap xserver-xephyr x11-utils libguestfs-tools`) and run:
  ```bash
  # Using a mounted SD card or extracted rootfs:
  make test-qemu

  # Or directly from distro/MaiaLinux-RG353V-v1.0.0-qemu.qcow2:
  ./scripts/host/run-qemu-image.sh --gui
  ```
Full-system `--vm` is experimental and requires an explicit `KERNEL_IMG` built for
QEMU's ARM64 `virt` machine, plus an appropriate optional `INITRD_IMG`. The handheld's
Rockchip kernel in `distro/Image` is not the VM kernel. The distributed QCOW2 is a
root filesystem for the `--gui` simulator; it is not a self-booting VM disk.
Distribute `qemu-support/` alongside the QCOW2 and `run-maialinux-qemu.sh`.

Release images reserve a 16 GiB root partition and require a card of at least 32 GB.
Free card capacity beyond the image does not automatically mean free root filesystem
space. Inspect `lsblk` and `df -h /` separately before allocating swap.

---

## Building from Source / Customizing

### Option 1: Build Both `distro/` Release Images (`sdcard.img.xz` + `qemu.qcow2`)

```bash
make build-distro
```
Generates `distro/MaiaLinux-RG353V-v1.0.0-sdcard.img.xz`, `distro/MaiaLinux-RG353V-v1.0.0-qemu.qcow2`, and their `.sha256` checksum files entirely in user-space.

### Reproducible Release Automation (Recommended)

Use the automated pipeline that fetches upstream inputs, stages vendor runtime libraries, rebuilds the RG353V kernel bundle, and emits release artifacts in `distro/`:

```bash
make build-release \
  ARKOS_IMAGE_URL="https://<upstream>/ArkOS_RG353V_*.img.xz" \
  ROOTFS=/media/$USER/root1
```

Detailed release engineering instructions are in:

- `docs/REPRODUCIBLE_DISTRIBUTION.md`

### Option 2: Install Directly onto a Mounted ArkOS SD Card

```bash
make install-sdcard SDCARD_ROOT=/media/$USER/root
```

### Option 3: Install Live on the RG353V Console over SSH

```bash
scp -r . ark@<RG353V_IP>:/tmp/maialinux
ssh ark@<RG353V_IP> "sudo /tmp/maialinux/install-on-device.sh"
```

### Option 4: Build and Deploy the Correct RG353V Kernel 4 Bundle (Recommended)

Use this to build the compatible RG353V kernel line (`4.19.172`) as a full bundle (`Image + rk3566.dtb + modules`) and deploy safely with rollback.

```bash
# Build kernel bundle in distro/kernel-rg353v-4.19.172
make build-kernel4-bundle

# Deploy bundle to mounted BOOT1/root1 with backup + rollback
make deploy-kernel4-bundle
```

The build script writes:
- `distro/kernel-rg353v-4.19.172/Image`
- `distro/kernel-rg353v-4.19.172/rk3566.dtb`
- `distro/kernel-rg353v-4.19.172/modules-<kernel_release>.tar.xz`
- metadata files (`Image.meta`, `bundle.meta`) for traceability.

### Option 5: Build RK3566 Kernel Image with Custom Early Boot Logo (Legacy Image-Only Flow)

This legacy flow builds only `Image` and is still available for experimentation.

```bash
# Default MaiaLinux assets (LCD + HDMI):
make build-logo-image

# Custom assets:
./scripts/host/build-rk3566-image-with-logo.sh \
  --logo images/logo-kernel-rg353-640x480.png \
  --update-hdmi yes \
  --hdmi-logo images/logo-kernel-hdmi-1280x720.png \
  --output distro/Image
```

Notes:
- The script accepts local file paths and URLs for logo sources.
- For first run on a fresh host, add `--install-deps` to install required packages.
- The generated Image can be copied to BOOT1 after backing up the current one.

Monitor build progress:

```bash
# One-shot status
make monitor-logo-build

# Live log tail
./scripts/host/monitor-rk3566-logo-build.sh --watch
```

Safe deploy to BOOT1 with backup + rollback:

```bash
make deploy-logo-image
```

Or directly:

```bash
./scripts/host/deploy-boot1-image-safe.sh distro/Image /media/$USER/BOOT1
```

The script creates `backups/boot-YYYYmmdd-HHMMSS/Image.before` and restores it automatically if verification fails.
If `distro/Image.meta` exists, the deploy script checks kernel/module compatibility against `root1/lib/modules` and blocks incompatible deploys by default.

Keep current kernel and update only boot/splash images:

```bash
make update-logo-only
```

This updates only `logo.bmp`, `logo_kernel.bmp`, and `loading.jpg` on mounted media and does not modify `BOOT1/Image`.

---

## Usage on the Console (Anbernic RG353V)

1. **Launch the LXQt Desktop**:
   - In EmulationStation, navigate to **Options** -> **Tools** -> **Launch-MaiaLinux-LXQt**.
2. **Switch Boot Mode (EmulationStation vs. Direct Desktop Boot)**:
   - Navigate to **Options** -> **Tools** -> **Switch-Boot-Mode**, or run in a terminal:
     ```bash
     sudo switch-boot-mode.sh desktop   # Boot directly into LXQt on power-on
     sudo switch-boot-mode.sh es        # Boot into EmulationStation (Dual-Mode)
     ```
3. **Switch Wallpapers Between 4:3 (640×480) and 16:9 (1920×1080 HDMI)**:
   - Automatic detection runs on every LXQt startup (`maialinux-wallpaper.sh auto`).
  - To toggle manually, select **Options** -> **Tools** -> **Switch-Wallpaper-4x3-HDMI** in EmulationStation, or change **Theme Color** in EmulationStation (`Start -> UI Settings -> Theme Configuration -> Theme Color`) between `MaiaLinux Neon (640x480 4:3)` and `MaiaLinux Neon (1920x1080 HDMI)`.
4. **Return to Gaming (EmulationStation)**:
  - Select `Maia -> Leave -> Logout` from the bottom-left panel menu.
5. **Run the System Health Check**:
   ```bash
   maialinux-healthcheck.sh
   ```

6. **Tune Gamepad Cursor Speed (LXQt)**:
   - Edit `/etc/maialinux/desktop.gptk` and adjust these two values:
     - `mouse_scale` (higher = faster cursor movement)
     - `mouse_delay` (higher = slower update cadence)
   - MaiaLinux defaults are conservative for handheld use:
     - `mouse_scale = 220`
     - `mouse_delay = 18`

---

## Repository Structure

```text
maialinux/
├── Makefile                        # Automation: build-distro, test-qemu, run-qemu-vm, install-sdcard
├── README.md                       # Documentation & User Guide (English)
├── RELEASE_NOTES.md                # Release Notes for GitHub Releases (v1.0.0)
├── install-on-device.sh            # Idempotent installer executed inside the ARM64 rootfs
├── distro/                         # (gitignored) Built SD Card (.img.xz) & QEMU (.qcow2) release images
├── images/                         # Official MaiaLinux artwork (4:3 640x480 and 16:9 1920x1080)
├── config/
│   ├── boot/                       # Rockchip resource.img, U-Boot/Kernel BMP logos & launch splash
│   ├── plymouth/                   # Graphical Plymouth boot theme (auto 4:3 & 16:9 HDMI)
│   ├── wallpapers/                 # Optimized 640x480, 1280x720, and 1920x1080 PNG wallpapers
│   ├── emulationstation/           # EmulationStation NES-Box theme customizations (4:3 & 16:9 HDMI)
│   ├── xorg/                       # Rockchip DRM modesetting (Glamor off), Touchscreen & Xwrapper
│   ├── lxqt/                       # LXQt + Openbox + PCManFM-Qt profile tuned for 640x480
│   ├── keyboard/                   # Virtual keyboard launcher/toggle script
│   ├── controls/                   # gptokeyb profile (desktop.gptk) for the RG353V gamepad
│   ├── geany/                      # Geany IDE configuration for 640x480
│   ├── desktop-entries/            # Application menu launchers
│   └── systemd/                    # maialinux-desktop.service systemd unit
├── scripts/
│   ├── host/                       # Host PC scripts (build-distro-releases.py, run-qemu-image.sh, test-qemu-desktop.sh)
│   └── target/                     # Target scripts installed on RG353V (/usr/local/bin & /roms/tools)
└── examples/                       # Starter projects (C, SDL2, Python Tkinter, Pygame)
```

---

## License

Distributed under the MIT License. See [`LICENSE`](LICENSE) for details.
