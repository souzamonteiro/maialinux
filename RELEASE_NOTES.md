# MaiaLinux v1.0.0 — Pocket Linux Desktop & Dev Environment for Anbernic RG353V

**MaiaLinux v1.0.0** is the first official release of MaiaLinux for the **Anbernic RG353V** (Rockchip RK3566), built on top of **ArkOS 2.0 (Ubuntu 19.10 Eoan ARM64)**.

It turns the RG353V into a complete **Dual-Mode Handheld Gaming Console + Linux Development Workstation** featuring **LXQt**, an **On-Screen Virtual Keyboard**, **Geany IDE**, **QTerminal**, and native **C/C++, Python 3, SDL2, GTK3, and Qt5** development toolchains while keeping 100% of ArkOS's EmulationStation, RetroArch, and Mali Bifrost G52 GPU acceleration intact.

---

## 📦 Release Artifacts (`distro/`)

The compiled MaiaLinux distribution, ready to install on the RG353V device and to run in QEMU, is also available for download from the official MaiaLinux project site: https://apps.maiaplatform.org/maialinux

| File | Description | Target |
| :--- | :--- | :--- |
| **`MaiaLinux-RG353V-v1.0.0-sdcard.img.xz`** | Flashable GPT SD Card image (compressed with `xz`). 16 GiB root filesystem; requires a microSD card of at least 32 GB. | **Anbernic RG353V (TF1/INT slot)** |
| **`MaiaLinux-RG353V-v1.0.0-sdcard.img.xz.sha256`** | SHA-256 checksum for the SD Card image. | Verification |
| **`MaiaLinux-RG353V-v1.0.0-qemu.qcow2`** | Compressed QCOW2 ARM64 root filesystem image for QEMU testing and emulation on a PC. | **Linux ARM64 desktop simulator** |
| **`MaiaLinux-RG353V-v1.0.0-qemu.qcow2.sha256`** | SHA-256 checksum for the QEMU image. | Verification |
| **`MaiaLinux-RG353V-v1.0.0-qemu-launcher.tar.xz`** | Runner and support files; extract beside the QCOW2 image. | Linux desktop simulator |

---

## ✨ What's Included in v1.0.0

### 1. Dual-Mode Boot (EmulationStation + LXQt Desktop)
- Boots into **EmulationStation** by default and allows launching the **LXQt** desktop at any time via **Options → Tools → Launch-MaiaLinux-LXQt**.
- Switch boot modes anytime via **Options → Tools → Switch-Boot-Mode** or `sudo switch-boot-mode.sh [desktop|es]`.
- Return seamlessly from LXQt to EmulationStation using the **Return to Gaming (ES)** desktop shortcut.

### 2. Custom Bootloader, Plymouth & Dual-Resolution Wallpapers (4:3 & 16:9 HDMI)
- **Original RG353V boot resources**: Preserves the base ArkOS resource partition and boot arguments. Desktop launch never flashes boot resources automatically.
- **Resolution-Aware Plymouth Boot Theme**: Automatically detects `4:3` (`640×480` internal DSI display) vs. `16:9` (`1280×720` / `1920×1080` HDMI output).
- **EmulationStation & LXQt Themes**: Includes both `4:3 (640×480)` and `16:9 (1920×1080 HDMI)` **MaiaLinux at Neon Twilight** wallpapers, with automatic HDMI detection on LXQt launch and one-click switching (`Wallpaper (4:3 / HDMI)` on the desktop or `Options → Tools → Switch-Wallpaper-4x3-HDMI`).

### 3. Ergonomic 640×480 UI + Touchscreen + Physical Gamepad Controls
- **Virtual Keyboard (`matchbox-keyboard` & `onboard`)**: Docked cleanly at the bottom of the `640×480` screen (`640×160`) without covering the active editor; toggle anytime via **Select** / **Y** (`F12`) or the panel icon.
- **Gamepad Mouse & Keyboard Emulation (`gptokeyb`)**:
  - **Left Stick**: Mouse Cursor | **L1 / A**: Left Click | **R1 / B**: Right Click
  - **Select / Y**: Toggle Virtual Keyboard (`F12`) | **R3**: Open Terminal (`F10`)
  - **D-Pad / Right Stick**: Arrow Keys | **Start**: Enter | **X**: Backspace | **L3**: Esc | **L2 / R2**: PageUp / PageDown

