# Reproducible Distribution Guide (RG353V)

This document describes the end-to-end, reproducible release pipeline for MaiaLinux on top of ArkOS.
All commands are intended to be run from the repository root.

## 1. Host Requirements

Ubuntu/Debian host with:

- `bash`, `git`, `python3`, `xz-utils`, `coreutils`, `rsync`
- `e2fsprogs` (`e2fsck`, `resize2fs`, `debugfs`)
- `util-linux` (`sfdisk`, `lsblk`)
- `qemu-utils` (`qemu-img`)
- `mtools`
- Build dependencies for kernel builds (`build-essential`, `bc`, `netpbm`, `imagemagick`, `wget`)

Install host dependencies:

```bash
sudo apt update
sudo apt install -y \
  bash git python3 rsync xz-utils coreutils \
  e2fsprogs util-linux qemu-utils mtools \
  build-essential bc netpbm imagemagick wget \
  gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
```

## 2. Fetch Upstream Inputs (Automated)

Fetch or stage all upstream assets (ArkOS base image + kernel/toolchain source trees):

```bash
make fetch-upstreams ARKOS_IMAGE_URL="https://<upstream>/ArkOS_RG353V_*.img.xz"
```

Alternative: use a local ArkOS image file:

```bash
make fetch-upstreams LOCAL_BASE_IMG="/path/to/ArkOS_RG353V_*.img"
```

Resulting assets:

- `.cache/upstream/ArkOS_RG353V_v2.0_02092025.img`
- `.cache/upstream/sources/RG353VKernel/`
- `.cache/upstream/sources/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu/`
- `.cache/upstream/upstream-manifest.txt`

## 3. Stage Vendor Runtime Libraries (Mali + Wayland EGL)

MaiaLinux preserves RG353V Mali userspace compatibility. Stage required vendor/runtime files from a mounted customized ArkOS rootfs:

```bash
make stage-vendor-libs ROOTFS=/media/$USER/root1
```

Resulting staged assets:

- `vendor/mali/aarch64/libmali-bifrost-g52-g2p0-gbm.so`
- `vendor/mali/armhf/libmali-bifrost-g52-g2p0-gbm.so` (if present)
- `vendor/runtime/lib/libwayland-egl.so.1.0.0`
- `vendor/vendor-libs-manifest.txt`

## 4. Build Reproducible Kernel Bundle (4.19.172)

Build the supported RG353V kernel bundle from source:

```bash
make build-kernel4-bundle
```

Generated outputs:

- `distro/kernel-rg353v-4.19.172/Image`
- `distro/kernel-rg353v-4.19.172/rk3566.dtb`
- `distro/kernel-rg353v-4.19.172/modules-<release>.tar.xz`
- `distro/kernel-rg353v-4.19.172/Image.meta`
- `distro/kernel-rg353v-4.19.172/bundle.meta`

This is reproducible from:

- Upstream kernel repo URL + commit hash
- Source artwork files
- Toolchain mode and metadata written by the build script

## 5. Build Distribution Images

Build release artifacts in `distro/`:

```bash
make build-distro
```

Outputs:

- `distro/MaiaLinux-RG353V-v1.0.0-sdcard.img.xz`
- `distro/MaiaLinux-RG353V-v1.0.0-sdcard.img.xz.sha256`
- `distro/MaiaLinux-RG353V-v1.0.0-qemu.qcow2`
- `distro/MaiaLinux-RG353V-v1.0.0-qemu.qcow2.sha256`
- `distro/MaiaLinux-RG353V-v1.0.0-qemu-launcher.tar.xz`
- `distro/MaiaLinux-RG353V-v1.0.0-qemu-launcher.tar.xz.sha256`

## 6. One-Command Orchestration

For an integrated build sequence (fetch inputs + stage vendor libs + kernel bundle + distro images):

```bash
make build-release \
  ARKOS_IMAGE_URL="https://<upstream>/ArkOS_RG353V_*.img.xz" \
  ROOTFS=/media/$USER/root1
```

## 7. Verification Checklist

Run these checks before publishing artifacts:

```bash
sha256sum distro/*.sha256
ls -lh distro/MaiaLinux-RG353V-v1.0.0-*
cat .cache/upstream/upstream-manifest.txt
cat vendor/vendor-libs-manifest.txt
cat distro/kernel-rg353v-4.19.172/bundle.meta
```

## 8. Notes

- If you update the kernel logos/artwork, rebuild the kernel bundle before `build-distro`.
- If upstream ArkOS base image changes, update `ARKOS_IMAGE_URL` and rerun:

  ```bash
  ./scripts/host/fetch-upstream-assets.sh --refresh --arkos-url "https://<upstream>/ArkOS_RG353V_*.img.xz"
  ```
- Vendor GPU/runtime blobs are device-specific compatibility artifacts and must be staged from a valid RG353V-compatible rootfs.

## 9. MaiaLinux v1.1.0 Kernel 5.10 Track (dArkOS-Compatible)

For MaiaLinux 1.1.0, we keep the same bundle model (`Image + rk3566.dtb + modules`) but build from a Rockchip/RG353V-compatible 5.10 source tree.

### 9.1 Build from Local Kernel 5.10 Source (recommended)

```bash
make build-kernel5-bundle \
  KERNEL5_SOURCE_DIR=/path/to/linux-rk356x-5.10
```

### 9.2 Build from dArkOS/other git source

```bash
./scripts/host/build-rg353v-kernel5-bundle.sh \
  --kernel-repo-url "https://github.com/<org>/<repo>.git" \
  --kernel-repo-ref "<branch-or-tag>"
```

The script auto-falls back across common RK3566 defconfigs if the requested one is unavailable.

### 9.3 Kernel 5.10 Outputs

- `distro/kernel-rg353v-5.10/Image`
- `distro/kernel-rg353v-5.10/rk3566.dtb`
- `distro/kernel-rg353v-5.10/modules-<release>.tar.xz`
- `distro/kernel-rg353v-5.10/Image.meta`
- `distro/kernel-rg353v-5.10/bundle.meta`

### 9.4 Deploy Kernel 5.10 Bundle

```bash
make deploy-kernel5-bundle
```

### 9.5 Full Release Pipeline with Kernel 5.10

```bash
make build-release-kernel5 \
  ARKOS_IMAGE_URL="https://<upstream>/ArkOS_RG353V_*.img.xz" \
  ROOTFS=/media/$USER/root1 \
  KERNEL5_SOURCE_DIR=/path/to/linux-rk356x-5.10
```
