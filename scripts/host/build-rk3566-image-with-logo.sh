#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

abspath_from_repo() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    printf '%s\n' "$p"
  else
    printf '%s\n' "$REPO_ROOT/$p"
  fi
}

KERNEL_REPO_URL="https://github.com/christianhaitian/kernel_5_10_226.git"
TOOLCHAIN_REPO_URL="https://github.com/christianhaitian/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu.git"

WORK_ROOT_DEFAULT="$REPO_ROOT/.cache/rk3566-logo-build"
WORK_ROOT="$WORK_ROOT_DEFAULT"
KERNEL_DIR=""
TOOLCHAIN_DIR=""
OUTPUT_IMAGE="$REPO_ROOT/distro/Image-custom-logo"
OUTPUT_META=""
LOG_FILE=""
PID_FILE=""
LOGO_INPUT="$REPO_ROOT/images/logo-kernel-rg353-640x480.png"
HDMI_LOGO_INPUT="$REPO_ROOT/images/logo-kernel-hdmi-1280x720.png"
UPDATE_HDMI="yes"
INSTALL_DEPS="no"
REFRESH_KERNEL="no"
JOBS="$(nproc)"
TOOLCHAIN_MODE="auto"
PYTHON_SHIM_DIR=""

usage() {
  cat <<'EOF'
Usage:
  scripts/host/build-rk3566-image-with-logo.sh [--logo <png-or-url>] [options]

Default assets:
  --logo defaults to images/logo-kernel-rg353-640x480.png
  --hdmi-logo defaults to images/logo-kernel-hdmi-1280x720.png

Options:
  --logo <path|url>           LCD logo source (640x480 PNG recommended)
  --update-hdmi <yes|no>      Also replace HDMI logo (default: yes)
  --hdmi-logo <path|url>      HDMI logo source (1280x720 PNG recommended)
  --output <path>             Output Image path (default: distro/Image-custom-logo)
  --work-root <path>          Build/cache directory (default: .cache/rk3566-logo-build)
  --jobs <n>                  Parallel build jobs (default: nproc)
  --toolchain <auto|linaro|system>
                               Toolchain selection (default: auto)
  --refresh-kernel            Re-clone kernel repo before build
  --install-deps              Install apt dependencies automatically
  -h, --help                  Show this help

Examples:
  scripts/host/build-rk3566-image-with-logo.sh \
    --logo images/logo-kernel-rg353-640x480.png \
    --update-hdmi yes \
    --hdmi-logo images/logo-kernel-hdmi-1280x720.png \
    --output distro/Image
EOF
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
    --output)
      OUTPUT_IMAGE="${2:-}"
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

if [[ -z "$LOGO_INPUT" ]]; then
  LOGO_INPUT="$REPO_ROOT/images/logo-kernel-rg353-640x480.png"
fi

if [[ -z "$HDMI_LOGO_INPUT" ]]; then
  HDMI_LOGO_INPUT="$REPO_ROOT/images/logo-kernel-hdmi-1280x720.png"
fi

if [[ ! -f "$LOGO_INPUT" && ! "$LOGO_INPUT" =~ ^https?:// ]]; then
  echo "Error: logo source not found: $LOGO_INPUT" >&2
  usage >&2
  exit 1
fi

if [[ "$UPDATE_HDMI" != "yes" && "$UPDATE_HDMI" != "no" ]]; then
  echo "Error: --update-hdmi must be 'yes' or 'no'." >&2
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

if [[ "$UPDATE_HDMI" == "yes" && -z "$HDMI_LOGO_INPUT" ]] && ! command -v convert >/dev/null 2>&1; then
  echo "Error: provide --hdmi-logo or install ImageMagick (command: convert)." >&2
  exit 1
fi

WORK_ROOT="$(abspath_from_repo "$WORK_ROOT")"
OUTPUT_IMAGE="$(abspath_from_repo "$OUTPUT_IMAGE")"
OUTPUT_META="${OUTPUT_IMAGE}.meta"

KERNEL_DIR="$WORK_ROOT/kernel_5_10_226"
TOOLCHAIN_DIR="$WORK_ROOT/toolchain"
LOG_FILE="$WORK_ROOT/build.log"
PID_FILE="$WORK_ROOT/build.pid"

install_dependencies() {
  sudo apt -y update
  sudo apt -y install \
    build-essential git lzop gcc bc libncurses5-dev libc6-i386 lib32stdc++6 \
    zlib1g netpbm wget imagemagick gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu python3
}

ensure_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd" >&2
    return 1
  fi
}

check_dependencies() {
  local missing=0
  for cmd in git make wget pngtopnm ppmquant pnmnoraw python3; do
    if ! ensure_command "$cmd"; then
      missing=1
    fi
  done
  if [[ "$missing" -eq 1 ]]; then
    echo "Install dependencies with: sudo apt install build-essential git lzop gcc bc libncurses5-dev libc6-i386 lib32stdc++6 zlib1g netpbm wget imagemagick gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu python3" >&2
    exit 1
  fi
}

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
  export ARCH=arm64
  export CROSS_COMPILE=aarch64-linux-gnu-

  local original_path="$PATH"

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

  # auto: try bundled Linaro first, then fallback to system cross compiler.
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
  local real_logo=""

  if local_path="$(resolve_local_file "$input")"; then
    cp -f "$local_path" "$output"
    return 0
  fi

  if [[ "$input" == *"pasteboard.co"* ]]; then
    wget -t 3 -T 60 --no-check-certificate "$input" -O page.txt
    real_logo="$(grep 'img data-src="' page.txt | cut -d '"' -f 2 || true)"
    [[ -n "$real_logo" ]] || return 1
    wget -t 3 -T 60 --no-check-certificate "$real_logo" -O "$output"
  elif [[ "$input" == *"ibb.co"* ]]; then
    wget -t 3 -T 60 --no-check-certificate "$input" -O page.txt
    real_logo="$(grep 'og:image" content="' page.txt | cut -d '"' -f 4 || true)"
    [[ -n "$real_logo" ]] || return 1
    wget -t 3 -T 60 --no-check-certificate "$real_logo" -O "$output"
  else
    wget -t 3 -T 60 --no-check-certificate "$input" -O "$output"
  fi
}

