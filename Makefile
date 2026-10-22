# MaiaLinux Makefile
# Automation for installing, testing, and building MaiaLinux for the Anbernic RG353V

SDCARD_ROOT ?= /media/roberto/root
BASE_IMG    ?= /home/roberto/projects/Anbernic/RG353V/ArkOS_RG353V_v2.0_02092025.img
OUT_IMG     ?= ./build/MaiaLinux_RG353V_v1.0.img

# Use sudo when an interactive terminal is attached or passwordless sudo is enabled;
# otherwise fall back to pkexec (GUI Polkit prompt).
SUDO := $(shell if [ $$(id -u) -eq 0 ]; then echo ""; elif sudo -n true 2>/dev/null || [ -t 0 ]; then echo "sudo"; else echo "pkexec"; fi)

.PHONY: help install-sdcard healthcheck chroot-shell test-qemu test-qemu-headless build-image

help:
	@echo "MaiaLinux RG353V Build & Deployment System"
	@echo "=========================================="
	@echo "  make install-sdcard      - Install MaiaLinux into mounted SD card ($(SDCARD_ROOT))"
	@echo "  make healthcheck         - Run diagnostic check inside mounted SD card via QEMU"
	@echo "  make test-qemu           - Launch interactive 640x480 LXQt desktop window on host PC"
	@echo "  make test-qemu-headless  - Run automated 640x480 LXQt test & capture screenshot"
	@echo "  make chroot-shell        - Open an interactive ARM64 root shell inside $(SDCARD_ROOT)"
	@echo "  make build-image         - Build a ready-to-flash .img.xz from $(BASE_IMG)"

install-sdcard:
	$(SUDO) "$(CURDIR)/scripts/host/install-to-sdcard.sh" "$(SDCARD_ROOT)"

healthcheck:
	$(SUDO) "$(CURDIR)/scripts/host/chroot-run.sh" "$(SDCARD_ROOT)" /usr/local/bin/maialinux-healthcheck.sh

chroot-shell:
	$(SUDO) "$(CURDIR)/scripts/host/chroot-run.sh" "$(SDCARD_ROOT)" /bin/bash

test-qemu:
	$(SUDO) "$(CURDIR)/scripts/host/test-qemu-desktop.sh" "$(SDCARD_ROOT)" --interactive

test-qemu-headless:
	$(SUDO) "$(CURDIR)/scripts/host/test-qemu-desktop.sh" "$(SDCARD_ROOT)" --headless

build-image:
	mkdir -p ./build
	$(SUDO) "$(CURDIR)/scripts/host/build-image.sh" "$(BASE_IMG)" "$(OUT_IMG)" --xz
