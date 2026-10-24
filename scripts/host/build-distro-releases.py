#!/usr/bin/env python3
"""
build-distro-releases.py
Builds the two official MaiaLinux distribution artifacts in distro/:
  1) distro/MaiaLinux-RG353V-v1.0.0-sdcard.img.xz  (Flashable GPT SD Card image for Anbernic RG353V)
  2) distro/MaiaLinux-RG353V-v1.0.0-qemu.qcow2     (Compressed QEMU ARM64 image + runner script)

Works entirely in user-space (no root/sudo required) using e2fsprogs (debugfs, resize2fs, e2fsck),
sfdisk, mtools, qemu-img, and xz.
"""

import hashlib
import os
import shutil
import stat
import subprocess
import sys
import time
import tarfile

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
DISTRO_DIR = os.path.join(REPO_ROOT, "distro")
DEFAULT_BASE_IMG = os.path.join(REPO_ROOT, ".cache", "upstream", "ArkOS_RG353V_v2.0_02092025.img")
BASE_IMG = os.environ.get(
    "BASE_IMG",
    DEFAULT_BASE_IMG,
)
SDCARD_ROOT = os.environ.get("SDCARD_ROOT", "/media/roberto/root")
SDCARD_BOOT = os.environ.get("SDCARD_BOOT", "/media/roberto/BOOT")
STAGING_DIR = os.environ.get(
    "STAGING_DIR", os.path.join(REPO_ROOT, ".cache", "distro-build")
)
VENDOR_MALI_AARCH64 = os.path.join(REPO_ROOT, "vendor", "mali", "aarch64", "libmali-bifrost-g52-g2p0-gbm.so")
VENDOR_WAYLAND_EGL = os.path.join(REPO_ROOT, "vendor", "runtime", "lib", "libwayland-egl.so.1.0.0")
KERNEL_BUNDLE_DIR = os.environ.get("KERNEL_BUNDLE_DIR", os.path.join(DISTRO_DIR, "kernel-rg353v-4.19.172"))
KERNEL_IMAGE = os.environ.get("KERNEL_IMAGE", os.path.join(KERNEL_BUNDLE_DIR, "Image"))
KERNEL_DTB = os.environ.get("KERNEL_DTB", os.path.join(KERNEL_BUNDLE_DIR, "rk3566.dtb"))

VERSION = "v1.0.0"
SDCARD_XZ_NAME = f"MaiaLinux-RG353V-{VERSION}-sdcard.img.xz"
QEMU_QCOW2_NAME = f"MaiaLinux-RG353V-{VERSION}-qemu.qcow2"


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def first_existing_file(paths):
    for path in paths:
        if path and os.path.isfile(path):
            return path
    return None


def ensure_mtools() -> str:
    mcopy = shutil.which("mcopy")
    if mcopy:
        return mcopy
    local_mcopy = "/tmp/mtools_root/usr/bin/mcopy"
    if os.path.isfile(local_mcopy):
        return local_mcopy
    log("Downloading mtools in user-space to /tmp/mtools_root...")
    subprocess.run(
        "cd /tmp && apt-get download mtools && dpkg-deb -x /tmp/mtools*.deb /tmp/mtools_root && rm -f /tmp/mtools*.deb",
        shell=True,
        check=True,
    )
    return local_mcopy


def extract_range(src_path: str, dst_path: str, start_lba: int, count_lba: int) -> None:
    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    offset = start_lba * 512
    remaining = count_lba * 512
    buf_size = 16 * 1024 * 1024
    with open(src_path, "rb") as f_in, open(dst_path, "wb") as f_out:
        f_in.seek(offset)
        while remaining > 0:
            chunk = f_in.read(min(buf_size, remaining))
            if not chunk:
                break
            f_out.write(chunk)
            remaining -= len(chunk)
        f_out.flush()