if [[ "$INSTALL_DEPS" == "yes" ]]; then
  install_dependencies
fi
check_dependencies

mkdir -p "$WORK_ROOT"

if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    echo "Error: another build process is running (pid $old_pid)." >&2
    echo "Monitor with: ./scripts/host/monitor-rk3566-logo-build.sh --watch" >&2
    exit 1
  fi
fi

touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "===== $(date -Iseconds) build start ====="
echo "WORK_ROOT=$WORK_ROOT"
echo "OUTPUT_IMAGE=$OUTPUT_IMAGE"
echo "TOOLCHAIN_MODE=$TOOLCHAIN_MODE"
echo "$$" > "$PID_FILE"

if [[ "$REFRESH_KERNEL" == "yes" ]]; then
  rm -rf "$KERNEL_DIR"
fi

if [[ ! -d "$KERNEL_DIR/.git" ]]; then
  git clone --recursive --depth=1 "$KERNEL_REPO_URL" "$KERNEL_DIR"
fi

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

fetch_logo_to_file "$LOGO_INPUT" "$TMP_DIR/logo.png" || {
  echo "Error: failed to get logo from '$LOGO_INPUT'." >&2
  exit 1
}

if [[ "$UPDATE_HDMI" == "yes" ]]; then
  if [[ -n "$HDMI_LOGO_INPUT" ]]; then
    fetch_logo_to_file "$HDMI_LOGO_INPUT" "$TMP_DIR/hdmi_logo.png" || {
      echo "Error: failed to get HDMI logo from '$HDMI_LOGO_INPUT'." >&2
      exit 1
    }
  else
    if [[ -f "$REPO_ROOT/images/logo-kernel-hdmi-1280x720.png" ]]; then
      cp -f "$REPO_ROOT/images/logo-kernel-hdmi-1280x720.png" "$TMP_DIR/hdmi_logo.png"
    else
      convert "$TMP_DIR/logo.png" -resize 1280x720! "$TMP_DIR/hdmi_logo.png"
    fi
  fi
fi

pushd "$KERNEL_DIR" >/dev/null

pngtopnm "$TMP_DIR/logo.png" | ppmquant 224 | pnmnoraw > drivers/video/logo/logo_linux_clut224.ppm
if [[ "$UPDATE_HDMI" == "yes" ]]; then
  pngtopnm "$TMP_DIR/hdmi_logo.png" | ppmquant 224 | pnmnoraw > drivers/video/logo/logo_hdmi_clut224.ppm
fi

configure_toolchain
ensure_python_compat

make ARCH=arm64 rk3566_optimized_linux_defconfig
CFLAGS=-Wno-deprecated-declarations make -j"$JOBS" ARCH=arm64 KERNEL_DTS=rk3566 KERNEL_CONFIG=rk3566_optimized_linux_defconfig

mkdir -p "$(dirname "$OUTPUT_IMAGE")"
cp -f arch/arm64/boot/Image "$OUTPUT_IMAGE"

KERNEL_RELEASE="$(make -s kernelrelease)"
{
  echo "kernel_release=${KERNEL_RELEASE}"
  echo "kernel_repo=${KERNEL_REPO_URL}"
  echo "toolchain_mode=${TOOLCHAIN_MODE}"
  echo "built_at=$(date -Iseconds)"
} > "$OUTPUT_META"

popd >/dev/null

echo "Image generated at: $OUTPUT_IMAGE"
echo "Metadata written at: $OUTPUT_META"
