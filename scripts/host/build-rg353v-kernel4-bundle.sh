#!/usr/bin/env bash
# Build a compatible RG353V kernel bundle (Image + rk3566.dtb + modules) from
# christianhaitian/RG353VKernel (4.19.172).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

KERNEL_REPO_URL="https://github.com/christianhaitian/RG353VKernel.git"
TOOLCHAIN_REPO_URL="https://github.com/christianhaitian/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu.git"
WORK_ROOT_DEFAULT="$REPO_ROOT/.cache/rg353v-kernel4-build"
WORK_ROOT="$WORK_ROOT_DEFAULT"
KERNEL_DIR=""
TOOLCHAIN_DIR=""
JOBS="$(nproc)"
INSTALL_DEPS="no"
REFRESH_KERNEL="no"
LOGO_INPUT="$REPO_ROOT/images/logo-kernel-rg353-640x480.png"
HDMI_LOGO_INPUT="$REPO_ROOT/images/logo-kernel-hdmi-1280x720.png"
UPDATE_HDMI="yes"
OUTPUT_DIR="$REPO_ROOT/distro/kernel-rg353v-4.19.172"
LOG_FILE=""
PID_FILE=""
TOOLCHAIN_MODE="auto"
PYTHON_SHIM_DIR=""

usage() {
  cat <<'EOF'
Usage:
  scripts/host/build-rg353v-kernel4-bundle.sh [options]

Options:
  --logo <path|url>           LCD logo source (default: images/logo-kernel-rg353-640x480.png)
  --hdmi-logo <path|url>      HDMI logo source (default: images/logo-kernel-hdmi-1280x720.png)
  --update-hdmi <yes|no>      Replace HDMI logo in source tree (default: yes)
  --output-dir <path>         Bundle output directory (default: distro/kernel-rg353v-4.19.172)
  --work-root <path>          Build/cache directory (default: .cache/rg353v-kernel4-build)
  --jobs <n>                  Parallel jobs (default: nproc)
  --toolchain <auto|linaro|system>
                               Toolchain selection (default: auto)
  --refresh-kernel            Re-clone kernel repository
  --install-deps              Install host dependencies (apt)
  -h, --help                  Show this help

Outputs in --output-dir:
  - Image
  - rk3566.dtb
  - modules-<kernel_release>.tar.xz
  - Image.meta
  - bundle.meta
EOF
}

abspath_from_repo() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    printf '%s\n' "$p"
  else
    printf '%s\n' "$REPO_ROOT/$p"
  fi
}

resolve_local_file() {
  local input="$1"
  if [[ -f "$input" ]]; then
    printf '%s\n' "$input"
    return 0
  fi
  if [[ -f "$REPO_ROOT/$input" ]]; then
    printf '%s\n' "$REPO_ROOT/$input"
    return 0
  fi
  return 1
}

fetch_logo_to_file() {
  local input="$1"
  local output="$2"
  local local_path=""

  if local_path="$(resolve_local_file "$input")"; then
    cp -f "$local_path" "$output"
    return 0
  fi

  wget -t 3 -T 60 --no-check-certificate "$input" -O "$output"
}

ensure_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd" >&2
    return 1
  fi
}

install_dependencies() {
  sudo apt -y update
  sudo apt -y install \
    build-essential git lzop gcc bc libncurses5-dev libc6-i386 lib32stdc++6 \
    zlib1g netpbm wget imagemagick gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu python3 xz-utils
}

check_dependencies() {
  local missing=0
  for cmd in git make wget pngtopnm ppmquant pnmnoraw xz; do
    if ! ensure_command "$cmd"; then
      missing=1
    fi
  done
  if [[ "$missing" -eq 1 ]]; then
    echo "Install dependencies with: sudo apt install build-essential git lzop gcc bc libncurses5-dev libc6-i386 lib32stdc++6 zlib1g netpbm wget imagemagick gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu python3 xz-utils" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --logo)
      LOGO_INPUT="${2:-}"
      shift 2
      ;;
    --hdmi-logo)
      HDMI_LOGO_INPUT="${2:-}"
      shift 2
      ;;
    --update-hdmi)
      UPDATE_HDMI="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --work-root)
      WORK_ROOT="${2:-}"
      shift 2
      ;;
    --jobs)
      JOBS="${2:-}"
      shift 2
      ;;
    --toolchain)
      TOOLCHAIN_MODE="${2:-}"
      shift 2
      ;;
    --refresh-kernel)
      REFRESH_KERNEL="yes"
      shift
      ;;
    --install-deps)
      INSTALL_DEPS="yes"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$UPDATE_HDMI" != "yes" && "$UPDATE_HDMI" != "no" ]]; then
  echo "Error: --update-hdmi must be yes or no." >&2
  exit 1
