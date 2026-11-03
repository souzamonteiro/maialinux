# MaiaLinux 2.0.1: Architecture, Boot Chain, and Customization Guide

This document describes the internal architecture, partition scheme, boot chain, offline Linux 5.10 kernel logo injection, Device Tree clock management (ArkOS Issue #837), and user interface integrations (EmulationStation, LXQt, Virtual Keyboard, and Silent Boot) of **MaiaLinux 2.0.1** for the **Anbernic RG353V (Rockchip RK3566)** handheld console.

---

## 1. Platform Overview

* **Device**: Anbernic RG353V (and RG353-series)
* **SoC**: Rockchip RK3566 (Quad-Core Cortex-A55, Mali Bifrost G52-2EE GPU)
* **Display**: 3.5" IPS (Native resolution: 640×480, 4:3 aspect ratio) + Mini-HDMI output (up to 1920×1080 @ 60Hz)
* **Inputs**: Capacitive multi-touch screen, D-Pad, dual clickable analog sticks (L3/R3), face buttons (A, B, X, Y, Select, Start, Function), shoulder buttons (L1, L2, R1, R2), and lateral physical Power button.
* **Base System**: dArkOS (Debian 13 "Trixie" aarch64)
* **Kernel**: Linux 5.10.226 Rockchip RK356x SMP PREEMPT
* **Desktop Environment**: LXQt + Openbox + Xorg (Display `:1`, `vt1`) + EmulationStation (Direct KMS/DRM)

---

## 2. MicroSD Card Partition Scheme (TF1/INT Slot)

The RG353V boot microSD card follows this partition and sector layout:

| Partition | Device | Type / FS | Approx. Size | Label / Mountpoint | Contents & Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Sectors 0-64M** | Raw Block | - | ~32 MB | (U-Boot / SPL) | Stores `idbloader.img`, `trust.img`, and `uboot.img` at fixed Rockchip RK3566 SoC offsets. |
| **Partition 1** | `/dev/mmcblk1p1` | Raw / Ext2 | 4 MB | `misc` | Recovery / fastboot parameters for Rockchip/Android. |
| **Partition 2** | `/dev/mmcblk1p2` | Raw / Ext2 | 4 MB | `resource` | **CRITICAL**: Contains U-Boot DTBs and boot resources (`resource.img`). **DO NOT OVERWRITE** with legacy 4.19 kernel tools to avoid black screens on the internal LCD. |
| **Partition 3** | `/dev/mmcblk1p3` | FAT32 (vfat) | ~98 MB | `BOOT` | Boot partition containing the kernel (`Image`, ~32MB), device tree blobs (`rk3566-353v.dtb`, `rk3566-OC.dtb`), initramfs (`uInitrd`), and bootloader configuration (`extlinux/extlinux.conf`). |
| **Partition 4** | `/dev/mmcblk1p4` | BTRFS / Ext4 | ~8-16 GB | `ROOTFS` | Complete root operating system (Debian 13 Trixie), binaries, libraries, and LXQt desktop environment. |
| **Partition 5** | `/dev/mmcblk1p5` | exFAT | Remaining SD | `EASYROMS` (`/roms`) | ROMs, EmulationStation themes, and MaiaLinux tools (`/roms/maialinux/`). |

> [!CAUTION]
> **Keep at least 40 MB free on Partition 3 (`BOOT`):**
> Because the Linux `Image` is ~33 MB, keeping multiple duplicate backups (such as `Image.bak`) will exhaust the 98 MB partition space. If copying without sufficient free space, the copy will be silently truncated, causing boot failure (black screen). Always keep at least 40 MB of free space on `BOOT`.

---

## 3. RK3566 Clock Stability & Device Tree Architecture (ArkOS Issue #837)

### 3.1 Silicon Variance and High-Clock Lockups
Certain hardware revisions and silicon production batches of the Anbernic RG353V / RG353M suffer from silicon tolerance limits. Standard kernel device trees define Operating Performance Points (OPP) up to **1.800 GHz** (`opp-1800000000`) and **1.992 GHz** (`opp-1992000000`).

On affected units, the CPU crashes immediately upon scaling to these frequencies during early boot or under heavy loads, causing complete system lockups or black screen hangs.

* **Reference**: [ArkOS Issue #837](https://github.com/christianhaitian/arkos/issues/837)
* **MaiaLinux Solution**: The maximum operating frequency is safely capped to **1.416 GHz (1416 MHz)** by cleanly removing `opp-1608000000`, `opp-m-1608000000`, `opp-1800000000`, and `opp-1992000000` from the device tree's `cpu0-opp-table`.

### 3.2 Human-Readable Device Tree Sources (`dts/`)
The repository includes dedicated DTS files in [`dts/`](../dts/):
- **`dts/rk3566-OC.dts`**: The canonical, human-readable DTS file with the 1.416 GHz stability patch applied.
- **`dts/rk3566-original.dts`**: Unpatched reference decompiled from the original vendor DTB.

### 3.3 Device Tree Tooling (`scripts/host/`)
MaiaLinux provides specialized host tooling for managing device trees without needing to rebuild the entire kernel:

- **`scripts/host/rk3566-dtb-tool.sh status`**: Inspects CPU OPP frequencies in any DTB/DTS and flags whether the clock is in a safe or dangerous state.
- **`scripts/host/fix-rk3566-boot-clock.sh`**: One-command automated fix. Decompiles the SD card DTB, creates timestamped and `.orig` backups, patches clocks to 1.416 GHz, compiles via `dtc`, and deploys both `rk3566-353v.dtb` and `rk3566-OC.dtb`.
- **`scripts/host/compile-rk3566-dts.sh`**: Compiles `dts/rk3566-OC.dts` and writes it to the mounted SD card.
- **`scripts/host/decompile-rk3566-dtb.sh`**: Decompiles any binary DTB back to DTS for inspection.

---

## 4. Boot Chain & Embedded Kernel Boot Logo

### 4.1 Framebuffer Boot Logo Architecture
In Rockchip Kernel 5.10, early kernel DRM/KMS does not load standalone bitmap files from filesystem storage during power-on. The boot logo is **statically compiled inside the kernel binary** (`Image`) using the Linux framebuffer logo subsystem:
- Kernel driver destination: `drivers/video/logo/logo_linux_clut224.ppm`
- Format: PPM (Portable Pixmap) text ASCII, restricted to **224 indexed colors (CLUT)**.

### 4.2 Offline Kernel Image Generator (`generate-custom-kernel-image.py`)
To update or rebuild the kernel logo without depending on external CI pipelines, MaiaLinux provides an offline generator in `scripts/host/generate-custom-kernel-image.py`:
- Employs the bundled Linaro GCC 6.3.1 cross-toolchain (`aarch64-linux-gnu-gcc`).
- Converts 640×480 and 1280×720 PNG logos to 224-color PPM.
- Compiles the kernel `Image` with zero-noise parameters (`loglevel=0 console=tty3 systemd.show_status=0`).

---

## 5. User Interface & Input Integrations

### 5.1 Clean Power Management & Suspend
To eliminate desktop popup errors when pressing the hardware Power button:
1. In `/home/ark/.config/lxqt/lxqt.conf`:
   ```ini
   [General]
   lock_screen_before_power_actions=false
   lock_command=/bin/true
   ```
2. In `/home/ark/.config/lxqt/power.conf`:
   ```ini
   [General]
   lock_screen=false
   lockScreenOnSuspend=false
   ```
3. Set `Hidden=true` in `/etc/xdg/autostart/lxqt-xscreensaver-autostart.desktop`.
4. Dummy scripts placed at `/usr/local/bin/xscreensaver` and `/usr/local/bin/xscreensaver-command` always return status `0`.

### 5.2 Ergonomic Virtual Keyboard for Programming (`matchbox-keyboard`)
A tailored 4-row, 50-key layout is provided at `/home/ark/.matchbox/keyboard.xml`:
* **Row 1 (Numbers & Direct Arithmetic)**: `1 2 3 4 5 6 7 8 9 0 - = [⇦ Backspace]`
* **Row 2**: `[Tab] q w e r t y u i o p [⏎ Enter]`
* **Row 3**: `[Esc] a s d f g h j k l ; '`
* **Row 4**: `[⇧ Shift] z x c v b n m , . / [?123] [ Space ]`
* **Symbol Layer (`?123` / Mod1)**: Provides one-touch access to all coding brackets (`[ ]`, `{ }`, `< >`), slashes (`|`, `\`, `/`), and symbols (`~`, '`', `!`, `@`, `#`, `$`, `%`, `^`, `&`, `*`, `_`, `+`, `:`, `"`, `?`).
* **Geometry**: Fixed at `x=0, y=280, width=640, height=180` via Openbox window rules, leaving the upper screen area completely unobstructed for editors and terminal output.

---

## 6. Maintenance & Deployment Workflows

### Applying the Clock Stability Fix to an SD Card:
```bash
scripts/host/fix-rk3566-boot-clock.sh
```

### Inspecting Clock Frequencies:
```bash
scripts/host/rk3566-dtb-tool.sh status
```

### Building Distribution Images (v2.0.1):
```bash
# Build SD card .img.xz and QEMU .qcow2 release artifacts:
scripts/host/build-release-2.0.1.sh
```

### Emergency Recovery of Partition 2 (`resource`):
If Partition 2 is corrupted by legacy tools, restore it using the clean reference image:
```bash
sudo dd if=config/boot/resource_darkos_original.img of=/dev/sdX2 bs=4M status=progress conv=fsync
```
*(Replace `/dev/sdX2` with the appropriate SD card block device).*
