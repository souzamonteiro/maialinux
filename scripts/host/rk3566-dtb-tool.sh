#!/usr/bin/env bash
# rk3566-dtb-tool.sh
# Tool to decompile, patch (downclock / overclock), compile, and deploy
# Device Tree Blobs (DTB) and Sources (DTS) for RK3566 devices (e.g., Anbernic RG353V).
#
# Addresses the boot freeze / crash issue described in ArkOS Issue #837:
# https://github.com/christianhaitian/arkos/issues/837
# Certain RK3566 hardware revisions / silicon bins cannot sustain clocks above
# 1.416 GHz (e.g. 1.6GHz, 1.8GHz, 2.0GHz), causing hard lockups during boot or load.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default paths
DEFAULT_BOOT_DIR="/media/roberto/BOOT"
DEFAULT_DTB_NAME="rk3566-353v.dtb"
DEFAULT_DTS_OUT="$REPO_ROOT/dts/rk3566-OC.dts"
DEFAULT_ORIG_DTS="$REPO_ROOT/dts/rk3566-original.dts"
DEFAULT_MAX_FREQ="1416" # in MHz (1416 = 1.416 GHz safe cap)

usage() {
  cat <<'EOF'
Usage:
  scripts/host/rk3566-dtb-tool.sh <command> [options]

Commands:
  status [file]                       Show CPU operating performance points (OPP) in a DTB or DTS
  decompile [input.dtb] [output.dts]  Decompile DTB to DTS (defaults: SD card DTB -> dts/rk3566-OC.dts)
  patch [input.dts] [output.dts]      Patch DTS to cap max CPU clock (removes frequencies > max-freq)
  compile [input.dts] [output.dtb]    Compile DTS to DTB using Device Tree Compiler (dtc)
  deploy [input.dtb|input.dts]        Deploy DTB to SD card BOOT partition and repo distro bundle
  fix                                 All-in-one: decompile, patch to 1.416GHz, compile, backup & deploy

Options:
  --boot-dir <path>                   BOOT partition mount path (default: /media/roberto/BOOT)
  --dtb-name <filename>               Target DTB name (default: rk3566-353v.dtb)
  --max-freq <1416|1608|1800>         Max CPU clock in MHz to keep (default: 1416 MHz)
  --notimingchange                    Also patch/deploy rk3566-353v-notimingchange.dtb
  -h, --help                          Show this help message

Examples:
  # Check current clock status of SD card DTB
  scripts/host/rk3566-dtb-tool.sh status

  # Apply safe 1.416GHz fix end-to-end to mounted SD card
  scripts/host/rk3566-dtb-tool.sh fix

  # Decompile to dts/rk3566-OC.dts for inspection or manual edits
  scripts/host/rk3566-dtb-tool.sh decompile

  # Compile modified dts/rk3566-OC.dts and deploy to SD card
  scripts/host/rk3566-dtb-tool.sh deploy dts/rk3566-OC.dts
EOF
}

