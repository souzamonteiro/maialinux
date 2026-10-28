# MaiaLinux v2.0.0 — Modern 64-bit Pocket Linux & Development Environment

**MaiaLinux v2.0.0** is the major second-generation release of the MaiaLinux distribution for the **Anbernic RG353V** (Rockchip RK3566), migrating the entire operating system stack to **dArkOS (Debian 13 "Trixie" ARM64)** powered by the **Linux 5.10.226 LTS Kernel**.

It turns the RG353V into a full-featured **dual-mode handheld gaming console + pocket software development computer**, seamlessly integrating **LXQt**, an enhanced **4-row 50-key virtual keyboard for programming**, **QTerminal**, **Geany IDE**, and complete **C/C++, Python 3, SDL2, and Qt5 toolchains**, while retaining full hardware compatibility with Mali Bifrost G52 GPU acceleration, RetroArch, and EmulationStation.

---

## 📦 Release Artifacts (`distro/`)

| File | Description | Target |
| :--- | :--- | :--- |
| **`MaiaLinux-RG353V-v2.0.0-sdcard.img.xz`** | Ready-to-flash GPT SD Card image (compressed with `xz`). Fits on any 16GB, 32GB or larger microSD card. | **Anbernic RG353V (TF1/INT slot)** |
| **`MaiaLinux-RG353V-v2.0.0-sdcard.img.xz.sha256`** | SHA-256 verification checksum for the SD Card image. | Integrity Verification |
| **`MaiaLinux-RG353V-v2.0.0-qemu.qcow2`** | Compressed QCOW2 ARM64 root filesystem image for QEMU testing and PC simulation. | **Linux PC (ARM64 desktop simulator)** |
| **`MaiaLinux-RG353V-v2.0.0-qemu.qcow2.sha256`** | SHA-256 verification checksum for the QEMU image. | Integrity Verification |

---

## ✨ Highlights & New Features in v2.0.0

### 1. Modern Base OS Migration: Debian 13 "Trixie" + Kernel 5.10.226
- Upgraded the base system from Ubuntu 19.10 (Eoan) to **Debian 13 (Trixie) ARM64**.
- Upgraded from legacy kernel 4.19 to **Linux Kernel 5.10.226 Rockchip SMP PREEMPT**.
- Provides modern GNU C Library (glibc), updated GCC toolchains, modern systemd, Python 3.11+, and contemporary library ecosystems.

### 2. Main Carousel Integration in EmulationStation
- **MaiaLinux Desktop** is now directly accessible on the **Main Carousel** of EmulationStation (`es_systems.cfg`), featuring dedicated system artwork, custom themes, and a one-click launcher to enter the LXQt desktop environment without hunting through submenus.
- Options/Tools integration preserved as an alternative launcher (`Options -> Tools -> Launch MaiaLinux (LXQt)`).

### 3. Embedded Kernel DRM Boot Logo
- Created a standalone, 100% offline kernel logo generation pipeline (`generate-custom-kernel-image.py`) using Linaro GCC 6.3.1.
- Converts the official MaiaLinux artwork into a 224-color CLUT PPM (`logo_linux_clut224.ppm`) embedded directly into the kernel framebuffer driver, rendering the full-screen boot logo immediately at power-on.
- Dedicated HDMI 1280×720 splash mode included for external monitor / TV output.

### 4. Virtual Keyboard Enhanced for Programming
- Brand new 4-row, 50-key ergonomic layout for `matchbox-keyboard` tailored for the 640×480 touchscreen (`x=0, y=280, 640×180`):
  - **Dedicated Number Row**: Direct access to `1 2 3 4 5 6 7 8 9 0 - =` and Backspace.
  - **Direct Programming Symbols**: Arithmetic operators (`+`, `-`, `=`), syntax punctuation (`;`, `:`, `'`, `"`, `,`, `.`, `/`), and navigation (`Tab`, `Esc`, `Shift`, `Enter`, `Space`).
  - **Instant `?123` / Mod1 Layer Toggle**: One touch unlocks all programming brackets (`[ ]`, `{ }`, `< >`), slashes (`\`, `/`, `|`), and symbols (`_`, `~`, '`', `!`, `@`, `#`, `$`, `%`, `^`, `&`, `*`).
  - Shortcut placed on the LXQt bottom panel and on the Desktop.

### 5. Seamless Power Management & Clean Suspend
- Fixed the LXQt screensaver popup error when pressing the physical Power button.
- Configured `lock_screen_before_power_actions=false` and dummy screensaver handlers so pressing the Power button suspends the device instantly and cleanly.

### 6. Partition Renaming (`dArkOS_Fat` → `BOOT`)
- Renamed FAT32 boot partition filesystem label and GPT partition name to `BOOT`.
- Mounts cleanly as `/media/roberto/BOOT` on host computers without affecting RK3566 U-Boot block-index booting.

---

## 🚀 Quick Start: Flashing the SD Card

1. Check the SHA-256 hash:
   ```bash
   sha256sum -c MaiaLinux-RG353V-v2.0.0-sdcard.img.xz.sha256
   ```
2. Flash **`MaiaLinux-RG353V-v2.0.0-sdcard.img.xz`** to your microSD card (16GB or larger) with **BalenaEtcher**, **Raspberry Pi Imager**, or directly via terminal:
   ```bash
   xzcat MaiaLinux-RG353V-v2.0.0-sdcard.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
   sync
   ```
   *(Replace `/dev/sdX` with your microSD card block device).*
3. Insert the card into slot **TF1/INT** of the Anbernic RG353V and turn on the device.

---

## 💻 Running with QEMU on PC

Launch the interactive 640×480 ARM64 LXQt desktop window on any x86_64 Linux PC without root privileges:
```bash
./run-maialinux-qemu.sh --gui
```
