#!/usr/bin/env bash
# build-rg353v-kernel5-bundle.sh
# Builds a custom RG353V Kernel 5.10 bundle (Image + DTBs + resource.img)
# with the MaiaLinux custom boot logos embedded.
# Compatible with dArkOS 08272026 / Christian Haitian kernel_5_10_226 tree.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

KERNEL_REPO_URL="https://github.com/christianhaitian/kernel_5_10_226.git"
TOOLCHAIN_REPO_URL="https://github.com/christianhaitian/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu.git"
WORK_ROOT_DEFAULT="$REPO_ROOT/.cache/rk3566-logo-build"
WORK_ROOT="$WORK_ROOT_DEFAULT"
KERNEL_DIR=""
TOOLCHAIN_DIR=""
JOBS="$(nproc)"
LOGO_INPUT="$REPO_ROOT/images/logo-kernel-rg353-640x480.png"
HDMI_LOGO_INPUT="$REPO_ROOT/images/logo-kernel-hdmi-1280x720.png"
OUTPUT_DIR="$REPO_ROOT/distro/kernel-rg353v-5.10"
REFRESH_KERNEL="no"
PYTHON_SHIM_DIR=""

usage() {
  cat <<'EOF'
Usage:
  scripts/host/build-rg353v-kernel5-bundle.sh [options]

Options:
  --logo <path>           LCD logo source (default: images/logo-kernel-rg353-640x480.png)
  --hdmi-logo <path>      HDMI logo source (default: images/logo-kernel-hdmi-1280x720.png)
  --output-dir <path>     Bundle output directory (default: distro/kernel-rg353v-5.10)
  --work-root <path>      Build/cache directory (default: .cache/rk3566-logo-build)
  --jobs <n>              Parallel jobs (default: nproc)
  --refresh-kernel        Re-clone kernel repository
  -h, --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --logo) LOGO_INPUT="${2:-}"; shift 2 ;;
    --hdmi-logo) HDMI_LOGO_INPUT="${2:-}"; shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:-}"; shift 2 ;;
    --work-root) WORK_ROOT="${2:-}"; shift 2 ;;
    --jobs) JOBS="${2:-}"; shift 2 ;;
    --refresh-kernel) REFRESH_KERNEL="yes"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

KERNEL_DIR="$WORK_ROOT/kernel_5_10_226"
TOOLCHAIN_DIR="$WORK_ROOT/toolchain"

mkdir -p "$WORK_ROOT" "$OUTPUT_DIR"

# 1. Ensure Linaro toolchain is present
if [[ ! -d "$TOOLCHAIN_DIR/bin" ]]; then
  echo "Cloning Linaro 6.3.1 cross-compiler toolchain..."
  git clone --depth=1 "$TOOLCHAIN_REPO_URL" "$TOOLCHAIN_DIR"
fi

# 2. Ensure Kernel 5.10 source is present
if [[ "$REFRESH_KERNEL" == "yes" ]]; then
  rm -rf "$KERNEL_DIR"
fi
if [[ ! -d "$KERNEL_DIR/.git" ]]; then
  echo "Cloning kernel_5_10_226 source..."
  git clone --recursive --depth=1 "$KERNEL_REPO_URL" "$KERNEL_DIR"
fi

# 3. Ensure python shim exists for gcc-wrapper.py
PYTHON_SHIM_DIR="$(mktemp -d)"
ln -s "$(command -v python3)" "$PYTHON_SHIM_DIR/python"
export PATH="$PYTHON_SHIM_DIR:$TOOLCHAIN_DIR/bin:$PATH"

cleanup() {
  if [[ -n "$PYTHON_SHIM_DIR" ]]; then
    rm -rf "$PYTHON_SHIM_DIR"
  fi
}
trap cleanup EXIT

# 4. Convert logos to PPM
echo "=== Converting MaiaLinux logos to PPM ==="
pngtopnm "$LOGO_INPUT" | ppmquant 224 | pnmnoraw > "$KERNEL_DIR/drivers/video/logo/logo_linux_clut224.ppm"
pngtopnm "$HDMI_LOGO_INPUT" | ppmquant 224 | pnmnoraw > "$KERNEL_DIR/drivers/video/logo/logo_hdmi_clut224.ppm"

rm -f "$KERNEL_DIR/drivers/video/logo/logo_linux_clut224.c" "$KERNEL_DIR/drivers/video/logo/logo_linux_clut224.o"
rm -f "$KERNEL_DIR/drivers/video/logo/logo_hdmi_clut224.c" "$KERNEL_DIR/drivers/video/logo/logo_hdmi_clut224.o"
rm -f "$KERNEL_DIR/drivers/video/logo/built-in.a"

# 5. Build Kernel Image and DTBs
echo "=== Compiling Kernel 5.10 for RG353V ==="
pushd "$KERNEL_DIR" >/dev/null

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- rk3566_optimized_linux_defconfig
CFLAGS=-Wno-deprecated-declarations make -j"$JOBS" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    KERNEL_DTS=rk3566 KERNEL_CONFIG=rk3566_optimized_linux_defconfig Image dtbs

# 6. Copy artifacts to output directory
echo "=== Staging artifacts in $OUTPUT_DIR ==="
cp -f arch/arm64/boot/Image "$OUTPUT_DIR/Image"
cp -f arch/arm64/boot/dts/rockchip/rk3566-353v.dtb "$OUTPUT_DIR/rk3566-353v.dtb"
cp -f arch/arm64/boot/dts/rockchip/rk3566-353v-notimingchange.dtb "$OUTPUT_DIR/rk3566-353v-notimingchange.dtb"

popd >/dev/null

echo "Kernel 5.10 bundle build complete!"
echo "Outputs in $OUTPUT_DIR:"
ls -lh "$OUTPUT_DIR"
