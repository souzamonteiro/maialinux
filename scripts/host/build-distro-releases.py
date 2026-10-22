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

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
DISTRO_DIR = os.path.join(REPO_ROOT, "distro")
BASE_IMG = os.environ.get(
    "BASE_IMG",
    "/home/roberto/projects/Anbernic/RG353V/ArkOS_RG353V_v2.0_02092025.img",
)
SDCARD_ROOT = os.environ.get("SDCARD_ROOT", "/media/roberto/root")
SDCARD_BOOT = os.environ.get("SDCARD_BOOT", "/media/roberto/BOOT")
STAGING_DIR = os.environ.get(
    "STAGING_DIR", "/media/roberto/root/etc/maialinux-runtime/.tmp-maialinux-build"
)

VERSION = "v1.0.0"
SDCARD_XZ_NAME = f"MaiaLinux-RG353V-{VERSION}-sdcard.img.xz"
QEMU_QCOW2_NAME = f"MaiaLinux-RG353V-{VERSION}-qemu.qcow2"


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


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


def build_part3_boot(part3_img: str) -> None:
    log("Building Partition 3 (BOOT FAT32) with MaiaLinux logos and firstboot hook...")
    extract_range(BASE_IMG, part3_img, 32768, 204800)
    mcopy = ensure_mtools()
    mmd = os.path.join(os.path.dirname(mcopy), "mmd")

    boot_files = [
        (os.path.join(REPO_ROOT, "config/boot/logo.bmp"), "::/logo.bmp"),
        (os.path.join(REPO_ROOT, "config/boot/logo_kernel.bmp"), "::/logo_kernel.bmp"),
        (os.path.join(REPO_ROOT, "config/boot/resource.img"), "::/resource.img"),
        (os.path.join(SDCARD_BOOT, "firstboot.sh"), "::/firstboot.sh"),
        (os.path.join(REPO_ROOT, "config/boot/logo.bmp"), "::/splash/logo_640x480.bmp"),
        (os.path.join(REPO_ROOT, "config/boot/logo_1920x1080.bmp"), "::/splash/logo_1920x1080.bmp"),
    ]
    subprocess.run([mmd, "-D", "s", "-i", part3_img, "::/splash"], stderr=subprocess.DEVNULL)
    for src, dst in boot_files:
        if os.path.isfile(src):
            subprocess.run([mcopy, "-o", "-i", part3_img, src, dst], check=True)


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
            files_to_write.append((src, f"/home/ark/Desktop/{fn}", 1002, 1002, 0o100755))
            files_to_write.append((src, f"/usr/local/share/applications/{fn}", 0, 0, 0o100755))

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
            out.write(f"set_inode_field {q(rel_p)} mode {oct(mode)[2:]}\n")

        for full_p, rel_p, uid, gid, mode in files_to_write:
            out.write(f"rm {q(rel_p)}\n")
            out.write(f"write {q(full_p)} {q(rel_p)}\n")
            out.write(f"set_inode_field {q(rel_p)} uid {uid}\n")
            out.write(f"set_inode_field {q(rel_p)} gid {gid}\n")
            out.write(f"set_inode_field {q(rel_p)} mode {oct(mode)[2:]}\n")

        for rel_p, target, uid, gid in symlinks_to_create:
            out.write(f"rm {q(rel_p)}\n")
            out.write(f"symlink {q(rel_p)} {q(target)}\n")
            out.write(f"set_inode_field {q(rel_p)} uid {uid}\n")
            out.write(f"set_inode_field {q(rel_p)} gid {gid}\n")

    subprocess.run(
        ["/usr/sbin/debugfs", "-w", "-f", cmd_file, part4_img],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=True,
    )
    os.remove(cmd_file)

    log("Running e2fsck on updated Partition 4...")
    subprocess.run(["/usr/sbin/e2fsck", "-f", "-y", part4_img], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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

    part3_img = os.path.join(STAGING_DIR, "part3_boot.fat")
    part4_img = os.path.join(STAGING_DIR, "part4_root.ext4")
    extra_sectors = 1638400  # +800 MiB

    build_part3_boot(part3_img)
    part4_sectors = build_part4_rootfs(part4_img, extra_sectors)

    # 1. Create the compressed QEMU QCOW2 image from part4_root.ext4
    qemu_qcow2_path = os.path.join(DISTRO_DIR, QEMU_QCOW2_NAME)
    log(f"Creating compressed QEMU image: {qemu_qcow2_path} ...")
    subprocess.run(
        ["qemu-img", "convert", "-f", "raw", "-O", "qcow2", "-c", part4_img, qemu_qcow2_path],
        check=True,
    )
    qemu_sha = write_sha256(qemu_qcow2_path)
    log(f"QEMU image ready ({os.path.getsize(qemu_qcow2_path) / (1024**3):.2f} GiB, SHA256: {qemu_sha[:16]}...)")

    shutil.copy2(os.path.join(SDCARD_BOOT, "Image"), os.path.join(DISTRO_DIR, "Image"))
    shutil.copy2(os.path.join(SDCARD_BOOT, "uInitrd"), os.path.join(DISTRO_DIR, "uInitrd"))

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
        # Write Rockchip resource.img at LBA 24576
        f.seek(24576 * 512)
        with open(os.path.join(REPO_ROOT, "config/boot/resource.img"), "rb") as rf:
            res_data = rf.read()
        f.write(res_data.ljust(8192 * 512, b"\x00"))
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
    cmd = f'cat "{header_img}" "{part4_img}" "{footer_img}" | xz -T0 -1 > "{sdcard_xz_path}"'
    subprocess.run(cmd, shell=True, check=True)

    shutil.rmtree(STAGING_DIR, ignore_errors=True)

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
    log("All distro/ release artifacts built successfully!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
