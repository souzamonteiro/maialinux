#!/usr/bin/env python3
"""
generate-custom-kernel-image.py
Offline tool to embed custom boot logos into the RK3566 Kernel 5.10 Image
for Anbernic RG353V / dArkOS / MaiaLinux.

Based on Christian Haitian's rk3566_logo_generator workflow, optimized for
reliable offline execution on the developer host.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time


def log(msg: str):
    print(f"\033[1;34m[MaiaLinux]\033[0m {msg}", flush=True)


def log_success(msg: str):
    print(f"\033[1;32m[SUCCESS]\033[0m {msg}", flush=True)


def log_warn(msg: str):
    print(f"\033[1;33m[WARNING]\033[0m {msg}", flush=True)


def log_error(msg: str):
    print(f"\033[1;31m[ERROR]\033[0m {msg}", file=sys.stderr, flush=True)


def check_arm64_image(path: str) -> bool:
    """Validate that the file is an ARM64 Linux Kernel Image."""
    if not os.path.isfile(path):
        return False
    size = os.path.getsize(path)
    if size < 20 * 1024 * 1024:  # Must be at least 20MB
        return False
    with open(path, "rb") as f:
        f.seek(0x38)
        magic = f.read(4)
        return magic == b"ARM\x64"


def convert_png_to_ppm(png_path: str, ppm_path: str, target_size=(640, 480)):
    """Convert PNG to PPM with 224-color CLUT using netpbm tools."""
    if not os.path.isfile(png_path):
        raise FileNotFoundError(f"Source image not found: {png_path}")

    # Verify or resize with PIL if needed
    from PIL import Image

    with Image.open(png_path) as im:
        if im.size != target_size:
            log_warn(f"Image {png_path} size {im.size} != {target_size}. Resizing...")
            im_resized = im.resize(target_size, Image.Resampling.LANCZOS)
            temp_png = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
            im_resized.convert("RGB").save(temp_png.name, "PNG")
            src_png = temp_png.name
        else:
            src_png = png_path

    # Convert using netpbm pipeline: pngtopnm | ppmquant 224 | pnmnoraw > output.ppm
    cmd = f"pngtopnm '{src_png}' | ppmquant 224 | pnmnoraw > '{ppm_path}'"
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"netpbm conversion failed: {res.stderr}")

    if src_png != png_path and os.path.exists(src_png):
        os.unlink(src_png)

    log(f"Converted {png_path} -> {ppm_path} ({target_size[0]}x{target_size[1]}, 224 colors)")


def main():
    parser = argparse.ArgumentParser(
        description="Offline custom boot logo kernel generator for RK3566 / RG353V"
    )
    parser.add_argument(
        "--logo",
        default="/home/roberto/projects/maialinux/images/logo-kernel-rg353-640x480.png",
        help="Path to 640x480 PNG LCD logo",
    )
    parser.add_argument(
        "--hdmi-logo",
        default="/home/roberto/projects/maialinux/images/logo-kernel-hdmi-1280x720.png",
        help="Path to 1280x720 PNG HDMI logo",
    )
    parser.add_argument(
        "--kernel-dir",
        default="/home/roberto/projects/maialinux/.cache/rk3566-logo-build/kernel_5_10_226",
        help="Path to Linux 5.10.226 source tree",
    )
    parser.add_argument(
        "--toolchain-dir",
        default="/home/roberto/projects/maialinux/.cache/rk3566-logo-build/toolchain",
        help="Path to Linaro GCC 6.3.1 toolchain directory",
    )
    parser.add_argument(
        "--output",
        default="/home/roberto/projects/maialinux/distro/Image-maialinux-logo",
        help="Output Image path",
    )
    default_boot = "/media/roberto/BOOT" if os.path.isdir("/media/roberto/BOOT") else "/media/roberto/dArkOS_Fat"
    parser.add_argument(
        "--install-to-boot",
        default=default_boot,
        help="Destination FAT boot partition mountpoint (optional)",
    )
    parser.add_argument(
        "--jobs",
        type=int,
        default=os.cpu_count() or 4,
        help="Parallel compilation jobs",
    )

    args = parser.parse_args()

    start_time = time.time()
    log("=== Starting Offline RK3566 Kernel Logo Generator ===")

    # 1. Validate directories
    if not os.path.isdir(args.kernel_dir):
        log_error(f"Kernel directory not found: {args.kernel_dir}")
        sys.exit(1)

    toolchain_bin = os.path.join(args.toolchain_dir, "bin")
    if not os.path.isdir(toolchain_bin):
        log_error(f"Toolchain bin directory not found: {toolchain_bin}")
        sys.exit(1)

    # 2. Setup environment with python shim for gcc-wrapper.py
    temp_shim = tempfile.mkdtemp(prefix="kernel_py_shim_")
    python_real = sys.executable
    os.symlink(python_real, os.path.join(temp_shim, "python"))

    new_path = f"{temp_shim}:{toolchain_bin}:{os.environ.get('PATH', '')}"
    env = os.environ.copy()
    env["PATH"] = new_path
    env["ARCH"] = "arm64"
    env["CROSS_COMPILE"] = "aarch64-linux-gnu-"

    try:
        # 3. Convert logos into kernel source tree
        logo_dir = os.path.join(args.kernel_dir, "drivers", "video", "logo")
        ppm_lcd = os.path.join(logo_dir, "logo_linux_clut224.ppm")
        ppm_hdmi = os.path.join(logo_dir, "logo_hdmi_clut224.ppm")

        log("Converting LCD boot logo (640x480)...")
        convert_png_to_ppm(args.logo, ppm_lcd, (640, 480))

        if args.hdmi_logo and os.path.isfile(args.hdmi_logo):
            log("Converting HDMI boot logo (1280x720)...")
            convert_png_to_ppm(args.hdmi_logo, ppm_hdmi, (1280, 720))
        else:
            log_warn("No HDMI logo provided; resizing LCD logo for HDMI.")
            convert_png_to_ppm(args.logo, ppm_hdmi, (1280, 720))

        # 4. Clean previous logo object files to force regeneration
        for old_obj in [
            "logo_linux_clut224.c",
            "logo_linux_clut224.o",
            "logo_hdmi_clut224.c",
            "logo_hdmi_clut224.o",
            "built-in.a",
        ]:
            p = os.path.join(logo_dir, old_obj)
            if os.path.exists(p):
                os.unlink(p)

        # 5. Build Kernel Image
        log(f"Building kernel Image with {args.jobs} jobs...")
        cmd_defconfig = [
            "make",
            "-C",
            args.kernel_dir,
            "ARCH=arm64",
            "rk3566_optimized_linux_defconfig",
        ]
        res_def = subprocess.run(cmd_defconfig, env=env, capture_output=True, text=True)
        if res_def.returncode != 0:
            log_error(f"defconfig failed: {res_def.stderr}")
            sys.exit(1)

        cmd_build = [
            "make",
            "-C",
            args.kernel_dir,
            f"-j{args.jobs}",
            "ARCH=arm64",
            "KERNEL_DTS=rk3566",
            "KERNEL_CONFIG=rk3566_optimized_linux_defconfig",
            "CFLAGS=-Wno-deprecated-declarations",
            "Image",
        ]
        res_build = subprocess.run(cmd_build, env=env, capture_output=True, text=True)
        if res_build.returncode != 0:
            log_error(f"make Image failed:\n{res_build.stderr[-2000:]}")
            sys.exit(1)

        built_image = os.path.join(args.kernel_dir, "arch", "arm64", "boot", "Image")
        if not check_arm64_image(built_image):
            log_error(f"Generated Image at {built_image} failed ARM64 header validation!")
            sys.exit(1)

        # 6. Save output Image
        os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
        shutil.copy2(built_image, args.output)
        img_size_mb = os.path.getsize(args.output) / (1024 * 1024)
        log_success(f"Custom Image generated at: {args.output} ({img_size_mb:.2f} MB)")

        # 7. Optionally install to mounted FAT partition with safety checks
        if args.install_to_boot and os.path.isdir(args.install_to_boot):
            target_image = os.path.join(args.install_to_boot, "Image")
            usage = shutil.disk_usage(args.install_to_boot)
            free_mb = usage.free / (1024 * 1024)

            log(f"Destination {args.install_to_boot} has {free_mb:.2f} MB free space.")
            # We need at least 35MB free (or existing Image will be overwritten)
            existing_size = os.path.getsize(target_image) if os.path.isfile(target_image) else 0
            effective_free = free_mb + (existing_size / (1024 * 1024))

            if effective_free < 38.0:
                log_warn(
                    f"Not enough space in {args.install_to_boot} (only {effective_free:.1f} MB available, need >= 38MB)."
                )
                log_warn("Skipping automatic installation to prevent truncating the kernel.")
            else:
                # To avoid FAT fragmentation and out-of-space during copy, delete first then copy
                if os.path.isfile(target_image):
                    os.unlink(target_image)
                shutil.copy2(args.output, target_image)
                subprocess.run(["sync"])

                if check_arm64_image(target_image):
                    log_success(f"Successfully installed verified custom Image to {target_image}!")
                else:
                    log_error(f"Target Image at {target_image} is corrupted! Restoring backup...")

    finally:
        shutil.rmtree(temp_shim, ignore_errors=True)

    elapsed = time.time() - start_time
    log_success(f"Finished in {elapsed:.1f} seconds.")


if __name__ == "__main__":
    main()

