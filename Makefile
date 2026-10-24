# MaiaLinux Makefile
# Automation for installing, testing, and building MaiaLinux for the Anbernic RG353V

SDCARD_ROOT ?= /media/roberto/root
ROOTFS      ?= /media/$(USER)/root1
BASE_IMG    ?= $(CURDIR)/.cache/upstream/ArkOS_RG353V_v2.0_02092025.img
OUT_IMG     ?= ./distro/MaiaLinux-RG353V-v1.0.0-sdcard.img
ARKOS_IMAGE_URL ?=
ARKOS_IMAGE_SHA256 ?=
LOCAL_BASE_IMG ?=

SUDO := $(shell if [ $$(id -u) -eq 0 ]; then echo ""; elif sudo -n true 2>/dev/null || [ -t 0 ]; then echo "sudo"; else echo "pkexec"; fi)

.PHONY: help fetch-upstreams stage-vendor-libs build-release install-sdcard healthcheck chroot-shell test-qemu test-qemu-headless build-distro run-qemu-vm build-image build-logo-image deploy-logo-image monitor-logo-build update-logo-only build-kernel4-bundle deploy-kernel4-bundle

help:
	@echo "MaiaLinux RG353V Build & Deployment System"
	@echo "=========================================="
	@echo "  make build-distro        - Build SD card (.img.xz) & QEMU (.qcow2) releases in distro/ (rootless)"
	@echo "  make fetch-upstreams     - Download/stage ArkOS base image + upstream kernel/toolchain"
	@echo "  make stage-vendor-libs   - Stage Mali + Wayland EGL runtime blobs from mounted rootfs"
	@echo "  make build-release       - Full release pipeline (fetch, stage libs, kernel bundle, distro)"
	@echo "  make test-qemu           - Launch interactive 640x480 ARM64 LXQt desktop window on host PC"
	@echo "  make run-qemu-vm         - Experimental VM; requires KERNEL_IMG for QEMU ARM64 virt"
	@echo "  make install-sdcard      - Install MaiaLinux into mounted SD card ($(SDCARD_ROOT))"
	@echo "  make healthcheck         - Run diagnostic check inside mounted SD card via QEMU"
	@echo "  make chroot-shell        - Open an interactive ARM64 root shell inside $(SDCARD_ROOT)"
	@echo "  make build-logo-image    - Build RK3566 Image with custom boot logo from local PNG/URL"
	@echo "  make deploy-logo-image   - Safely deploy distro/Image to BOOT1 with backup+rollback"
	@echo "  make build-kernel4-bundle - Build RG353V 4.19.172 bundle (Image + rk3566.dtb + modules)"
	@echo "  make deploy-kernel4-bundle - Deploy kernel4 bundle to mounted BOOT1/root1 with rollback"
	@echo "  make monitor-logo-build  - Show current logo build status and output Image metadata"
	@echo "  make update-logo-only    - Update boot/splash images only (keeps BOOT1/Image unchanged)"

fetch-upstreams:
	"$(CURDIR)/scripts/host/fetch-upstream-assets.sh" \
		$(if $(LOCAL_BASE_IMG),--base-image "$(LOCAL_BASE_IMG)",) \
		$(if $(ARKOS_IMAGE_URL),--arkos-url "$(ARKOS_IMAGE_URL)",) \
		$(if $(ARKOS_IMAGE_SHA256),--arkos-sha256 "$(ARKOS_IMAGE_SHA256)",)

stage-vendor-libs:
	"$(CURDIR)/scripts/host/stage-vendor-libs.sh" "$(ROOTFS)"

build-release: fetch-upstreams stage-vendor-libs build-kernel4-bundle build-distro

build-distro:
	BASE_IMG="$(BASE_IMG)" python3 "$(CURDIR)/scripts/host/build-distro-releases.py"

test-qemu:
	"$(CURDIR)/scripts/host/test-qemu-desktop.sh" "$(SDCARD_ROOT)" --interactive

test-qemu-headless:
	"$(CURDIR)/scripts/host/test-qemu-desktop.sh" "$(SDCARD_ROOT)" --screenshot-only

run-qemu-vm:
	"$(CURDIR)/scripts/host/run-qemu-image.sh" --vm

install-sdcard:
	$(SUDO) "$(CURDIR)/scripts/host/install-to-sdcard.sh" "$(SDCARD_ROOT)"

healthcheck:
	$(SUDO) "$(CURDIR)/scripts/host/chroot-run.sh" "$(SDCARD_ROOT)" /usr/local/bin/maialinux-healthcheck.sh

chroot-shell:
	$(SUDO) "$(CURDIR)/scripts/host/chroot-run.sh" "$(SDCARD_ROOT)" /bin/bash

build-image:
	mkdir -p ./distro
	$(SUDO) "$(CURDIR)/scripts/host/build-image.sh" "$(BASE_IMG)" "$(OUT_IMG)" --xz

build-logo-image:
	"$(CURDIR)/scripts/host/build-rk3566-image-with-logo.sh" --logo "$(CURDIR)/images/logo-kernel-rg353-640x480.png" --update-hdmi yes --hdmi-logo "$(CURDIR)/images/logo-kernel-hdmi-1280x720.png" --output "$(CURDIR)/distro/Image"

deploy-logo-image:
	"$(CURDIR)/scripts/host/deploy-boot1-image-safe.sh" "$(CURDIR)/distro/Image" "/media/$(USER)/BOOT1"

build-kernel4-bundle:
	"$(CURDIR)/scripts/host/build-rg353v-kernel4-bundle.sh"

deploy-kernel4-bundle:
	"$(CURDIR)/scripts/host/deploy-rg353v-kernel4-bundle-safe.sh" "$(CURDIR)/distro/kernel-rg353v-4.19.172" "/media/$(USER)/BOOT1" "/media/$(USER)/root1"

monitor-logo-build:
	"$(CURDIR)/scripts/host/monitor-rk3566-logo-build.sh" --status

update-logo-only:
	"$(CURDIR)/scripts/host/update-boot-images-only.sh" "/media/$(USER)/root1" "/media/$(USER)/BOOT1"