fi

if [[ ! "$JOBS" =~ ^[0-9]+$ ]] || [[ "$JOBS" -lt 1 ]]; then
  echo "Error: --jobs must be a positive integer." >&2
  exit 1
fi

if [[ "$TOOLCHAIN_MODE" != "auto" && "$TOOLCHAIN_MODE" != "linaro" && "$TOOLCHAIN_MODE" != "system" ]]; then
  echo "Error: --toolchain must be auto, linaro, or system." >&2
  exit 1
fi

if [[ "$INSTALL_DEPS" == "yes" ]]; then
  install_dependencies
fi
check_dependencies

WORK_ROOT="$(abspath_from_repo "$WORK_ROOT")"
OUTPUT_DIR="$(abspath_from_repo "$OUTPUT_DIR")"
KERNEL_DIR="$WORK_ROOT/RG353VKernel"
TOOLCHAIN_DIR="$WORK_ROOT/toolchain"
LOG_FILE="$WORK_ROOT/build.log"
PID_FILE="$WORK_ROOT/build.pid"

mkdir -p "$WORK_ROOT" "$OUTPUT_DIR"

if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    echo "Error: another build process is running (pid $old_pid)." >&2
    exit 1
  fi
fi

touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "===== $(date -Iseconds) RG353V kernel bundle build start ====="
echo "WORK_ROOT=$WORK_ROOT"
echo "OUTPUT_DIR=$OUTPUT_DIR"
echo "$$" > "$PID_FILE"

TMP_DIR="$(mktemp -d)"
cleanup() {
  local rc=$?
  rm -f "$PID_FILE"
  rm -rf "$TMP_DIR"
  if [[ -n "$PYTHON_SHIM_DIR" ]]; then
    rm -rf "$PYTHON_SHIM_DIR"
  fi
  if [[ "$rc" -eq 0 ]]; then
    echo "===== $(date -Iseconds) build end (success) ====="
  else
    echo "===== $(date -Iseconds) build end (failure rc=$rc) ====="
  fi
}
trap cleanup EXIT

ensure_python_compat() {
  if command -v python >/dev/null 2>&1; then
    return
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: neither python nor python3 found in PATH." >&2
    exit 1
  fi

  PYTHON_SHIM_DIR="$(mktemp -d)"
  ln -sf "$(command -v python3)" "$PYTHON_SHIM_DIR/python"
  export PATH="$PYTHON_SHIM_DIR:$PATH"
}

compiler_smoke_test() {
  local compiler="$1"
  local smoke_dir
  smoke_dir="$(mktemp -d)"
  cat > "$smoke_dir/test.c" <<'EOF'
int main(void) { return 0; }
EOF
  if "$compiler" -c "$smoke_dir/test.c" -o "$smoke_dir/test.o" >/dev/null 2>&1; then
    rm -rf "$smoke_dir"
    return 0
  fi
  rm -rf "$smoke_dir"
  return 1
}

configure_toolchain() {
  local original_path="$PATH"
  export ARCH=arm64
  export CROSS_COMPILE=aarch64-linux-gnu-

  if [[ "$TOOLCHAIN_MODE" != "system" ]]; then
    if [[ ! -d "$TOOLCHAIN_DIR/bin" ]]; then
      rm -rf "$TOOLCHAIN_DIR"
      git clone --depth=1 "$TOOLCHAIN_REPO_URL" "$TOOLCHAIN_DIR"
    fi
  fi

  if [[ "$TOOLCHAIN_MODE" == "linaro" ]]; then
    export PATH="$TOOLCHAIN_DIR/bin:$original_path"
    if ! compiler_smoke_test "${CROSS_COMPILE}gcc"; then
      echo "Error: bundled Linaro toolchain failed smoke test." >&2
      echo "Hint: try --toolchain system and install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu." >&2
      exit 1
    fi
    return
  fi

  if [[ "$TOOLCHAIN_MODE" == "system" ]]; then
    if ! command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
      echo "Error: system compiler ${CROSS_COMPILE}gcc not found." >&2
      echo "Install: sudo apt install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu" >&2
      exit 1
    fi
    export PATH="$original_path"
    if ! compiler_smoke_test "${CROSS_COMPILE}gcc"; then
      echo "Error: system cross-compiler failed smoke test." >&2
      exit 1
    fi
    return
  fi

  export PATH="$TOOLCHAIN_DIR/bin:$original_path"
  if compiler_smoke_test "${CROSS_COMPILE}gcc"; then
    echo "Using bundled Linaro toolchain."
    return
  fi

  echo "Bundled Linaro toolchain failed smoke test, trying system toolchain..."
  export PATH="$original_path"
  if command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1 && compiler_smoke_test "${CROSS_COMPILE}gcc"; then
    echo "Using system cross-compiler toolchain."
    return
  fi

  echo "Error: no working cross-compiler found." >&2
  echo "Install: sudo apt install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu" >&2
  exit 1
}