find_dtc() {
  if command -v dtc >/dev/null 2>&1; then
    command -v dtc
    return 0
  fi
  local candidates=(
    "$REPO_ROOT/.cache/rk3566-logo-build/kernel_5_10_226/scripts/dtc/dtc"
    "$REPO_ROOT/.cache/rg353v-kernel4-build/RG353VKernel/scripts/dtc/dtc"
    "$REPO_ROOT/.cache/upstream/sources/linux-rk356x-5.10/scripts/dtc/dtc"
  )
  for c in "${candidates[@]}"; do
    if [[ -x "$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  echo "Error: Device Tree Compiler (dtc) not found." >&2
  echo "Please install it with: sudo apt install device-tree-compiler" >&2
  return 1
}

find_boot_dir() {
  local candidate="$1"
  if [[ -n "$candidate" && -d "$candidate" ]]; then
    echo "$candidate"
    return 0
  fi
  local dirs=("$DEFAULT_BOOT_DIR" "/media/$USER/BOOT" "/media/$USER/boot" "/media/$USER/BOOT1")
  for d in "${dirs[@]}"; do
    if [[ -d "$d" ]]; then
      echo "$d"
      return 0
    fi
  done
  echo "$DEFAULT_BOOT_DIR"
}

cmd_status() {
  local target="${1:-}"
  local dtc
  dtc="$(find_dtc)"

  if [[ -z "$target" ]]; then
    local bdir
    bdir="$(find_boot_dir "")"
    if [[ -f "$bdir/$DEFAULT_DTB_NAME" ]]; then
      target="$bdir/$DEFAULT_DTB_NAME"
    elif [[ -f "$DEFAULT_DTS_OUT" ]]; then
      target="$DEFAULT_DTS_OUT"
    elif [[ -f "$REPO_ROOT/distro/kernel-rg353v-5.10/$DEFAULT_DTB_NAME" ]]; then
      target="$REPO_ROOT/distro/kernel-rg353v-5.10/$DEFAULT_DTB_NAME"
    else
      echo "Error: no target DTB or DTS found to inspect." >&2
      exit 1
    fi
  fi

  echo "=== Inspecting OPP Clocks for: $target ==="
  local dts_content=""
  if [[ "$target" == *.dtb ]]; then
    dts_content="$("$dtc" -I dtb -O dts "$target" 2>/dev/null)"
  else
    dts_content="$(cat "$target")"
  fi

  python3 - <<PYEOF
import re, sys

content = """$dts_content"""
table_match = re.search(r"cpu0-opp-table\s*\{.*?\n\t\};", content, re.DOTALL)
if not table_match:
    print("Warning: cpu0-opp-table not found in target.")
    sys.exit(0)

table = table_match.group(0)
opps = re.findall(r"(opp-[a-z0-9_-]+)\s*\{", table)
print("Detected CPU OPP nodes:")
max_hz = 0
for opp in opps:
    hz_match = re.search(re.escape(opp) + r"\s*\{[^}]*?opp-hz\s*=\s*<([^>]+)>", table)
    extra = ""
    if hz_match:
        vals = hz_match.group(1).split()
        # dtc output may be <0x00 0x54667200> or </bits/ 64 <1416000000>>
        hz = 0
        try:
            if len(vals) == 2:
                hz = (int(vals[0], 0) << 32) | int(vals[1], 0)
            elif len(vals) == 1:
                hz = int(vals[0], 0)
            if hz > 0:
                mhz = hz / 1_000_000
                extra = f" (~{mhz:.1f} MHz / {mhz/1000:.3f} GHz)"
                if hz > max_hz and not "opp-j-" in opp:
                    max_hz = hz
        except Exception:
            pass
    print(f"  - {opp}{extra}")

if max_hz > 0:
    max_mhz = max_hz / 1_000_000
    print(f"\n=> Maximum standard CPU clock: {max_mhz:.1f} MHz ({max_mhz/1000:.3f} GHz)")
    if max_mhz <= 1416.1:
        print("=> Status: SAFE / DOWNCLOCKED (Safe for all RK3566 silicon revisions - ArkOS #837 compliant)")
    else:
        print("=> Status: HIGH CLOCK (May cause boot lockup / freeze on sensitive RK3566 batches!)")
PYEOF
}

cmd_decompile() {
  local input="${1:-}"
  local output="${2:-$DEFAULT_DTS_OUT}"
  local dtc
  dtc="$(find_dtc)"

  if [[ -z "$input" ]]; then
    local bdir
    bdir="$(find_boot_dir "")"
    if [[ -f "$bdir/$DEFAULT_DTB_NAME" ]]; then
      input="$bdir/$DEFAULT_DTB_NAME"
    elif [[ -f "$REPO_ROOT/distro/kernel-rg353v-5.10/$DEFAULT_DTB_NAME" ]]; then
      input="$REPO_ROOT/distro/kernel-rg353v-5.10/$DEFAULT_DTB_NAME"
    else
      echo "Error: input DTB not specified and not found at $bdir/$DEFAULT_DTB_NAME." >&2
      exit 1
    fi
  fi

  mkdir -p "$(dirname "$output")"
  echo "Decompiling: $input -> $output"
  "$dtc" -I dtb -O dts -o "$output" "$input" 2>&1 | grep -v "Warning" || true
  echo "Decompile complete: $output"
}

cmd_patch() {
  local input="${1:-$DEFAULT_ORIG_DTS}"
  local output="${2:-$DEFAULT_DTS_OUT}"
  local max_freq="$DEFAULT_MAX_FREQ"

  if [[ ! -f "$input" ]]; then
    if [[ -f "$DEFAULT_DTS_OUT" ]]; then
      input="$DEFAULT_DTS_OUT"
    else
      echo "Input DTS not found at $input. Decompiling current DTB first..."
      cmd_decompile "" "$input"
    fi
  fi

  echo "Patching DTS: $input -> $output (Capping max CPU clock to ${max_freq} MHz)"
  python3 - "$input" "$output" "$max_freq" <<'PYEOF'
import sys, re

input_path = sys.argv[1]
output_path = sys.argv[2]
max_freq_mhz = int(sys.argv[3])

with open(input_path, "r", encoding="utf-8") as f:
    text = f.read()

header = f"""/*
 * MaiaLinux RK3566 Device Tree Source (rk3566-OC.dts)
 *
 * Modified for Anbernic RG353V / RG353-series handhelds.
 * Downclocks maximum CPU frequency to {max_freq_mhz} MHz to resolve boot freezing
 * and lockups on RK3566 silicon revisions with lower silicon tolerance.
 * Reference: https://github.com/christianhaitian/arkos/issues/837
 */
"""

if not text.startswith("/*"):
    text = header + text
elif "MaiaLinux RK3566" not in text:
    text = header + "\n" + text

# Remove OPP nodes higher than max_freq_mhz
# Standard nodes: opp-1608000000 (1608 MHz), opp-1800000000 (1800 MHz), opp-1992000000 (1992 MHz)
# Variant nodes: opp-m-1608000000 (1608 MHz)
candidates = [
    ("opp-1608000000", 1608),
    ("opp-m-1608000000", 1608),
    ("opp-1800000000", 1800),
    ("opp-1992000000", 1992),
]

removed_count = 0
for node, freq in candidates:
    if freq > max_freq_mhz:
        pattern = r"\t\t" + re.escape(node) + r"\s*\{[^}]*?\};\n+"
        text, n = re.subn(pattern, "", text)
        if n > 0:
            print(f"  - Removed {node} ({freq} MHz)")
            removed_count += n

with open(output_path, "w", encoding="utf-8") as f:
    f.write(text)

print(f"Patch applied successfully ({removed_count} high-clock nodes removed). Saved to {output_path}")
PYEOF
}

cmd_compile() {
  local input="${1:-$DEFAULT_DTS_OUT}"
  local output="${2:-${input%.dts}.dtb}"
  local dtc
  dtc="$(find_dtc)"

  if [[ ! -f "$input" ]]; then
    echo "Error: input DTS not found at $input" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$output")"
  echo "Compiling DTS: $input -> $output"
  "$dtc" -I dts -O dtb -o "$output" "$input" 2>&1 | grep -v "Warning" || true
  echo "Compilation complete: $output ($(stat -c%s "$output" 2>/dev/null || wc -c < "$output") bytes)"
}

cmd_deploy() {
  local input="${1:-$DEFAULT_DTS_OUT}"
  local boot_dir
  boot_dir="$(find_boot_dir "${BOOT_DIR_OVERRIDE:-}")"
  local dtc
  dtc="$(find_dtc)"
  local compiled_dtb=""

  if [[ "$input" == *.dts ]]; then
    compiled_dtb="$(mktemp --suffix=.dtb)"
    cmd_compile "$input" "$compiled_dtb"
  elif [[ "$input" == *.dtb ]]; then
    compiled_dtb="$input"
  else
    echo "Error: input must be a .dts or .dtb file." >&2
    exit 1
  fi

  local ts
  ts="$(date +%Y%m%d-%H%M%S)"

  # 1. Update repo bundles
  echo "==> Updating repo kernel bundle at distro/kernel-rg353v-5.10..."
  mkdir -p "$REPO_ROOT/distro/kernel-rg353v-5.10"
  cp -f "$compiled_dtb" "$REPO_ROOT/distro/kernel-rg353v-5.10/$DEFAULT_DTB_NAME"
  cp -f "$compiled_dtb" "$REPO_ROOT/distro/kernel-rg353v-5.10/rk3566.dtb"
  cp -f "$compiled_dtb" "$REPO_ROOT/distro/kernel-rg353v-5.10/rk3566-OC.dtb"

  # Also save in dts/
  cp -f "$compiled_dtb" "$REPO_ROOT/dts/rk3566-OC.dtb"

  # 2. Update BOOT partition if present
  if [[ -d "$boot_dir" && -w "$boot_dir" ]]; then
    echo "==> Deploying to BOOT partition at $boot_dir..."
    local target_dtb="$boot_dir/$DEFAULT_DTB_NAME"
    if [[ -f "$target_dtb" ]]; then
      # Make persistent orig backup once
      if [[ ! -f "$boot_dir/$DEFAULT_DTB_NAME.orig" ]]; then
        cp -f "$target_dtb" "$boot_dir/$DEFAULT_DTB_NAME.orig"
        echo "  - Created original backup: $boot_dir/$DEFAULT_DTB_NAME.orig"
      fi
      # Make timestamped backup
      cp -f "$target_dtb" "$boot_dir/$DEFAULT_DTB_NAME.bak.$ts"
      echo "  - Created backup: $boot_dir/$DEFAULT_DTB_NAME.bak.$ts"
    fi

    cp -f "$compiled_dtb" "$target_dtb"
    echo "  - Installed: $target_dtb"

    # Also install rk3566-OC.dtb for maximum compatibility with ArkOS configurations
    cp -f "$compiled_dtb" "$boot_dir/rk3566-OC.dtb"
    echo "  - Installed: $boot_dir/rk3566-OC.dtb"

    if [[ "${PATCH_NOTIMINGCHANGE:-no}" == "yes" && -f "$boot_dir/rk3566-353v-notimingchange.dtb" ]]; then
      cp -f "$boot_dir/rk3566-353v-notimingchange.dtb" "$boot_dir/rk3566-353v-notimingchange.dtb.bak.$ts"
      cp -f "$compiled_dtb" "$boot_dir/rk3566-353v-notimingchange.dtb"
      echo "  - Installed: $boot_dir/rk3566-353v-notimingchange.dtb"
    fi

    sync
    echo "==> Sync complete on $boot_dir."
  else
    echo "Notice: BOOT partition not mounted or not writable at $boot_dir. Repo bundles updated."
  fi

  if [[ "$input" == *.dts ]]; then
    rm -f "$compiled_dtb"
  fi

  echo "==> Deploy finished successfully!"
}

cmd_fix() {
  local boot_dir
  boot_dir="$(find_boot_dir "${BOOT_DIR_OVERRIDE:-}")"
  local target_dtb="$boot_dir/$DEFAULT_DTB_NAME"
  local orig_dts="$DEFAULT_ORIG_DTS"
  local oc_dts="$DEFAULT_DTS_OUT"

  echo "=========================================================="
  echo " MaiaLinux RK3566 Clock Stability Fix (ArkOS Issue #837) "
  echo "=========================================================="
  echo "Target BOOT dir : $boot_dir"
  echo "Target DTB      : $target_dtb"
  echo "Safe max clock  : ${DEFAULT_MAX_FREQ} MHz (1.416 GHz)"
  echo ""

  # 1. Inspect current status
  if [[ -f "$target_dtb" ]]; then
    echo "--- Current Status ---"
    cmd_status "$target_dtb"
    echo ""
  fi

  # 2. Decompile current original DTB if orig_dts not present
  if [[ ! -f "$orig_dts" ]]; then
    echo "--- Decompiling Original DTB ---"
    cmd_decompile "$target_dtb" "$orig_dts"
    echo ""
  fi

  # 3. Apply clock downclock patch
  echo "--- Patching DTS to Safe Frequencies ---"
  cmd_patch "$orig_dts" "$oc_dts"
  echo ""

  # 4. Deploy DTB to SD Card and distro bundle
  echo "--- Compiling and Deploying ---"
  cmd_deploy "$oc_dts"
  echo ""

  # 5. Verify newly installed DTB
  if [[ -f "$target_dtb" ]]; then
    echo "--- Verifying Deployed DTB ---"
    cmd_status "$target_dtb"
    echo ""
  fi

  echo "=========================================================="
  echo " Fix successfully applied! Safe to eject SD card and boot."
  echo "=========================================================="
}

BOOT_DIR_OVERRIDE=""
PATCH_NOTIMINGCHANGE="no"

COMMAND="${1:-fix}"
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --boot-dir)
      BOOT_DIR_OVERRIDE="${2:-}"
      shift 2
      ;;
    --dtb-name)
      DEFAULT_DTB_NAME="${2:-}"
      shift 2
      ;;
    --max-freq)
      DEFAULT_MAX_FREQ="${2:-1416}"
      shift 2
      ;;
    --notimingchange)
      PATCH_NOTIMINGCHANGE="yes"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      # positional arguments passed to commands
      break
      ;;
  esac
done

case "$COMMAND" in
  status)
    cmd_status "${1:-}"
    ;;
  decompile)
    cmd_decompile "${1:-}" "${2:-}"
    ;;
  patch)
    cmd_patch "${1:-}" "${2:-}"
    ;;
  compile)
    cmd_compile "${1:-}" "${2:-}"
    ;;
  deploy)
    cmd_deploy "${1:-}"
    ;;
  fix)
    cmd_fix
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    usage >&2
    exit 1
    ;;
esac