def repository_payload():
    """Files whose inclusion must never depend on mounted filesystem timestamps."""
    files = []
    for root, _, names in os.walk(os.path.join(REPO_ROOT, "examples")):
        for name in names:
            src = os.path.join(root, name)
            dst = "/home/ark/projects/" + os.path.relpath(src, os.path.join(REPO_ROOT, "examples"))
            files.append((src, dst, 1002, 1002, os.stat(src).st_mode))
    mappings = {
        "config/lxqt/lxqt.conf": "/home/ark/.config/lxqt/lxqt.conf",
        "config/lxqt/session.conf": "/home/ark/.config/lxqt/session.conf",
        "config/lxqt/panel.conf": "/home/ark/.config/lxqt/panel.conf",
        "config/geany/geany.conf": "/home/ark/.config/geany/geany.conf",
        "config/systemd/emulationstation.service.d/maialinux.conf": "/etc/systemd/system/emulationstation.service.d/maialinux.conf",
        "config/controls/desktop.gptk": "/etc/maialinux/desktop.gptk",
        "config/xorg/Xwrapper.config": "/etc/X11/Xwrapper.config",
        "config/xorg/10-rockchip-modesetting.conf": "/etc/X11/xorg.conf.d/10-rockchip-modesetting.conf",
        "config/xorg/20-touchscreen.conf": "/etc/X11/xorg.conf.d/20-touchscreen.conf",
    }
    for src, dst in mappings.items():
        uid = 1002 if dst.startswith("/home/ark/") else 0
        files.append((os.path.join(REPO_ROOT, src), dst, uid, uid, 0o100644))
    directories = {}
    for _, dst, uid, gid, _ in files:
        parent = os.path.dirname(dst)
        while parent not in ("/", "/home", "/home/ark", "/etc"):
            directories[parent] = (parent, uid, gid, 0o040755)
            parent = os.path.dirname(parent)
    return list(directories.values()), files


def copy_fat_file_if_present(mcopy: str, part3_img: str, src: str, dst: str) -> bool:
    result = subprocess.run([mcopy, "-o", "-i", part3_img, src, dst], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, check=False)
    if result.returncode == 0:
        return True
    if "File not found" in result.stderr or "not found" in result.stderr.lower():
        log(f"Skipping missing FAT payload {src!r} on boot image ({dst})")
        return False
    raise RuntimeError(f"Failed to copy {src} -> {dst}: {result.stderr.strip() or result.returncode}")


