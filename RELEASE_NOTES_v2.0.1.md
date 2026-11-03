# MaiaLinux v2.0.1 — RK3566 Clock Stability Fix & Device Tree Tooling

**MaiaLinux v2.0.1** is a stability and hardware compatibility release of the MaiaLinux distribution for the **Anbernic RG353V** (Rockchip RK3566), addressing critical boot freeze and CPU instability issues on sensitive silicon revisions while introducing dedicated Device Tree Source (DTS) management tooling.

---

## 📦 Release Artifacts (`distro/`)

| File | Description | Target |
| :--- | :--- | :--- |
| **`MaiaLinux-RG353V-v2.0.1-sdcard.img.xz`** | Ready-to-flash GPT SD Card image with stable 1.416 GHz DTB. | **Anbernic RG353V (TF1/INT slot)** |
| **`MaiaLinux-RG353V-v2.0.1-sdcard.img.xz.sha256`** | SHA-256 verification checksum for the SD Card image. | Integrity Verification |
| **`MaiaLinux-RG353V-v2.0.1-qemu.qcow2`** | Compressed QCOW2 ARM64 root filesystem image for QEMU testing and PC simulation. | **Linux PC (ARM64 desktop simulator)** |
| **`MaiaLinux-RG353V-v2.0.1-qemu.qcow2.sha256`** | SHA-256 verification checksum for the QEMU image. | Integrity Verification |

---

## ✨ Highlights & Fixes in v2.0.1

### 1. RK3566 CPU Clock Stability & Boot Freeze Fix ([ArkOS Issue #837](https://github.com/christianhaitian/arkos/issues/837))
- **The Issue**: Certain newer hardware batches and silicon revisions of the Anbernic RG353V / RG353M fail to boot past the initial loading screen or freeze under system load because the stock device tree enables CPU frequencies up to 1.8 GHz (`opp-1800000000`) and 1.992 GHz (`opp-1992000000`), exceeding the silicon tolerance of these chips.
- **The Solution**: Capped the maximum CPU Operating Performance Point (OPP) frequency to a rock-solid **1.416 GHz (1416 MHz)**, cleanly removing unstable 1.6 GHz, 1.8 GHz, and 2.0 GHz operating points (`opp-1608000000`, `opp-m-1608000000`, `opp-1800000000`, `opp-1992000000`).
- **Results**: Completely eliminates boot freezes and random system lockups while preserving excellent emulation and desktop performance.

### 2. Device Tree Sources (`dts/`) Tracked in Repository
- Provided human-readable Device Tree Sources directly in the [`dts/`](../dts/) directory:
  - **`dts/rk3566-OC.dts`**: Active, editable device tree source with the safe 1.416 GHz CPU OPP table applied.
  - **`dts/rk3566-original.dts`**: Unpatched original reference decompiled from vendor DTB.
  - **`dts/README.md`**: Complete documentation on the RK3566 clock architecture, issue background, and compiler usage.

### 3. Comprehensive Host Device Tree Tooling (`scripts/host/`)
- Added [`scripts/host/rk3566-dtb-tool.sh`](../scripts/host/rk3566-dtb-tool.sh) to diagnose, decompile, patch, compile, and deploy device trees:
  - `rk3566-dtb-tool.sh status`: Inspeciona OPP clock table in any DTB/DTS and reports whether it is safe or high-clock.
  - `rk3566-dtb-tool.sh fix`: One-shot end-to-end diagnosis, backup, 1.416 GHz downclock, compile, deploy, and verification.
  - `rk3566-dtb-tool.sh compile`: Compiles `.dts` to `.dtb` using the bundled Device Tree Compiler (`dtc`).
  - `rk3566-dtb-tool.sh decompile`: Converts binary `.dtb` to human-readable `.dts`.
  - `rk3566-dtb-tool.sh deploy`: Atomically deploys to mounted SD card `BOOT` partition with automatic timestamped and `.orig` backups.
- Added convenient helper wrappers:
  - `scripts/host/fix-rk3566-boot-clock.sh`
  - `scripts/host/compile-rk3566-dts.sh`
  - `scripts/host/decompile-rk3566-dtb.sh`

### 4. Dual DTB Bootloader Compatibility
- Installs both `rk3566-353v.dtb` (used by MaiaLinux / dArkOS `extlinux.conf`) and `rk3566-OC.dtb` (used by standard ArkOS configurations) to the `BOOT` partition, ensuring full cross-compatibility regardless of bootloader configuration.

### 5. Version Bump to v2.0.1
- Upgraded system version identifiers across `/etc/os-release`, `/etc/issue`, `/etc/maialinux-release`, MOTD banners, Plymouth themes, build scripts, and documentation.

