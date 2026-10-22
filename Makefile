# MaiaLinux Makefile
# Automation for installing, testing, and building MaiaLinux for the Anbernic RG353V

SDCARD_ROOT ?= /media/roberto/root
BASE_IMG    ?= /home/roberto/projects/Anbernic/RG353V/ArkOS_RG353V_v2.0_02092025.img
OUT_IMG     ?= ./distro/MaiaLinux-RG353V-v1.0.0-sdcard.img

SUDO := $(shell if [ $$(id -u) -eq 0 ]; then echo ""; elif sudo -n true 2>/dev/null || [ -t 0 ]; then echo "sudo"; else echo "pkexec"; fi)

.PHONY: help install-sdcard healthcheck chroot-shell test-qemu test-qemu-headless build-distro run-qemu-vm build-image

help:
	@echo "MaiaLinux RG353V Build & Deployment System"
	@echo "=========================================="
	@echo "  make build-distro        - Build SD card (.img.xz) & QEMU (.qcow2) releases in distro/ (rootless)"
	@echo "  make test-qemu           - Launch interactive 640x480 ARM64 LXQt desktop window on host PC"
	@echo "  make run-qemu-vm         - Experimental VM; requires KERNEL_IMG for QEMU ARM64 virt"
	@echo "  make install-sdcard      - Install MaiaLinux into mounted SD card ($(SDCARD_ROOT))"
	@echo "  make healthcheck         - Run diagnostic check inside mounted SD card via QEMU"
	@echo "  make chroot-shell        - Open an interactive ARM64 root shell inside $(SDCARD_ROOT)"

build-distro:
	python3 "$(CURDIR)/scripts/host/build-distro-releases.py"

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