### 4. Complete On-Device Development Stack
- **C / C++ & System**: `gcc 9.2.1`, `g++`, `make`, `cmake`, `gdb`, `git`, `pkg-config`, `tmux`, `htop`, `openssh-server` (with full `/usr/include` headers restored).
- **Python 3**: `python3 3.7.5`, `pip`, `venv`, `python3-tk` (Tkinter), `python3-pygame` (Pygame 1.9.6), `python3-evdev`.
- **Graphics & Game Libraries**: `libsdl2-dev` (`SDL2`, `SDL2_image`, `SDL2_mixer`, `SDL2_ttf`, `SDL2_gfx`, `SDL2_net`), `libgtk-3-dev`, `qtbase5-dev`.
- **IDEs & Editors**: `Geany` (configured for `640×480`), `FeatherPad`, `Vim`, `Nano`.
- **Starter Projects (`/home/ark/projects`)**: Pre-loaded `hello-c`, `hello-sdl2`, `hello-python-tk`, and `hello-pygame` examples.
- **2GB Swapfile**: Automatically managed by `maialinux-swap.sh` so heavy C++/Qt5/CMake builds never run out of RAM on the 1GB/2GB RK3566 board.

---

## 🚀 Quick Start: Flashing the SD Card Image

1. Verify the checksum:
   ```bash
   sha256sum -c MaiaLinux-RG353V-v1.0.0-sdcard.img.xz.sha256
   ```
2. Flash **`MaiaLinux-RG353V-v1.0.0-sdcard.img.xz`** to a microSD card (32GB or larger) using **BalenaEtcher**, **Raspberry Pi Imager**, or via terminal on Linux:
   ```bash
   xzcat MaiaLinux-RG353V-v1.0.0-sdcard.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
   ```
   *(Replace `/dev/sdX` or `/dev/mmcblkX` with your microSD card device).*
3. Insert the microSD card into the **TF1/INT** slot of your Anbernic RG353V and power on.

---

## 🖥️ Quick Start: Running the QEMU Image on a PC

```bash
# Option A: Run the 640x480 ARM64 LXQt graphical desktop simulator (requires qemu-user-static, bubblewrap, xserver-xephyr):
./scripts/host/run-qemu-image.sh --gui

# Experimental full-system mode requires a kernel built for QEMU ARM64 virt:
KERNEL_IMG=/path/to/virt-compatible-Image ./scripts/host/run-qemu-image.sh --vm
```

---

## 🔐 Default Credentials (SSH / Terminal)

- **User**: `ark`
- **Password**: `arkos`


## Recovery build corrections

- Root filesystem enlarged to 16 GiB to leave room for desktop tools and swap.
- Persistent desktop/Xorg diagnostics in `~/.local/state/maialinux/`.
- Simulator starts the full LXQt session, waits for the window manager and panel, and reaps guest processes on exit.
- Projects and desktop profiles are injected explicitly and compared against their source files during builds.
- Full-system VM mode requires an explicitly supplied QEMU-compatible kernel.
- The QEMU distribution includes `qemu-support/`; keep it beside the runner script.

## GPU and clean-session correction

- Restores the backed-up Mali EGL driver and prevents Wayland library copies from following destination symlinks into the GPU driver.
- GPU health checks now require the `eglInitialize` export.
- QEMU starts the normal LXQt desktop without automatically opening Geany or the keyboard.
- Legacy splash hooks do no framebuffer writes or installation work during early boot.
- EmulationStation startup output is retained in `~/.local/state/maialinux/emulationstation.log`.
