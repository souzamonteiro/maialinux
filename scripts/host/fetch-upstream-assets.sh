#!/usr/bin/env bash
# fetch-upstream-assets.sh
# Downloads or stages upstream assets needed to rebuild MaiaLinux release artifacts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

UPSTREAM_DIR="$REPO_ROOT/.cache/upstream"
BASE_IMAGE_NAME="ArkOS_RG353V_v2.0_02092025.img"
BASE_IMAGE_PATH="$UPSTREAM_DIR/$BASE_IMAGE_NAME"
ARKOS_IMAGE_URL="${ARKOS_IMAGE_URL:-}"
ARKOS_IMAGE_SHA256="${ARKOS_IMAGE_SHA256:-}"
LOCAL_BASE_IMAGE=""
REFRESH="no"

KERNEL_REPO_URL="https://github.com/christianhaitian/RG353VKernel.git"
TOOLCHAIN_REPO_URL="https://github.com/christianhaitian/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu.git"

usage() {
  cat <<'EOF'
Usage:
  scripts/host/fetch-upstream-assets.sh [options]

Options:
  --upstream-dir <path>       Cache/output directory (default: .cache/upstream)
  --base-image-name <name>    Output base image filename (default: ArkOS_RG353V_v2.0_02092025.img)
  --base-image <path>         Use existing local ArkOS .img as source (copied into upstream dir)
  --arkos-url <url>           Download ArkOS image (.img or .img.xz) from URL
  --arkos-sha256 <sha256>     Expected SHA256 for downloaded file (optional)
  --refresh                   Re-download/re-clone all upstream assets
  -h, --help                  Show this help

Environment alternatives:
  ARKOS_IMAGE_URL=<url>
  ARKOS_IMAGE_SHA256=<sha256>

Outputs:
  .cache/upstream/ArkOS_RG353V_v2.0_02092025.img
  .cache/upstream/sources/RG353VKernel/
  .cache/upstream/sources/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu/
  .cache/upstream/upstream-manifest.txt
EOF
}

abspath() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "$PWD/$path"
  fi
}

download_file() {
  local url="$1"
  local out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -L --fail --retry 3 --connect-timeout 20 "$url" -o "$out"
  elif command -v wget >/dev/null 2>&1; then
    wget -t 3 -T 60 "$url" -O "$out"
  else
    echo "Error: neither curl nor wget is available." >&2
    exit 1
  fi
}

verify_sha256() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(sha256sum "$file" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "Error: SHA256 mismatch for $file" >&2
    echo "Expected: $expected" >&2
    echo "Actual:   $actual" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --upstream-dir)
      UPSTREAM_DIR="${2:-}"
      shift 2
      ;;
    --base-image-name)
      BASE_IMAGE_NAME="${2:-}"
      shift 2
      ;;
    --base-image)
      LOCAL_BASE_IMAGE="${2:-}"
      shift 2
      ;;
    --arkos-url)
      ARKOS_IMAGE_URL="${2:-}"
      shift 2
      ;;
    --arkos-sha256)
      ARKOS_IMAGE_SHA256="${2:-}"
      shift 2
      ;;
    --refresh)
      REFRESH="yes"
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

UPSTREAM_DIR="$(abspath "$UPSTREAM_DIR")"
BASE_IMAGE_PATH="$UPSTREAM_DIR/$BASE_IMAGE_NAME"
SOURCES_DIR="$UPSTREAM_DIR/sources"
KERNEL_DIR="$SOURCES_DIR/RG353VKernel"
TOOLCHAIN_DIR="$SOURCES_DIR/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu"

mkdir -p "$UPSTREAM_DIR" "$SOURCES_DIR"

if [[ "$REFRESH" == "yes" ]]; then
  rm -f "$BASE_IMAGE_PATH" "$UPSTREAM_DIR"/*.img.xz "$UPSTREAM_DIR"/*.download
  rm -rf "$KERNEL_DIR" "$TOOLCHAIN_DIR"
fi

if [[ ! -f "$BASE_IMAGE_PATH" ]]; then
  if [[ -n "$LOCAL_BASE_IMAGE" ]]; then
    LOCAL_BASE_IMAGE="$(abspath "$LOCAL_BASE_IMAGE")"
    if [[ ! -f "$LOCAL_BASE_IMAGE" ]]; then
      echo "Error: local base image not found: $LOCAL_BASE_IMAGE" >&2
      exit 1
    fi
    echo "==> Staging local base image: $LOCAL_BASE_IMAGE"
    cp -f "$LOCAL_BASE_IMAGE" "$BASE_IMAGE_PATH"
  elif [[ -n "$ARKOS_IMAGE_URL" ]]; then
    tmp_file="$UPSTREAM_DIR/$(basename "$ARKOS_IMAGE_URL").download"
    echo "==> Downloading ArkOS base image: $ARKOS_IMAGE_URL"
    download_file "$ARKOS_IMAGE_URL" "$tmp_file"

    if [[ -n "$ARKOS_IMAGE_SHA256" ]]; then
      verify_sha256 "$tmp_file" "$ARKOS_IMAGE_SHA256"
    fi

    case "$ARKOS_IMAGE_URL" in
      *.img.xz|*.xz)
        echo "==> Extracting ArkOS image to $BASE_IMAGE_PATH"
        xz -dc "$tmp_file" > "$BASE_IMAGE_PATH"
        ;;
      *.img)
        cp -f "$tmp_file" "$BASE_IMAGE_PATH"
        ;;
      *)
        echo "Error: unsupported ArkOS URL extension. Use .img or .img.xz" >&2
        exit 1
        ;;
    esac
    rm -f "$tmp_file"
  else
    cat >&2 <<EOF
Error: no ArkOS base image provided.

Provide one of:
  1) --base-image /path/to/ArkOS_RG353V*.img
  2) --arkos-url https://.../ArkOS_RG353V*.img.xz
  3) ARKOS_IMAGE_URL environment variable
EOF
    exit 1
  fi
fi

if [[ ! -d "$KERNEL_DIR/.git" ]]; then
  echo "==> Cloning RG353V kernel source"
  git clone --recursive --depth=1 "$KERNEL_REPO_URL" "$KERNEL_DIR"
fi

if [[ ! -d "$TOOLCHAIN_DIR/bin" ]]; then
  echo "==> Cloning Linaro cross-toolchain"
  git clone --depth=1 "$TOOLCHAIN_REPO_URL" "$TOOLCHAIN_DIR"
fi

manifest="$UPSTREAM_DIR/upstream-manifest.txt"
{
  echo "generated_at=$(date -Iseconds)"
  echo "base_image=$BASE_IMAGE_PATH"
  echo "base_image_sha256=$(sha256sum "$BASE_IMAGE_PATH" | awk '{print $1}')"
  echo "kernel_repo=$KERNEL_REPO_URL"
  echo "kernel_commit=$(git -C "$KERNEL_DIR" rev-parse HEAD)"
  echo "toolchain_repo=$TOOLCHAIN_REPO_URL"
  echo "toolchain_commit=$(git -C "$TOOLCHAIN_DIR" rev-parse HEAD)"
} > "$manifest"

echo "==> Upstream assets ready"
echo "    BASE_IMG=$BASE_IMAGE_PATH"
echo "    Manifest: $manifest"