if [[ "$REFRESH_KERNEL" == "yes" ]]; then
  rm -rf "$KERNEL_DIR"
fi

if [[ ! -d "$KERNEL_DIR/.git" ]]; then
  git clone --recursive --depth=1 "$KERNEL_REPO_URL" "$KERNEL_DIR"
fi

fetch_logo_to_file "$LOGO_INPUT" "$TMP_DIR/logo.png"
if [[ "$UPDATE_HDMI" == "yes" ]]; then
  fetch_logo_to_file "$HDMI_LOGO_INPUT" "$TMP_DIR/hdmi_logo.png"
fi

pushd "$KERNEL_DIR" >/dev/null

pngtopnm "$TMP_DIR/logo.png" | ppmquant 224 | pnmnoraw > drivers/video/logo/logo_linux_clut224.ppm
if [[ "$UPDATE_HDMI" == "yes" ]]; then
  pngtopnm "$TMP_DIR/hdmi_logo.png" | ppmquant 224 | pnmnoraw > drivers/video/logo/logo_hdmi_clut224.ppm
fi

configure_toolchain
ensure_python_compat

make rk3566_optimized_linux_defconfig
CFLAGS=-Wno-deprecated-declarations make -j"$JOBS" KERNEL_DTS=rk3566 KERNEL_CONFIG=rk3566_optimized_linux_defconfig Image dtbs modules

KERNEL_RELEASE="$(make -s kernelrelease)"
KERNEL_COMMIT="$(git rev-parse --short HEAD)"

DTB_SRC="arch/arm64/boot/dts/rockchip/rk3566.dtb"
if [[ ! -f "$DTB_SRC" ]]; then
  echo "Error: expected DTB not found at $DTB_SRC" >&2
  exit 1
fi

MODULES_STAGE="$TMP_DIR/modules-stage"
rm -rf "$MODULES_STAGE"
make -j"$JOBS" modules_install INSTALL_MOD_PATH="$MODULES_STAGE"

IMAGE_OUT="$OUTPUT_DIR/Image"
DTB_OUT="$OUTPUT_DIR/rk3566.dtb"
IMAGE_META_OUT="$OUTPUT_DIR/Image.meta"
BUNDLE_META_OUT="$OUTPUT_DIR/bundle.meta"
MODULES_TAR_OUT="$OUTPUT_DIR/modules-${KERNEL_RELEASE}.tar.xz"

cp -f arch/arm64/boot/Image "$IMAGE_OUT"
cp -f "$DTB_SRC" "$DTB_OUT"
tar -C "$MODULES_STAGE" -cJf "$MODULES_TAR_OUT" "lib/modules/${KERNEL_RELEASE}"

IMAGE_SHA="$(sha256sum "$IMAGE_OUT" | awk '{print $1}')"
DTB_SHA="$(sha256sum "$DTB_OUT" | awk '{print $1}')"
MODULES_SHA="$(sha256sum "$MODULES_TAR_OUT" | awk '{print $1}')"

cat > "$IMAGE_META_OUT" <<EOF
kernel_release=${KERNEL_RELEASE}
kernel_repo=${KERNEL_REPO_URL}
kernel_commit=${KERNEL_COMMIT}
image_sha256=${IMAGE_SHA}
built_at=$(date -Iseconds)
EOF

cat > "$BUNDLE_META_OUT" <<EOF
kernel_release=${KERNEL_RELEASE}
kernel_repo=${KERNEL_REPO_URL}
kernel_commit=${KERNEL_COMMIT}
image=Image
dtb=rk3566.dtb
modules_archive=$(basename "$MODULES_TAR_OUT")
initramfs=none
uinitrd=not-generated
image_sha256=${IMAGE_SHA}
dtb_sha256=${DTB_SHA}
modules_sha256=${MODULES_SHA}
built_at=$(date -Iseconds)
EOF

popd >/dev/null

echo "Bundle generated at: $OUTPUT_DIR"
echo "  - $IMAGE_OUT"
echo "  - $DTB_OUT"
echo "  - $MODULES_TAR_OUT"
echo "  - $IMAGE_META_OUT"
echo "  - $BUNDLE_META_OUT"