def build_part3_boot(part3_img: str) -> None:
    log("Building Partition 3 (BOOT FAT32) with MaiaLinux logos and firstboot hook...")
    extract_range(BASE_IMG, part3_img, 32768, 204800)

    mcopy = ensure_mtools()
    mdel = os.path.join(os.path.dirname(mcopy), "mdel")
    mmd = os.path.join(os.path.dirname(mcopy), "mmd")

    firstboot = os.path.join(STAGING_DIR, "firstboot.sh")
    with open(firstboot, "w") as script:
        script.write("#!/bin/bash\n/usr/local/bin/maialinux-boot-setup.sh\n")
    boot_files = [
        (firstboot, "::/firstboot.sh"),
        (os.path.join(REPO_ROOT, "config/boot/logo.bmp"), "::/logo.bmp"),
        (os.path.join(REPO_ROOT, "config/boot/logo_kernel.bmp"), "::/logo_kernel.bmp"),
        (os.path.join(REPO_ROOT, "config/boot/logo.bmp"), "::/splash/logo_640x480.bmp"),
        (os.path.join(REPO_ROOT, "config/boot/logo_1920x1080.bmp"), "::/splash/logo_1920x1080.bmp"),
    ]
    for _, dst in boot_files:
        subprocess.run([mdel, "-i", part3_img, dst], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    subprocess.run([mmd, "-D", "s", "-i", part3_img, "::/splash"], stderr=subprocess.DEVNULL)
    for src, dst in boot_files:
        if os.path.isfile(src):
            subprocess.run([mcopy, "-o", "-i", part3_img, src, dst], check=True)

    # Prefer reproducible kernel bundle artifacts when available.
    for target in ("::/Image", "::/rk3566.dtb", "::/uInitrd"):
        subprocess.run([mdel, "-i", part3_img, target], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    if os.path.isfile(KERNEL_IMAGE):
        subprocess.run([mcopy, "-o", "-i", part3_img, KERNEL_IMAGE, "::/Image"], check=True)
    if os.path.isfile(KERNEL_DTB):
        subprocess.run([mcopy, "-o", "-i", part3_img, KERNEL_DTB, "::/rk3566.dtb"], check=True)


def build_part4_rootfs(part4_img: str, extra_sectors: int) -> int:
    orig_sectors = 15208047
    total_sectors = orig_sectors + extra_sectors
    log(f"Extracting base Partition 4 (ext4) to {part4_img}...")
    extract_range(BASE_IMG, part4_img, 237568, orig_sectors)

    log(f"Expanding Partition 4 to {total_sectors * 512 / (1024**3):.2f} GiB...")
    with open(part4_img, "r+b") as f:
        f.truncate(total_sectors * 512)

    subprocess.run(["/usr/sbin/e2fsck", "-f", "-y", part4_img], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["/usr/sbin/resize2fs", part4_img], check=True)

    log("Scanning modified/added MaiaLinux files on mounted SD card rootfs...")
    skip_prefixes = (
        os.path.realpath(STAGING_DIR),
        os.path.join(SDCARD_ROOT, "var/cache/apt"),
        os.path.join(SDCARD_ROOT, "var/lib/apt/lists"),
        os.path.join(SDCARD_ROOT, ".tmp-maialinux-build"),
        os.path.join(SDCARD_ROOT, "etc/maialinux-runtime/.tmp-maialinux-build"),
        os.path.join(SDCARD_ROOT, "home/ark/.config/retroarch"),
        os.path.join(SDCARD_ROOT, "home/ark/.config/ppsspp"),
        os.path.join(SDCARD_ROOT, "home/ark/.config/mupen64plus"),
        os.path.join(SDCARD_ROOT, "home/ark/.config/duckstation"),
        os.path.join(SDCARD_ROOT, "proc"),
        os.path.join(SDCARD_ROOT, "sys"),
        os.path.join(SDCARD_ROOT, "dev"),
        os.path.join(SDCARD_ROOT, "run"),
        os.path.join(SDCARD_ROOT, "tmp"),
    )
    skip_exact = {
        os.path.join(SDCARD_ROOT, "swapfile"),
    }

    dirs_to_create = []
    files_to_write = []
    symlinks_to_create = []

    for root, dirs, files in os.walk(SDCARD_ROOT, topdown=True, followlinks=False):
        dirs[:] = [
            d
            for d in dirs
            if not os.path.join(root, d).startswith(skip_prefixes)
            and os.path.join(root, d) not in skip_exact
        ]
        for d in dirs:
            full_p = os.path.join(root, d)
            rel_p = "/" + os.path.relpath(full_p, SDCARD_ROOT)
            try:
                st = os.lstat(full_p)
            except OSError:
                continue
            if st.st_ctime > 1790000000:
                if stat.S_ISLNK(st.st_mode):
                    try:
                        target = os.readlink(full_p)
                        symlinks_to_create.append((rel_p, target, st.st_uid, st.st_gid))
                    except OSError:
                        pass
                elif stat.S_ISDIR(st.st_mode):
                    dirs_to_create.append((rel_p, st.st_uid, st.st_gid, st.st_mode))

        for name in files:
            full_p = os.path.join(root, name)
            if full_p in skip_exact or full_p.startswith(skip_prefixes):
                continue
            rel_p = "/" + os.path.relpath(full_p, SDCARD_ROOT)
            try:
                st = os.lstat(full_p)
            except OSError:
                continue
            if st.st_ctime > 1790000000:
                if stat.S_ISLNK(st.st_mode):
                    try:
                        target = os.readlink(full_p)
                        symlinks_to_create.append((rel_p, target, st.st_uid, st.st_gid))
                    except OSError:
                        pass
                elif stat.S_ISREG(st.st_mode) and os.access(full_p, os.R_OK):
                    files_to_write.append((full_p, rel_p, st.st_uid, st.st_gid, st.st_mode))

    extra_dirs = [
        ("/etc/plymouth", 0, 0, 0o040755),
        ("/usr/share/plymouth/themes/maialinux", 0, 0, 0o040755),
        ("/usr/share/backgrounds", 0, 0, 0o040755),
        ("/usr/share/backgrounds/maialinux", 0, 0, 0o040755),
        ("/home/ark/Pictures", 1002, 1002, 0o040755),
        ("/home/ark/Pictures/Wallpapers", 1002, 1002, 0o040755),
    ]
    dirs_to_create.extend(extra_dirs)

    for fn in os.listdir(os.path.join(REPO_ROOT, "config/plymouth/maialinux")):
        src = os.path.join(REPO_ROOT, "config/plymouth/maialinux", fn)
        if os.path.isfile(src):
            files_to_write.append((src, f"/usr/share/plymouth/themes/maialinux/{fn}", 0, 0, 0o100644))
    files_to_write.append(
        (os.path.join(REPO_ROOT, "config/plymouth/text.plymouth"), "/usr/share/plymouth/themes/text.plymouth", 0, 0, 0o100644)
    )
    files_to_write.append(
        (os.path.join(REPO_ROOT, "config/plymouth/plymouthd.conf"), "/etc/plymouth/plymouthd.conf", 0, 0, 0o100644)
    )
    files_to_write.append(
        (os.path.join(REPO_ROOT, "config/plymouth/plymouthd.conf"), "/usr/share/plymouth/plymouthd.defaults", 0, 0, 0o100644)
    )
    files_to_write.append(
        (os.path.join(REPO_ROOT, "config/systemd/maialinux-boot-splash.service"), "/etc/systemd/system/maialinux-boot-splash.service", 0, 0, 0o100644)
    )
    symlinks_to_create.append(
        ("/usr/share/plymouth/themes/default.plymouth", "/usr/share/plymouth/themes/maialinux/maialinux.plymouth", 0, 0)
    )

    for fn in os.listdir(os.path.join(REPO_ROOT, "config/wallpapers")):
        src = os.path.join(REPO_ROOT, "config/wallpapers", fn)
        if os.path.isfile(src):
            files_to_write.append((src, f"/usr/share/backgrounds/maialinux/{fn}", 0, 0, 0o100644))
            files_to_write.append((src, f"/home/ark/Pictures/Wallpapers/{fn}", 1002, 1002, 0o100644))

    files_to_write.append(
        (os.path.join(REPO_ROOT, "config/lxqt/pcmanfm-qt-settings.conf"), "/home/ark/.config/pcmanfm-qt/lxqt/settings.conf", 1002, 1002, 0o100644)
    )
    files_to_write.append(
        (os.path.join(REPO_ROOT, "config/lxqt/openbox-lxqt-rc.xml"), "/home/ark/.config/openbox/lxqt-rc.xml", 1002, 1002, 0o100644)
    )
    for fn in os.listdir(os.path.join(REPO_ROOT, "config/desktop-entries")):
        src = os.path.join(REPO_ROOT, "config/desktop-entries", fn)
        if os.path.isfile(src):
            files_to_write.append((src, f"/usr/local/share/applications/{fn}", 0, 0, 0o100755))

    payload_dirs, payload_files = repository_payload()
    dirs_to_create.extend(payload_dirs)
    files_to_write.extend(payload_files)

    # Always inject current repository fixes, rather than stale installed copies.
    for fn in os.listdir(os.path.join(REPO_ROOT, "scripts/target")):
        src = os.path.join(REPO_ROOT, "scripts/target", fn)
        if os.path.isfile(src):
            files_to_write.extend([
                (src, f"/usr/local/bin/{fn}", 0, 0, 0o100755),
                (src, f"/etc/maialinux-runtime/scripts/{fn}", 0, 0, 0o100755),
            ])
    files_to_write.extend([
        (os.path.join(REPO_ROOT, "scripts/target/maialinux-boot-setup.sh"), "/etc/maialinux-runtime/maialinux-boot-setup.sh", 0, 0, 0o100755),
        (os.path.join(REPO_ROOT, "scripts/target/start-maialinux.sh"), "/opt/system/Tools/Launch-MaiaLinux-LXQt.sh", 1002, 1002, 0o100755),
        (os.path.join(REPO_ROOT, "scripts/target/start-maialinux.sh"), "/roms/tools/Launch-MaiaLinux-LXQt.sh", 1002, 1002, 0o100755),
    ])

    symlinks_to_create = [item for item in symlinks_to_create if not item[0].endswith(".target.wants/maialinux-boot-splash.service")]

    # Never distribute the damaged Mali blob or Wayland aliases into libMali.
    mali_backup = first_existing_file([
        os.path.join(SDCARD_ROOT, "opt/maialinux/backup/mali/aarch64/libmali-bifrost-g52-g2p0-gbm.so"),
        os.path.join(SDCARD_ROOT, "usr/lib/aarch64-linux-gnu/libmali-bifrost-g52-g2p0-gbm.so"),
        VENDOR_MALI_AARCH64,
    ])
    if mali_backup is None or os.path.getsize(mali_backup) < 1000000:
        raise RuntimeError(
            "A valid Mali blob is required. Run scripts/host/stage-vendor-libs.sh or provide it in the mounted rootfs."
        )
    files_to_write.append((mali_backup, "/usr/lib/aarch64-linux-gnu/libmali-bifrost-g52-g2p0-gbm.so", 0, 0, 0o100755))
    wayland_dir = "/usr/lib/aarch64-linux-gnu/"
    wayland_names = ("libwayland-egl.so", "libwayland-egl.so.1", "libwayland-egl.so.1.0.0")
    symlinks_to_create = [item for item in symlinks_to_create if item[0] not in [wayland_dir + name for name in wayland_names]]
    wayland_egl_src = first_existing_file([
        os.path.join(SDCARD_ROOT, "etc/maialinux-runtime/lib/libwayland-egl.so.1.0.0"),
        os.path.join(SDCARD_ROOT, "usr/lib/aarch64-linux-gnu/libwayland-egl.so.1.0.0"),
        VENDOR_WAYLAND_EGL,
    ])
    if wayland_egl_src is None:
        raise RuntimeError(
            "libwayland-egl.so.1.0.0 is required. Run scripts/host/stage-vendor-libs.sh or provide it in the mounted rootfs."
        )
    files_to_write.append((wayland_egl_src, wayland_dir + "libwayland-egl.so.1.0.0", 0, 0, 0o100644))
    symlinks_to_create.extend([(wayland_dir + name, "libwayland-egl.so.1.0.0", 0, 0) for name in wayland_names[:2]])

    log(
        f"Injecting {len(dirs_to_create)} dirs, {len(files_to_write)} files, {len(symlinks_to_create)} symlinks via debugfs..."
    )

    cmd_file = os.path.join(STAGING_DIR, "debugfs_cmds.txt")
    dirs_to_create.sort(key=lambda x: x[0].count("/"))

    def q(s: str) -> str:
        return '"' + s.replace('"', '\\"') + '"'

    with open(cmd_file, "w", encoding="utf-8") as out:
        for rel_p, uid, gid, mode in dirs_to_create:
            out.write(f"mkdir {q(rel_p)}\n")
            out.write(f"set_inode_field {q(rel_p)} uid {uid}\n")
            out.write(f"set_inode_field {q(rel_p)} gid {gid}\n")
            out.write(f"set_inode_field {q(rel_p)} mode 0{oct(mode)[2:]}\n")

        for full_p, rel_p, uid, gid, mode in files_to_write:
            out.write(f"rm {q(rel_p)}\n")
            out.write(f"write {q(full_p)} {q(rel_p)}\n")
            out.write(f"set_inode_field {q(rel_p)} uid {uid}\n")
            out.write(f"set_inode_field {q(rel_p)} gid {gid}\n")
            out.write(f"set_inode_field {q(rel_p)} mode 0{oct(mode)[2:]}\n")

        for rel_p, target, uid, gid in symlinks_to_create:
            out.write(f"rm {q(rel_p)}\n")
            out.write(f"symlink {q(rel_p)} {q(target)}\n")
            out.write(f"set_inode_field {q(rel_p)} uid {uid}\n")
            out.write(f"set_inode_field {q(rel_p)} gid {gid}\n")

    result = subprocess.run(
        ["/usr/sbin/debugfs", "-w", "-f", cmd_file, part4_img],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, check=True,
    )
    if "Could not allocate" in result.stderr or "No space left" in result.stderr:
        raise RuntimeError("Image filesystem is full during injection: " + result.stderr[-4000:])
    os.remove(cmd_file)

    log("Running e2fsck on updated Partition 4...")
    result = subprocess.run(["/usr/sbin/e2fsck", "-f", "-y", part4_img], stdout=subprocess.DEVNULL)
    if result.returncode not in (0, 1):
        raise RuntimeError("Image filesystem check failed.")
    subprocess.run(["/usr/sbin/e2fsck", "-f", "-n", part4_img], check=True, stdout=subprocess.DEVNULL)
    # debugfs may return success even when an individual write failed.
    for source, target, _, _, _ in payload_files:
        content = subprocess.check_output(["/usr/sbin/debugfs", "-R", f'cat "{target}"', part4_img], stderr=subprocess.DEVNULL)
        with open(source, "rb") as expected:
            if content != expected.read():
                raise RuntimeError(f"Repository payload missing or different in image: {target}")
    return total_sectors


def write_sha256(file_path: str) -> str:
    h = hashlib.sha256()
    with open(file_path, "rb") as f:
        while True:
            chunk = f.read(4 * 1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    digest = h.hexdigest()
    sha_file = file_path + ".sha256"
    with open(sha_file, "w", encoding="utf-8") as out:
        out.write(f"{digest}  {os.path.basename(file_path)}\n")
    return digest


def main() -> int:
    os.makedirs(DISTRO_DIR, exist_ok=True)
    os.makedirs(STAGING_DIR, exist_ok=True)
    if shutil.disk_usage(STAGING_DIR).free < 10 * 1024**3:
        raise RuntimeError("Build staging needs at least 10 GiB free; expand root or set STAGING_DIR to a larger filesystem.")
    if shutil.disk_usage(DISTRO_DIR).free < 4 * 1024**3:
        raise RuntimeError("distro/ needs at least 4 GiB free to replace each compressed artifact safely.")

    part3_img = os.path.join(STAGING_DIR, "part3_boot.fat")
    part4_img = os.path.join(STAGING_DIR, "part4_root.ext4")
    extra_sectors = 33554432 - 15208047  # 16 GiB rootfs, including space for swap

    build_part3_boot(part3_img)
    part4_sectors = build_part4_rootfs(part4_img, extra_sectors)

    # 1. Create the compressed QEMU QCOW2 image from part4_root.ext4
    qemu_qcow2_path = os.path.join(DISTRO_DIR, QEMU_QCOW2_NAME)
    log(f"Creating compressed QEMU image: {qemu_qcow2_path} ...")
    subprocess.run(
        ["qemu-img", "convert", "-f", "raw", "-O", "qcow2", "-c", part4_img, qemu_qcow2_path + ".tmp"],
        check=True,
    )
    os.replace(qemu_qcow2_path + ".tmp", qemu_qcow2_path)
    qemu_sha = write_sha256(qemu_qcow2_path)
    log(f"QEMU image ready ({os.path.getsize(qemu_qcow2_path) / (1024**3):.2f} GiB, SHA256: {qemu_sha[:16]}...)")

    mcopy = ensure_mtools()
    for output_path in [os.path.join(DISTRO_DIR, "Image"), os.path.join(DISTRO_DIR, "uInitrd")]:
        if os.path.exists(output_path):
            os.remove(output_path)
    if not copy_fat_file_if_present(mcopy, part3_img, "::/Image", os.path.join(DISTRO_DIR, "Image")):
        raise RuntimeError("Kernel bundle does not contain /Image; cannot assemble distro boot payload.")
    copy_fat_file_if_present(mcopy, part3_img, "::/uInitrd", os.path.join(DISTRO_DIR, "uInitrd"))

    # 2. Build exact GPT header & footer using a 0-disk-usage sparse file in /tmp
    part5_start = 237568 + part4_sectors + 401
    part5_sectors = 155615
    last_lba = part5_start + part5_sectors - 1
    total_lba = last_lba + 34

    sparse_gpt = "/tmp/maialinux_sparse_gpt.img"
    with open(sparse_gpt, "wb") as f:
        f.truncate(total_lba * 512)

    sfdisk_script = f"""label: gpt
label-id: 23000000-0000-4C4A-8000-699000005ABB
unit: sectors
first-lba: 34
last-lba: {last_lba}

1 : start= 16384, size= 8192, type=A60B0000-0000-4C7E-8000-015E00004DB7, uuid=12390000-0000-4B64-8000-700300004538, name="uboot"
2 : start= 24576, size= 8192, type=D46E0000-0000-457F-8000-220D000030DB, uuid=9A010000-0000-484B-8000-3E4900003A7D, name="resource"
3 : start= 32768, size= 204800, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=223E0000-0000-4B12-8000-58CA00007B72, name="ANBERNIC"
4 : start= 237568, size= {part4_sectors}, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=007800AD-96C0-4FD0-60EC-DB015A01F000, name="Basic data partition"
5 : start= {part5_start}, size= {part5_sectors}, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=0A792D1D-A31D-C949-A5B6-1DEDCD6391C4
"""
    subprocess.run(
        ["/usr/sbin/sfdisk", "--no-reread", "--no-tell-kernel", sparse_gpt],
        input=sfdisk_script.encode("utf-8"),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=True,
    )

    with open(sparse_gpt, "rb") as f:
        gpt_primary = f.read(34 * 512)
        f.seek((total_lba - 33) * 512)
        gpt_backup = f.read(33 * 512)
    os.remove(sparse_gpt)

    # Assemble 116 MiB header (LBA 0..237567)
    header_img = os.path.join(STAGING_DIR, "header_237568.bin")
    log("Building 116 MiB GPT + U-Boot + Resource + BOOT header...")
    extract_range(BASE_IMG, header_img, 0, 237568)
    with open(header_img, "r+b") as f:
        f.seek(0)
        f.write(gpt_primary)
        # Preserve the original RG353V resource partition from BASE_IMG.
        # Write Part 3 BOOT FAT32 at LBA 32768
        f.seek(32768 * 512)
        with open(part3_img, "rb") as bf:
            f.write(bf.read())
    os.remove(part3_img)

    # Assemble 76 MiB footer (401 gap sectors + Part 5 EASYROMS + 33 backup GPT sectors)
    footer_img = os.path.join(STAGING_DIR, "footer_easyroms.bin")
    with open(footer_img, "wb") as f:
        f.write(b"\x00" * (401 * 512))
        with open(BASE_IMG, "rb") as bf:
            bf.seek(15446016 * 512)
            f.write(bf.read(part5_sectors * 512))
        f.write(gpt_backup)

    # Stream-compress header + part4_img + footer directly into distro/MaiaLinux-RG353V-v1.0.0-sdcard.img.xz
    sdcard_xz_path = os.path.join(DISTRO_DIR, SDCARD_XZ_NAME)
    log(f"Stream-compressing full GPT SD Card image -> {sdcard_xz_path} (xz -T0 -1)...")
    with open(sdcard_xz_path + ".tmp", "wb") as output:
        compressor = subprocess.Popen(["xz", "-T0", "-1"], stdin=subprocess.PIPE, stdout=output)
        try:
            for source in (header_img, part4_img, footer_img):
                with open(source, "rb") as stream:
                    shutil.copyfileobj(stream, compressor.stdin, 16 * 1024 * 1024)
        finally:
            compressor.stdin.close()
        if compressor.wait() != 0:
            raise RuntimeError("SD card image compression failed.")

    shutil.rmtree(STAGING_DIR, ignore_errors=True)

    os.replace(sdcard_xz_path + ".tmp", sdcard_xz_path)
    sd_sha = write_sha256(sdcard_xz_path)
    log(f"SD Card image ready ({os.path.getsize(sdcard_xz_path) / (1024**3):.2f} GiB, SHA256: {sd_sha[:16]}...)")

    # Copy helper script and release notes into distro/
    shutil.copy2(
        os.path.join(REPO_ROOT, "scripts/host/run-qemu-image.sh"),
        os.path.join(DISTRO_DIR, "run-maialinux-qemu.sh"),
    )
    os.chmod(os.path.join(DISTRO_DIR, "run-maialinux-qemu.sh"), 0o755)
    shutil.copy2(
        os.path.join(REPO_ROOT, "RELEASE_NOTES.md"),
        os.path.join(DISTRO_DIR, f"RELEASE_NOTES_{VERSION}.md"),
    )
    support_dir = os.path.join(DISTRO_DIR, "qemu-support")
    os.makedirs(os.path.join(support_dir, "scripts/host"), exist_ok=True)
    shutil.copy2(os.path.join(REPO_ROOT, "scripts/host/test-qemu-desktop.sh"), os.path.join(support_dir, "scripts/host/test-qemu-desktop.sh"))
    shutil.copytree(os.path.join(REPO_ROOT, "config"), os.path.join(support_dir, "config"), dirs_exist_ok=True)
    shutil.copy2(os.path.join(REPO_ROOT, "scripts/host/setup-qemu-userns.sh"), os.path.join(support_dir, "scripts/host/setup-qemu-userns.sh"))
    launcher_archive = os.path.join(DISTRO_DIR, f"MaiaLinux-RG353V-{VERSION}-qemu-launcher.tar.xz")
    with tarfile.open(launcher_archive, "w:xz") as archive:
        archive.add(support_dir, arcname="qemu-support")
        archive.add(os.path.join(DISTRO_DIR, "run-maialinux-qemu.sh"), arcname="run-maialinux-qemu.sh")
    write_sha256(launcher_archive)
    log("All distro/ release artifacts built successfully!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
