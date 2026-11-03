# MaiaLinux RK3566 Device Tree Sources (DTS) & Clock Management

This directory contains the Device Tree Source (`.dts`) files for Rockchip RK3566-based handhelds (such as the Anbernic RG353V, RG353M, and RG353P).

---

## Background & Problem Description (ArkOS Issue #837)

Certain hardware revisions and silicon batches of the **Anbernic RG353V** (and other RK3566 consoles) suffer from silicon lottery variance and cannot reliably handle the factory/overclocked CPU frequencies (1.6 GHz, 1.8 GHz, and 2.0 GHz) defined in standard device trees. When attempting to boot with these higher Operating Performance Points (OPP), the device crashes or hangs indefinitely ("boot freeze" / black screen or freeze at the initial boot splash).

- **Reference**: [ArkOS Issue #837 — (New?) RG353V has issues with ArkOS](https://github.com/christianhaitian/arkos/issues/837)
- **Root Cause**: The standard `rk3566-353v.dtb` defines OPP nodes up to `1992000000` (1.992 GHz) and `1800000000` (1.800 GHz). On affected chips, frequency scaling attempts to step beyond 1.416 GHz during boot, causing instantaneous CPU instability and freeze.
- **Solution**: Downclock the maximum operating frequency to **1.416 GHz (1416 MHz)** by cleanly removing `opp-1608000000`, `opp-m-1608000000`, `opp-1800000000`, and `opp-1992000000` from `cpu0-opp-table`.

---

## Directory Contents

| File | Description |
| :--- | :--- |
| **`rk3566-OC.dts`** | The active, human-readable Device Tree Source file with the safe 1.416 GHz max clock cap applied. Fully editable. |
| **`rk3566-original.dts`** | The unmodified reference DTS decompiled from the original vendor DTB (contains points up to 1.992 GHz). |
| **`rk3566-OC.dtb`** | The compiled binary Device Tree Blob generated from `rk3566-OC.dts` (matches ArkOS naming conventions). |

---

## Tooling & Helper Scripts

Pre-configured scripts are available in [`scripts/host/`](../scripts/host/):

### 1. Check Clock Status of any DTB / DTS
Inspect the OPP table and determine if the device tree is in a safe or high-clock state:
```bash
scripts/host/rk3566-dtb-tool.sh status
# Or inspect a specific file:
scripts/host/rk3566-dtb-tool.sh status /media/roberto/BOOT/rk3566-353v.dtb
```

### 2. Apply the Clock Stability Fix End-to-End
Decompiles the current DTB, creates timestamped and `.orig` backups on the SD card, applies the 1.416 GHz cap, compiles, and deploys both `rk3566-353v.dtb` and `rk3566-OC.dtb` to the `BOOT` partition:
```bash
scripts/host/fix-rk3566-boot-clock.sh
# Equivalent to:
scripts/host/rk3566-dtb-tool.sh fix
```

### 3. Recompile and Deploy Manual Edits to `dts/rk3566-OC.dts`
After making custom adjustments in `dts/rk3566-OC.dts`, recompile and deploy with:
```bash
scripts/host/compile-rk3566-dts.sh
# Equivalent to:
scripts/host/rk3566-dtb-tool.sh deploy dts/rk3566-OC.dts
```

### 4. Decompile any DTB to DTS
```bash
scripts/host/decompile-rk3566-dtb.sh [input.dtb] [output.dts]
```
