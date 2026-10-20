# GNU Makefile for Australis OS.

# Build compilation, packaging, and QEMU launching are intentionally separate.
# Run `make help` to see the supported commands.
.DEFAULT_GOAL := help

# External tools
HYDROGEN ?= ../Hylang-Compiler/build/self_hosting/hydrogen-stage1
QEMU ?= qemu-system-x86_64
QEMU_DISPLAY ?= sdl
XORRISO ?= xorriso
OVMF_CODE ?= /usr/share/OVMF/OVMF_CODE_4M.fd
GPU_RENDER_NODE ?= $(firstword $(wildcard /dev/dri/renderD*))

# Build directories
BUILD_DIR := build
EFI_DIR := $(BUILD_DIR)/efi
EFI_BOOT_DIR := $(EFI_DIR)/EFI/BOOT
GENERATED_ROOTFS := $(BUILD_DIR)/rootfs
APPLICATIONS_DIR := $(BUILD_DIR)/applications

# EFI and kernel
PROJECT := src/australlis.hyproj
OS_SOURCES := $(wildcard src/bootloader/*.hy src/bootloader/*.hyproj src/kernel/*.hy src/kernel/*.hyproj src/kernel/*/*.hy)
NATIVE_RUNTIME_BLOB := src/kernel/user/NativeRuntimeBlob.hy
EFI_BINARY := $(EFI_BOOT_DIR)/BOOTX64.EFI
KERNEL_BINARY := $(EFI_DIR)/EFI/AUSTRALIS/KERNEL.BIN
IMAGE := $(BUILD_DIR)/australis-hylang-uefi.img
EFI_BOOT_IMAGE := $(BUILD_DIR)/boot/efiboot.img

# Application compilation
APPLICATIONS_PROJECT ?= applications/Applications.hyproj
APPLICATIONS_STAMP := $(APPLICATIONS_DIR)/.built
APPLICATION_ARTIFACTS ?=
APPLICATION_SOURCES := $(shell find applications src/userland src/shell -type f \( -name '*.hy' -o -name '*.hyproj' \) 2>/dev/null)
APP_COMPILER := $(BUILD_DIR)/hydrogen-apps
APP_COMPILER_INPUTS := $(wildcard ../Hylang-Compiler/samples/self_hosting/*/*.hy ../Hylang-Compiler/samples/self_hosting/*/*.hyproj)
ROOTFS_STAMP := $(GENERATED_ROOTFS)/.staged

# HyFS1 image
HYFS1_SOURCES := $(wildcard tools/HyFS1Image/*.hy)
HYFS1_TOOL := $(BUILD_DIR)/tools/hyfs1-image
HYFS1_PROJECT := tools/HyFS1Image/HyFS1Image.hyproj
HYFS1_IMAGE := $(BUILD_DIR)/boot/root.hyfs1.img
HYFS1_ISO_ROOT := $(BUILD_DIR)/iso-root-hyfs1
HYFS1_ISO := $(BUILD_DIR)/australis-hyfs1.iso
HYFS1_AHCI_DISK_ARGS = -device ich9-ahci,id=ahci0 -drive if=none,id=sata0,format=raw,snapshot=on,file="$(HYFS1_ISO)" -device ide-hd,drive=sata0,bus=ahci0.0
HYFS1_NVME_DISK_ARGS = -drive if=none,id=nvme0,format=raw,readonly=on,file="$(HYFS1_ISO)" -device nvme,serial=australis,drive=nvme0

# HyFS2 image
HYFS2_SOURCES := $(wildcard tools/HyFS2Image/*.hy)
HYFS2_TOOL := $(BUILD_DIR)/tools/hyfs2-image
HYFS2_PROJECT := tools/HyFS2Image/HyFS2Image.hyproj
HYFS2_IMAGE := $(BUILD_DIR)/boot/root.hyfs2.img
HYFS2_ISO_ROOT := $(BUILD_DIR)/iso-root-hyfs2
HYFS2_ISO := $(BUILD_DIR)/australis-hyfs2.iso
ISO := $(HYFS2_ISO)
HYFS2_DATA_DISK ?= $(BUILD_DIR)/hyfs2-data.img
HYFS2_AHCI_DISK_ARGS = -device ich9-ahci,id=ahci0 -drive if=none,id=sata0,format=raw,snapshot=on,file="$(HYFS2_ISO)" -device ide-hd,drive=sata0,bus=ahci0.0
HYFS2_NVME_DISK_ARGS = -drive if=none,id=nvme0,format=raw,readonly=on,file="$(HYFS2_ISO)" -device nvme,serial=australis,drive=nvme0

# Hardware and QEMU
HYFS_GPT_TYPE := 9f5eb82e-692e-5a8f-b968-adaaa349dd93
AHCI_DISK_ARGS = -device ich9-ahci,id=ahci0 -drive if=none,id=sata0,format=raw,snapshot=on,file="$(ISO)" -device ide-hd,drive=sata0,bus=ahci0.0
NVME_DISK_ARGS = -drive if=none,id=nvme0,format=raw,readonly=on,file="$(ISO)" -device nvme,serial=australis,drive=nvme0
USB_INPUT_ARGS = -device qemu-xhci,id=xhci0 -device usb-kbd,bus=xhci0.0 -device usb-mouse,bus=xhci0.0
VIRTIO_DISPLAY_ARGS = -display $(QEMU_DISPLAY) -vga none -device virtio-vga,id=gpu0
USB_STORAGE_ARGS = -device qemu-xhci,id=xhci0 -drive if=none,id=usb0,format=raw,readonly=on,file="$(ISO)" -device usb-storage,drive=usb0,bus=xhci0.0

# Hash a snapshot of compiled binary metadata: packaging never acquires
# direct dependencies on compiler output file rules.
EFI_INPUT_SIGNATURE := $(shell for f in "$(EFI_BINARY)" "$(KERNEL_BINARY)"; do stat -c '%n %s %y' "$$f" 2>/dev/null || echo "missing:$$f"; done | sha256sum | cut -c1-16)
EFI_INPUT_STAMP := $(BUILD_DIR)/.efi-input-$(EFI_INPUT_SIGNATURE)
APP_CONTENT_SIGNATURE := $(shell find "$(APPLICATIONS_DIR)" -type f \( -name '*.exec' -o -name '.built' \) -printf '%p %s %TY-%Tm-%TdT%TH:%TM:%TS\n' 2>/dev/null | sort | sha256sum | cut -c1-16)
APP_CONTENT_STAMP := $(BUILD_DIR)/.app-content-$(APP_CONTENT_SIGNATURE)
ROOTFS_INPUTS := $(shell find rootfs -type f 2>/dev/null)
ARTIFACT_SELECTION_SIGNATURE := $(shell printf '%s\n' '$(APPLICATION_ARTIFACTS)' | sha256sum | cut -c1-16)
ARTIFACT_SELECTION_STAMP := $(BUILD_DIR)/.artifact-selection-$(ARTIFACT_SELECTION_SIGNATURE)

#
# RELEASE CONFIGURATION
#
RELEASE_VERSION ?= dev-$(shell git rev-parse --short HEAD)
RELEASE_DIR = dist/release-candidate/$(RELEASE_VERSION)
RELEASE_ISO = australis-os-$(RELEASE_VERSION)-x86_64.iso

RELEASE_DOCS := README.md ROADMAP.md PLAN.md docs/hyfs-v2.md

# ====================================================================
# PHONY TARGET DECLARATIONS
# ====================================================================

# Build & Compilation
.PHONY: all build applications rebuild-applications
.PHONY: clean

# Images & Packaging
.PHONY: image boot_image iso iso-hyfs1
.PHONY: iso-hyfs2 hyfs2-data-disk data-disk-hyfs2

# QEMU & Emulation
.PHONY: run run-emu run-gop run-serial
.PHONY: run-disk run-disk-serial run-nvme run-nvme-serial
.PHONY: run-usb-storage run-usb-storage-nvme run-data-ahci run-data-nvme
.PHONY: run-hyfs1 run-hyfs1-serial run-hyfs1-nvme run-hyfs1-nvme-serial
.PHONY: run-gop-hyfs1 run-serial-hyfs1 run-disk-hyfs1 run-disk-serial-hyfs1
.PHONY: run-nvme-hyfs1 run-nvme-serial-hyfs1 run-usb-storage-hyfs1 run-usb-storage-nvme-hyfs1
.PHONY: run-hyfs2 run-gop-hyfs2 run-serial-hyfs2 run-disk-hyfs2
.PHONY: run-disk-serial-hyfs2 run-nvme-hyfs2 run-nvme-serial-hyfs2 run-usb-storage-hyfs2
.PHONY: run-usb-storage-nvme-hyfs2 run-data-ahci-hyfs2 run-data-nvme-hyfs2

# Kernel & Boot Tests
.PHONY: test-rescue-boot test-bootloader-negative test-boot-modes test-kmon-recovery
.PHONY: test-kernel-panic test-stage2 test-stage2-boot test-stage2-boot-ahci
.PHONY: test-stage2-boot-nvme test-phase5-6

# Input & USB Tests
.PHONY: test-stage3 test-stage3-ahci test-stage3-nvme test-stage4
.PHONY: test-stage4-ahci test-stage4-nvme test-usb test-xhci-multi
.PHONY: test-mouse test-mouse-ahci test-mouse-nvme

# Userland & AUEX Tests
.PHONY: test-stage5 test-stage5-host test-stage5-ahci test-stage5-nvme
.PHONY: test-auex-file-api test-auex-portable-api test-auex-arguments test-auex-arguments-image
.PHONY: test-userland-stage1 test-userland-stage1-host test-userland-stage1-image test-userland-stage1-ahci
.PHONY: test-userland-stage1-nvme test-userland-stage2 test-userland-stage3 test-userland-stage4-supervision
.PHONY: test-userland-stage4-concurrency test-userland-stage4-concurrency-image test-userland-stage5-ipc test-userland-stage5-ipc-image
.PHONY: test-userland-cat test-userland-info test-userland-files-processes test-userland-shell-preview
.PHONY: test-userland-system-host test-userland-system-boot test-userland-essentials

# Native Execution & Storage Persistence Tests
.PHONY: test-native-user-mode test-native-user-mode-image test-native-files test-stage6
.PHONY: test-stage6-image test-stage6-ahci test-stage6-nvme

# Storage & Controller Tests
.PHONY: test-storage test-ahci test-ahci-controller test-ahci-boot
.PHONY: test-nvme test-nvme-controller test-nvme-boot test-partitions
.PHONY: test-vfs test-storage-failure-ahci test-storage-failure-nvme

# HyFS Filesystem Tests
.PHONY: test-hyfs test-hyfs1 test-hyfs1-boot-ahci test-hyfs1-boot-nvme
.PHONY: test-hyfs1-serial-ahci test-hyfs1-serial-nvme test-hyfs1-storage-failure-ahci test-hyfs1-storage-failure-nvme
.PHONY: test-hyfs2 test-hyfs2-writes test-hyfs2-boot-ahci test-hyfs2-boot-nvme
.PHONY: test-hyfs2-serial-ahci test-hyfs2-serial-nvme test-hyfs2-data-ahci test-hyfs2-data-nvme

# Graphics & GPU Tests
.PHONY: test-graphics benchmark-graphics test-display-ahci test-display-nvme test-cursor-stress
.PHONY: test-display-fallback test-virtio-gpu test-virtio-gpu-3d test-frame-pacing

# Console & Serial Tests
.PHONY: test-terminal test-serial-ahci test-serial-nvme

# Tool & Environment Checks
.PHONY: help list-targets check-build-tools check-image-tools
.PHONY: check-efi-image-tools check-iso-tools check-run-tools check-efi-binaries
.PHONY: check-app-binaries check-hyfs1-iso check-hyfs2-iso check-hyfs2-data-disk

#
# RELEASE CANDIDATE
#
.PHONY: release-candidate

release-candidate: iso
	@set -eu; \
	echo "Preparing Australis OS release candidate..."; \
	test -s "$(ISO)" || { echo "ERROR: ISO missing or empty"; exit 1; }; \
	mkdir -p "$(RELEASE_DIR)"; \
	cp "$(ISO)" "$(RELEASE_DIR)/$(RELEASE_ISO)"; \
	for doc in $(RELEASE_DOCS) RELEASE_NOTES.md; do \
		if [ -f "$$doc" ]; then \
			cp "$$doc" "$(RELEASE_DIR)/$$(basename "$$doc")"; \
		fi; \
	done; \
	{ \
		printf 'Australis OS\n'; \
		printf 'Version: %s\n' "$(RELEASE_VERSION)"; \
		printf 'Commit: %s\n' "$$(git rev-parse HEAD)"; \
		printf 'Built UTC: %s\n' "$$(date -u +%Y-%m-%dT%H:%M:%SZ)"; \
	} > "$(RELEASE_DIR)/BUILD-INFO.txt"; \
	cd "$(RELEASE_DIR)"; \
	sha256sum "$(RELEASE_ISO)" > SHA256SUMS; \
	sha256sum -c SHA256SUMS; \
	echo ""; \
	echo "Release candidate ready: $(RELEASE_DIR)"

# ====================================================================
# BUILD AND PACKAGING FILE RULES
# ====================================================================

# Hydrogen compiler / kernel / applications

$(APP_COMPILER): $(APP_COMPILER_INPUTS) $(HYDROGEN) | check-build-tools
	@mkdir -p "$(dir $@)"
	"$(HYDROGEN)" build ../Hylang-Compiler/samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -o "$@"
	@chmod +x "$@"

$(NATIVE_RUNTIME_BLOB): src/kernel/user/native_runtime.S tools/generate_native_runtime_blob.py
	python3 tools/generate_native_runtime_blob.py "$<" "$@"

$(EFI_BINARY) $(KERNEL_BINARY) &: $(PROJECT) $(OS_SOURCES) $(NATIVE_RUNTIME_BLOB) $(APP_COMPILER) | check-build-tools
	"$(APP_COMPILER)" build "$(PROJECT)" -o "$(EFI_DIR)"

$(APPLICATIONS_STAMP): $(APPLICATIONS_PROJECT) $(APPLICATION_SOURCES) $(APP_COMPILER) | check-build-tools
	@mkdir -p "$(APPLICATIONS_DIR)"
	"$(APP_COMPILER)" build "$(APPLICATIONS_PROJECT)" -o "$(APPLICATIONS_DIR)"
	@touch "$@"

# Input-snapshot stamp files

$(EFI_INPUT_STAMP):
	@mkdir -p "$(BUILD_DIR)"
	@rm -f "$(BUILD_DIR)"/.efi-input-*
	@touch "$@"

$(APP_CONTENT_STAMP):
	@mkdir -p "$(BUILD_DIR)"
	@rm -f "$(BUILD_DIR)"/.app-content-*
	@touch "$@"

$(ARTIFACT_SELECTION_STAMP):
	@mkdir -p "$(BUILD_DIR)"
	@rm -f "$(BUILD_DIR)"/.artifact-selection-*
	@touch "$@"

# Root filesystem staging

$(ROOTFS_STAMP): $(APP_CONTENT_STAMP) $(ROOTFS_INPUTS) $(APPLICATION_ARTIFACTS) $(ARTIFACT_SELECTION_STAMP) | check-app-binaries
	@rm -rf "$(GENERATED_ROOTFS)"
	@mkdir -p "$(GENERATED_ROOTFS)"
	@cp -a rootfs/. "$(GENERATED_ROOTFS)/"
	@cp "$(APPLICATIONS_DIR)"/*.exec "$(GENERATED_ROOTFS)/"
	@for artifact in $(APPLICATION_ARTIFACTS); do \
		name=$$(basename "$$artifact"); \
		test ! -e "$(GENERATED_ROOTFS)/$$name" || { echo "duplicate root executable: $$name"; exit 1; }; \
		cp "$$artifact" "$(GENERATED_ROOTFS)/$$name"; \
	done
	@touch "$@"

# Standalone EFI and boot images

$(IMAGE): $(EFI_INPUT_STAMP) | check-efi-image-tools check-efi-binaries
	@mkdir -p "$(BUILD_DIR)"
	@rm -f "$@"
	truncate -s 64M "$@"
	mformat -i "$@" -F ::
	mmd -i "$@" ::/EFI ::/EFI/BOOT ::/EFI/AUSTRALIS
	mcopy -i "$@" "$(EFI_BINARY)" ::/EFI/BOOT/BOOTX64.EFI
	mcopy -i "$@" "$(KERNEL_BINARY)" ::/EFI/AUSTRALIS/KERNEL.BIN

$(EFI_BOOT_IMAGE): $(EFI_INPUT_STAMP) | check-efi-image-tools check-efi-binaries
	@mkdir -p "$(dir $(EFI_BOOT_IMAGE))"
	@rm -f "$@"
	truncate -s 8M "$@"
	mformat -i "$@" ::
	mmd -i "$@" ::/EFI ::/EFI/BOOT ::/EFI/AUSTRALIS
	mcopy -i "$@" "$(EFI_BINARY)" ::/EFI/BOOT/BOOTX64.EFI
	mcopy -i "$@" "$(KERNEL_BINARY)" ::/EFI/AUSTRALIS/KERNEL.BIN

# HyFS1 and HyFS2 filesystem images

$(HYFS1_TOOL): $(HYFS1_PROJECT) $(HYFS1_SOURCES)
	@mkdir -p "$(dir $@)"
	"$(HYDROGEN)" build "$(HYFS1_PROJECT)" -o "$@"

$(HYFS1_IMAGE): tools/make_hyfs1_image.py $(ROOTFS_STAMP)
	python3 tools/make_hyfs1_image.py "$(GENERATED_ROOTFS)" "$@"

$(HYFS2_TOOL): $(HYFS2_PROJECT) $(HYFS2_SOURCES)
	@mkdir -p "$(dir $@)"
	"$(HYDROGEN)" build "$(HYFS2_PROJECT)" -o "$@"

$(HYFS2_IMAGE): tools/hyfs2.py tools/make_hyfs2_image.py src/userland/system/startup.manifest src/userland/system/capabilities.manifest $(ROOTFS_STAMP)
	python3 tools/make_hyfs2_image.py "$(GENERATED_ROOTFS)" "$@" --system-apps "$(APPLICATIONS_DIR)/system"

$(HYFS2_DATA_DISK): $(wildcard $(HYFS2_ISO)) | check-hyfs2-iso
	python3 tools/make_hyfs2_data_disk.py "$(HYFS2_ISO)" "$@"

# Bootable ISO packaging

$(HYFS1_ISO): $(EFI_BOOT_IMAGE) $(HYFS1_IMAGE) | check-iso-tools check-efi-binaries check-app-binaries
	@rm -rf "$(HYFS1_ISO_ROOT)"
	@mkdir -p "$(HYFS1_ISO_ROOT)/EFI/BOOT"
	cp "$(EFI_BOOT_IMAGE)" "$(HYFS1_ISO_ROOT)/EFI/BOOT/efiboot.img"
	"$(XORRISO)" -as mkisofs -R -J \
	-eltorito-alt-boot -e EFI/BOOT/efiboot.img -no-emul-boot \
	-efi-boot-part --efi-boot-image \
	-append_partition 4 "$(HYFS_GPT_TYPE)" "$(HYFS1_IMAGE)" -appended_part_as_gpt \
	-o "$@" "$(HYFS1_ISO_ROOT)"

$(HYFS2_ISO): $(EFI_BOOT_IMAGE) $(HYFS2_IMAGE) | check-iso-tools check-efi-binaries check-app-binaries
	@rm -rf "$(HYFS2_ISO_ROOT)"
	@mkdir -p "$(HYFS2_ISO_ROOT)/EFI/BOOT"
	cp "$(EFI_BOOT_IMAGE)" "$(HYFS2_ISO_ROOT)/EFI/BOOT/efiboot.img"
	"$(XORRISO)" -as mkisofs -R -J \
	-eltorito-alt-boot -e EFI/BOOT/efiboot.img -no-emul-boot \
	-efi-boot-part --efi-boot-image \
	-append_partition 4 "$(HYFS_GPT_TYPE)" "$(HYFS2_IMAGE)" -appended_part_as_gpt \
	-o "$@" "$(HYFS2_ISO_ROOT)"

# VFS host test input

$(BUILD_DIR)/host-vfs/Hyfs.hy: src/kernel/vfs/Hyfs.hy tests/vfs/build_host_hyfs.py
	python3 tests/vfs/build_host_hyfs.py "$<" "$@"

# ====================================================================
# BUILD & COMPILATION
# ====================================================================
##@ Build & Compilation

all: ## Compile the OS and applications, then create EFI and HyFS2 images (no QEMU)
	@$(MAKE) build
	@$(MAKE) applications
	@$(MAKE) image
	@$(MAKE) iso

build: $(EFI_BINARY) $(KERNEL_BINARY) ## Compile the bootloader and kernel if sources changed

applications: $(APPLICATIONS_STAMP) ## Compile applications if their sources changed

rebuild-applications: ## Force recompilation of all applications
	@rm -f "$(APPLICATIONS_STAMP)"
	@$(MAKE) applications

clean: ## Remove the generated build directory
	rm -rf "$(BUILD_DIR)"

# ====================================================================
# IMAGES & PACKAGING
# ====================================================================
##@ Images & Packaging

image: check-efi-binaries $(IMAGE) ## Package compiled EFI binaries into a standalone disk image

boot_image: check-efi-binaries $(EFI_BOOT_IMAGE) ## Package compiled EFI boot image

iso: iso-hyfs2 ## Package the compiled OS and applications into HyFS2 ISO

iso-hyfs1: check-efi-binaries check-app-binaries $(HYFS1_ISO) ## Package the legacy HyFS1 ISO

iso-hyfs2: check-efi-binaries check-app-binaries $(HYFS2_ISO) ## Package the default HyFS2 ISO

hyfs2-data-disk: data-disk-hyfs2 ## Generate a writable HyFS2 data disk

data-disk-hyfs2: $(HYFS2_DATA_DISK) ## Generate a writable HyFS2 data disk

# ====================================================================
# QEMU & EMULATION
# ====================================================================
##@ QEMU & Emulation

run: run-hyfs2 ## Boot Australis with VirtIO-GPU

run-emu: run ## Alias for the default QEMU runner

run-gop: run-gop-hyfs2 ## Boot using GOP framebuffer

run-serial: run-serial-hyfs2 ## Boot with serial console

run-disk: run-disk-hyfs2 ## Boot from AHCI disk

run-disk-serial: run-disk-serial-hyfs2 ## Run disk serial hyfs2

run-nvme: run-nvme-hyfs2 ## Boot from NVMe disk

run-nvme-serial: run-nvme-serial-hyfs2 ## Run nvme serial hyfs2

run-usb-storage: run-usb-storage-hyfs2 ## Boot with USB storage

run-usb-storage-nvme: run-usb-storage-nvme-hyfs2 ## Run usb storage nvme hyfs2

run-data-ahci: run-data-ahci-hyfs2 ## Run data ahci hyfs2

run-data-nvme: run-data-nvme-hyfs2 ## Run data nvme hyfs2

run-hyfs1: | check-run-tools check-hyfs1-iso ## Run the existing legacy HyFS1 ISO
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS1_ISO)" $(HYFS1_AHCI_DISK_ARGS) $(USB_INPUT_ARGS) -net none

run-hyfs1-serial: run-serial-hyfs1 ## Run serial hyfs1

run-hyfs1-nvme: run-nvme-hyfs1 ## Run nvme hyfs1

run-hyfs1-nvme-serial: run-nvme-serial-hyfs1 ## Run nvme serial hyfs1

run-gop-hyfs1: | check-run-tools check-hyfs1-iso
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS1_ISO)" $(HYFS1_AHCI_DISK_ARGS) $(USB_INPUT_ARGS) -net none -monitor none -serial stdio

run-serial-hyfs1: | check-run-tools check-hyfs1-iso
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS1_ISO)" $(HYFS1_AHCI_DISK_ARGS) -net none -display none -monitor none -serial stdio

run-disk-hyfs1: | check-run-tools check-hyfs1-iso
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" $(HYFS1_AHCI_DISK_ARGS) $(USB_INPUT_ARGS) -net none

run-disk-serial-hyfs1: | check-run-tools check-hyfs1-iso
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" $(HYFS1_AHCI_DISK_ARGS) -net none -display none -monitor none -serial stdio

run-nvme-hyfs1: | check-run-tools check-hyfs1-iso
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS1_ISO)" $(HYFS1_NVME_DISK_ARGS) $(USB_INPUT_ARGS) -net none

run-nvme-serial-hyfs1: | check-run-tools check-hyfs1-iso
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS1_ISO)" $(HYFS1_NVME_DISK_ARGS) -net none -display none -monitor none -serial stdio

run-usb-storage-hyfs1: | check-run-tools check-hyfs1-iso
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS1_ISO)" $(HYFS1_AHCI_DISK_ARGS) $(USB_STORAGE_ARGS) -net none -display none -monitor none -serial stdio

run-usb-storage-nvme-hyfs1: | check-run-tools check-hyfs1-iso
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS1_ISO)" $(HYFS1_NVME_DISK_ARGS) $(USB_STORAGE_ARGS) -net none -display none -monitor none -serial stdio

run-hyfs2: | check-run-tools check-hyfs2-iso ## Run the existing HyFS2 ISO using VirtIO-GPU
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS2_ISO)" $(HYFS2_AHCI_DISK_ARGS) $(USB_INPUT_ARGS) $(VIRTIO_DISPLAY_ARGS) -net none

run-gop-hyfs2: | check-run-tools check-hyfs2-iso ## Run HyFS2 in GOP fallback mode
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS2_ISO)" $(HYFS2_AHCI_DISK_ARGS) $(USB_INPUT_ARGS) -net none -monitor none -serial stdio

run-serial-hyfs2: | check-run-tools check-hyfs2-iso
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS2_ISO)" $(HYFS2_AHCI_DISK_ARGS) -net none -display none -monitor none -serial stdio

run-disk-hyfs2: | check-run-tools check-hyfs2-iso ## Run HyFS2 from AHCI disk with VirtIO-GPU
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" $(HYFS2_AHCI_DISK_ARGS) $(USB_INPUT_ARGS) $(VIRTIO_DISPLAY_ARGS) -net none

run-disk-serial-hyfs2: | check-run-tools check-hyfs2-iso
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" $(HYFS2_AHCI_DISK_ARGS) -net none -display none -monitor none -serial stdio

run-nvme-hyfs2: | check-run-tools check-hyfs2-iso ## Run HyFS2 from NVMe with VirtIO-GPU
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS2_ISO)" $(HYFS2_NVME_DISK_ARGS) $(USB_INPUT_ARGS) $(VIRTIO_DISPLAY_ARGS) -net none

run-nvme-serial-hyfs2: | check-run-tools check-hyfs2-iso
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS2_ISO)" $(HYFS2_NVME_DISK_ARGS) -net none -display none -monitor none -serial stdio

run-usb-storage-hyfs2: | check-run-tools check-hyfs2-iso
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS2_ISO)" $(HYFS2_AHCI_DISK_ARGS) $(USB_STORAGE_ARGS) -net none -display none -monitor none -serial stdio

run-usb-storage-nvme-hyfs2: | check-run-tools check-hyfs2-iso
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS2_ISO)" $(HYFS2_NVME_DISK_ARGS) $(USB_STORAGE_ARGS) -net none -display none -monitor none -serial stdio

run-data-ahci-hyfs2: | check-run-tools check-hyfs2-iso check-hyfs2-data-disk
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS2_ISO)" -device ich9-ahci,id=ahci0 -drive if=none,id=data0,format=raw,file="$(HYFS2_DATA_DISK)" -device ide-hd,drive=data0,bus=ahci0.0 -net none -display none -monitor none -serial stdio

run-data-nvme-hyfs2: | check-run-tools check-hyfs2-iso check-hyfs2-data-disk
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS2_ISO)" -drive if=none,id=data0,format=raw,file="$(HYFS2_DATA_DISK)" -device nvme,serial=australis-data,drive=data0 -net none -display none -monitor none -serial stdio

# ====================================================================
# KERNEL & BOOT TESTS
# ====================================================================
##@ Kernel & Boot Tests

test-rescue-boot: image | check-run-tools ## Smoke-test the rescue monitor boot
	python3 tests/console/rescue_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(IMAGE)"

test-bootloader-negative: image | check-run-tools ## Test missing or invalid kernel boot cases
	python3 tests/bootloader/negative_kernel_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(IMAGE)" "$(KERNEL_BINARY)"

test-boot-modes: iso | check-run-tools ## Test bootloader boot modes
	python3 tests/bootloader/boot_modes.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)"

test-kmon-recovery: iso | check-run-tools ## Test kernel monitor recovery commands
	python3 tests/console/recovery_commands_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)"

test-kernel-panic: iso | check-run-tools ## Test kernel panic behaviour
	python3 tests/kernel/panic_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)"

test-stage2: check-build-tools ## Run kernel Stage 2 host tests
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/kernel/Stage2.hyproj -o "$(BUILD_DIR)/stage2-tests"
	"$(BUILD_DIR)/stage2-tests"

test-stage2-boot: test-stage2-boot-ahci test-stage2-boot-nvme ## Run Stage 2 boot tests (AHCI and NVMe)

test-stage2-boot-ahci: iso | check-run-tools
	python3 tests/kernel/stage2_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci

test-stage2-boot-nvme: iso | check-run-tools
	python3 tests/kernel/stage2_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" nvme

# Boot tests that change the ISO must run in series (no parallel test jobs).
test-phase5-6: ## Run the comprehensive Phase 5/6 test suite serially
	"$(MAKE)" -j1 test-storage test-ahci-controller test-nvme-controller test-partitions test-usb test-terminal test-hyfs2
	"$(MAKE)" -j1 test-stage6
	"$(MAKE)" -j1 test-stage3
	"$(MAKE)" -j1 test-mouse
	"$(MAKE)" -j1 test-stage4
	"$(MAKE)" -j1 test-xhci-multi
	"$(MAKE)" -j1 test-serial-ahci test-serial-nvme
	"$(MAKE)" -j1 test-userland-info
	"$(MAKE)" -j1 test-native-files

# ====================================================================
# INPUT & USB TESTS
# ====================================================================
##@ Input & USB Tests

test-stage3: test-stage3-ahci test-stage3-nvme ## Test xHCI keyboard in QEMU

test-stage3-ahci: iso | check-run-tools
	python3 tests/usb/xhci_keyboard_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci

test-stage3-nvme: iso | check-run-tools
	python3 tests/usb/xhci_keyboard_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" nvme

test-stage4: test-stage4-ahci test-stage4-nvme ## Test xHCI storage in QEMU

test-stage4-ahci: iso | check-run-tools
	python3 tests/usb/xhci_storage_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci

test-stage4-nvme: iso | check-run-tools
	python3 tests/usb/xhci_storage_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" nvme

test-usb: check-build-tools ## Run USB driver host tests
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/usb/UsbDrivers.hyproj -o "$(BUILD_DIR)/usb-tests"
	"$(BUILD_DIR)/usb-tests"

test-xhci-multi: iso | check-run-tools ## Test multiple USB HID devices
	python3 tests/usb/xhci_multi_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci
	python3 tests/usb/xhci_multi_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" nvme
	python3 tests/usb/xhci_dual_hid_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci
	python3 tests/usb/xhci_dual_hid_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" nvme

test-mouse: test-mouse-ahci test-mouse-nvme ## Smoke-test USB mouse input

test-mouse-ahci: iso | check-run-tools
	python3 tests/usb/xhci_mouse_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci

test-mouse-nvme: iso | check-run-tools
	python3 tests/usb/xhci_mouse_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" nvme

# ====================================================================
# USERLAND & AUEX TESTS
# ====================================================================
##@ Userland & AUEX Tests

test-stage5: test-stage5-host test-stage5-ahci test-stage5-nvme ## Run Stage 5 user-program tests

test-stage5-host: check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/user/UserRuntime.hyproj -o "$(BUILD_DIR)/user-runtime-tests"
	"$(BUILD_DIR)/user-runtime-tests"

test-stage5-ahci: iso | check-run-tools
	python3 tests/user/user_program_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci

test-stage5-nvme: iso | check-run-tools
	python3 tests/user/user_program_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" nvme

test-auex-file-api: $(APP_COMPILER) ## Test AUEX filesystem API
	@mkdir -p "$(BUILD_DIR)"
	"$(APP_COMPILER)" build applications/Australis-Inspector/Inspector.hyproj -o "$(BUILD_DIR)/inspector-file-api.exec"
	"$(APP_COMPILER)" build tests/user/FileApiApp.hyproj -o "$(BUILD_DIR)/file-api-test.exec"
	"$(HYDROGEN)" build tests/user/UserRuntime.hyproj -o "$(BUILD_DIR)/user-runtime-tests"
	"$(BUILD_DIR)/user-runtime-tests" inspector "$(BUILD_DIR)/inspector-file-api.exec"
	"$(BUILD_DIR)/user-runtime-tests" file-api "$(BUILD_DIR)/file-api-test.exec"

test-auex-portable-api: $(APP_COMPILER) ## Test AUEX portable API
	@mkdir -p "$(BUILD_DIR)"
	"$(APP_COMPILER)" build applications/Australis.Dev-user-demo/UserDemo.hyproj -o "$(BUILD_DIR)/portable-api-test.exec"
	"$(APP_COMPILER)" build tests/user/PortableApiApp.hyproj -o "$(BUILD_DIR)/portable-io-test.exec"
	"$(HYDROGEN)" build tests/user/UserRuntime.hyproj -o "$(BUILD_DIR)/user-runtime-tests"
	"$(BUILD_DIR)/user-runtime-tests" portable-api "$(BUILD_DIR)/portable-api-test.exec"
	"$(BUILD_DIR)/user-runtime-tests" portable-io "$(BUILD_DIR)/portable-io-test.exec"

test-auex-arguments: test-auex-arguments-image ## Test native application arguments
	python3 tests/user/argument_program_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci
	python3 tests/user/argument_program_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

test-auex-arguments-image: $(APP_COMPILER) | check-run-tools
	"$(APP_COMPILER)" build tests/user/ArgumentApp.hyproj -o "$(BUILD_DIR)/argv-check.exec"
	"$(MAKE)" iso-hyfs2 APPLICATION_ARTIFACTS="$(BUILD_DIR)/argv-check.exec"

test-userland-stage1: test-userland-stage1-host test-userland-stage1-image ## Run Stage 1 userland boot tests
	python3 tests/user/stage1_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci
	python3 tests/user/stage1_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

test-userland-stage1-host: $(APP_COMPILER) test-stage5-host
	"$(APP_COMPILER)" build tests/user/Stage1App.hyproj -o "$(BUILD_DIR)/stage1-app.exec"
	"$(BUILD_DIR)/user-runtime-tests" stage1 "$(BUILD_DIR)/stage1-app.exec"
	"$(APP_COMPILER)" build tests/user/StarterApp.hyproj -o "$(BUILD_DIR)/stage1-starter.exec"
	"$(BUILD_DIR)/user-runtime-tests" stage1-starter "$(BUILD_DIR)/stage1-starter.exec"

test-userland-stage1-image: $(APP_COMPILER) | check-run-tools
	"$(APP_COMPILER)" build tests/user/Stage1App.hyproj -o "$(BUILD_DIR)/stage1-app.exec"
	"$(APP_COMPILER)" build tests/user/StarterApp.hyproj -o "$(BUILD_DIR)/stage1-starter.exec"
	"$(MAKE)" iso-hyfs2 APPLICATION_ARTIFACTS="$(BUILD_DIR)/stage1-app.exec $(BUILD_DIR)/stage1-starter.exec"

test-userland-stage1-ahci: test-userland-stage1-image
	python3 tests/user/stage1_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci

test-userland-stage1-nvme: test-userland-stage1-image
	python3 tests/user/stage1_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

test-userland-stage2: iso-hyfs2 | check-run-tools ## Test Stage 2 userland boot and context
	"$(APP_COMPILER)" build tests/user/ContextProbe.hyproj -o "$(BUILD_DIR)/context-probe.exec"
	python3 tests/user/stage2_shell_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" "$(BUILD_DIR)/context-probe.exec" ahci
	python3 tests/user/stage2_shell_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" "$(BUILD_DIR)/context-probe.exec" nvme

test-userland-stage3: iso-hyfs2 | check-run-tools ## Test userland system recovery
	python3 tests/user/system_image_recovery_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci
	python3 tests/user/system_image_recovery_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

test-userland-stage4-supervision: iso-hyfs2 | check-run-tools ## Test supervisor fault handling
	python3 tests/user/stage4_supervision_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" "$(APPLICATIONS_DIR)/user-fault.exec" ahci
	python3 tests/user/stage4_supervision_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" "$(APPLICATIONS_DIR)/user-fault.exec" nvme

test-userland-stage4-concurrency: test-userland-stage4-concurrency-image ## Test concurrent userland applications
	python3 tests/user/stage4_concurrency_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci
	python3 tests/user/stage4_concurrency_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

test-userland-stage4-concurrency-image: $(APP_COMPILER) | check-run-tools
	"$(APP_COMPILER)" build tests/user/ConcurrentA.hyproj -o "$(BUILD_DIR)/concurrent-a.exec"
	"$(APP_COMPILER)" build tests/user/ConcurrentB.hyproj -o "$(BUILD_DIR)/concurrent-b.exec"
	"$(APP_COMPILER)" build tests/user/ConcurrentProbe.hyproj -o "$(BUILD_DIR)/concurrent-probe.exec"
	"$(MAKE)" iso-hyfs2 APPLICATION_ARTIFACTS="$(BUILD_DIR)/concurrent-a.exec $(BUILD_DIR)/concurrent-b.exec $(BUILD_DIR)/concurrent-probe.exec"

test-userland-stage5-ipc: test-userland-stage5-ipc-image ## Test userland IPC across processes
	python3 tests/user/stage5_ipc_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci
	python3 tests/user/stage5_ipc_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

test-userland-stage5-ipc-image: $(APP_COMPILER) | check-run-tools
	"$(APP_COMPILER)" build tests/user/IpcProbe.hyproj -o "$(BUILD_DIR)/ipc-probe.exec"
	"$(APP_COMPILER)" build tests/user/IpcChild.hyproj -o "$(BUILD_DIR)/ipc-child.exec"
	"$(APP_COMPILER)" build tests/user/IpcExit.hyproj -o "$(BUILD_DIR)/ipc-exit.exec"
	"$(APP_COMPILER)" build tests/user/IpcDenied.hyproj -o "$(BUILD_DIR)/ipc-denied.exec"
	"$(APP_COMPILER)" build tests/user/IpcNoop.hyproj -o "$(BUILD_DIR)/ipc-noop.exec"
	"$(MAKE)" iso-hyfs2 APPLICATION_ARTIFACTS="$(BUILD_DIR)/ipc-probe.exec $(BUILD_DIR)/ipc-child.exec $(BUILD_DIR)/ipc-exit.exec $(BUILD_DIR)/ipc-denied.exec $(BUILD_DIR)/ipc-noop.exec"

test-userland-cat: iso | check-run-tools ## Test cat command in QEMU
	python3 tests/user/cat_program_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci
	python3 tests/user/cat_program_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

test-userland-info: PROJECT = tests/user/BootImage.hyproj
test-userland-info: iso | check-run-tools ## Test system information commands
	python3 tests/user/system_info_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci
	python3 tests/user/system_info_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

test-userland-files-processes: PROJECT = tests/user/BootImage.hyproj
test-userland-files-processes: iso | check-run-tools ## Test file and process command support
	python3 tests/user/files_processes_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci
	python3 tests/user/files_processes_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

test-userland-shell-preview: $(APP_COMPILER) check-build-tools ## Test CommandShell via host runtime
	"$(APP_COMPILER)" build src/shell/australlis.shell.hyproj -o "$(BUILD_DIR)/CommandShell.exec"
	"$(HYDROGEN)" build tests/user/UserRuntime.hyproj -o "$(BUILD_DIR)/user-runtime-tests"
	"$(BUILD_DIR)/user-runtime-tests" shell-preview "$(BUILD_DIR)/CommandShell.exec"
	"$(BUILD_DIR)/user-runtime-tests" shell-commands "$(BUILD_DIR)/CommandShell.exec"

test-userland-system-host: $(APP_COMPILER) check-build-tools ## Test System.exec via host runtime
	"$(APP_COMPILER)" build src/userland/australlis.userland.hyproj -o "$(BUILD_DIR)/System.exec"
	"$(HYDROGEN)" build tests/user/UserRuntime.hyproj -o "$(BUILD_DIR)/user-runtime-tests"
	"$(BUILD_DIR)/user-runtime-tests" system-launch "$(BUILD_DIR)/System.exec"
	"$(BUILD_DIR)/user-runtime-tests" system-failure "$(BUILD_DIR)/System.exec"

test-userland-system-boot: iso-hyfs2 | check-run-tools ## Smoke-test system boot in QEMU
	python3 tests/user/system_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci
	python3 tests/user/system_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

test-userland-essentials: iso-hyfs2 | check-run-tools ## Smoke-test essential userland services
	python3 tests/user/essentials_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci
	python3 tests/user/essentials_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

# ====================================================================
# NATIVE EXECUTION & STORAGE PERSISTENCE TESTS
# ====================================================================
##@ Native Execution & Storage Persistence Tests

test-native-user-mode: test-native-user-mode-image ## Test native user-mode isolation and process execution
	python3 tests/user/native_user_mode_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci
	python3 tests/user/native_user_mode_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

test-native-user-mode-image: $(APP_COMPILER)
	python3 tools/make_native_test_image.py tests/user/native_pid.S "$(BUILD_DIR)/native-pid.exec"
	python3 tools/make_native_test_image.py tests/user/native_fault.S "$(BUILD_DIR)/native-fault.exec"
	python3 tools/make_native_test_image.py tests/user/native_privilege.S "$(BUILD_DIR)/native-privilege.exec"
	python3 tools/make_native_test_image.py tests/user/native_write_invalid.S "$(BUILD_DIR)/native-write-invalid.exec"
	python3 tools/make_native_test_image.py tests/user/native_code_write.S "$(BUILD_DIR)/native-code-write.exec"
	python3 tools/make_native_test_image.py tests/user/native_data_execute.S "$(BUILD_DIR)/native-data-execute.exec"
	python3 tools/make_native_test_image.py tests/user/native_stack_guard.S "$(BUILD_DIR)/native-stack-guard.exec"
	python3 tools/make_native_test_image.py tests/user/native_kernel_write.S "$(BUILD_DIR)/native-kernel-write.exec"
	python3 tools/make_native_test_image.py tests/user/native_invalid_opcode.S "$(BUILD_DIR)/native-invalid-opcode.exec"
	python3 tools/make_native_test_image.py tests/user/native_divide_error.S "$(BUILD_DIR)/native-divide-error.exec"
	python3 tools/make_native_test_image.py tests/user/native_spin.S "$(BUILD_DIR)/native-spin.exec"
	python3 tools/make_native_test_image.py tests/user/native_context.S "$(BUILD_DIR)/native-context.exec"
	python3 tools/make_native_test_image.py tests/user/native_ipc_child.S "$(BUILD_DIR)/native-ipc.exec"
	python3 tools/make_native_test_image.py tests/user/native_files.S "$(BUILD_DIR)/native-files.exec"
	"$(APP_COMPILER)" build ../Hylang-Compiler/tests/phase6/Aun1Hello.hyproj -o "$(BUILD_DIR)/native-hydrogen.exec" --hide-progress
	"$(APP_COMPILER)" build tests/user/NativeScheduleProbe.hyproj -o "$(BUILD_DIR)/native-schedule-probe.exec" --hide-progress
	"$(APP_COMPILER)" build tests/user/NativeOrphanProbe.hyproj -o "$(BUILD_DIR)/native-orphan-probe.exec" --hide-progress
	"$(APP_COMPILER)" build tests/user/NativeIpcProbe.hyproj -o "$(BUILD_DIR)/native-ipc-probe.exec" --hide-progress
	"$(MAKE)" iso-hyfs2 APPLICATION_ARTIFACTS="$(BUILD_DIR)/native-pid.exec $(BUILD_DIR)/native-fault.exec $(BUILD_DIR)/native-privilege.exec $(BUILD_DIR)/native-write-invalid.exec $(BUILD_DIR)/native-code-write.exec $(BUILD_DIR)/native-data-execute.exec $(BUILD_DIR)/native-stack-guard.exec $(BUILD_DIR)/native-kernel-write.exec $(BUILD_DIR)/native-invalid-opcode.exec $(BUILD_DIR)/native-divide-error.exec $(BUILD_DIR)/native-spin.exec $(BUILD_DIR)/native-context.exec $(BUILD_DIR)/native-ipc.exec $(BUILD_DIR)/native-files.exec $(BUILD_DIR)/native-hydrogen.exec $(BUILD_DIR)/native-schedule-probe.exec $(BUILD_DIR)/native-orphan-probe.exec $(BUILD_DIR)/native-ipc-probe.exec"

test-native-files: test-native-user-mode-image ## Test native userland file operations
	python3 tests/user/native_files_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci
	python3 tests/user/native_files_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

test-stage6: test-hyfs2 test-stage6-ahci test-stage6-nvme ## Run Stage 6 persistent filesystem tests

test-stage6-image: $(APP_COMPILER) | check-run-tools
	"$(APP_COMPILER)" build tests/user/PersistentFileApp.hyproj -o "$(BUILD_DIR)/stage6-file-test.exec"
	"$(MAKE)" iso-hyfs2 APPLICATION_ARTIFACTS="$(BUILD_DIR)/stage6-file-test.exec"

test-stage6-ahci: test-stage6-image
	python3 tests/storage/hyfs2_persistent_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci

test-stage6-nvme: test-stage6-image
	python3 tests/storage/hyfs2_persistent_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

# ====================================================================
# STORAGE & CONTROLLER TESTS
# ====================================================================
##@ Storage & Controller Tests

test-storage: check-build-tools ## Run block-device host tests
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/BlockDevice.hyproj -o "$(BUILD_DIR)/storage-tests"
	"$(BUILD_DIR)/storage-tests"

test-ahci: check-build-tools ## Test AHCI block driver
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/Ahci.hyproj -o "$(BUILD_DIR)/ahci-tests"
	"$(BUILD_DIR)/ahci-tests"

test-ahci-controller: check-build-tools ## Test AHCI controller logic
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/AhciController.hyproj -o "$(BUILD_DIR)/ahci-controller-tests"
	"$(BUILD_DIR)/ahci-controller-tests"

test-ahci-boot: iso | check-run-tools
	python3 tests/storage/controller_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci

test-nvme: check-build-tools ## Test NVMe block driver
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/Nvme.hyproj -o "$(BUILD_DIR)/nvme-tests"
	"$(BUILD_DIR)/nvme-tests"

test-nvme-controller: check-build-tools ## Test NVMe controller logic
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/NvmeController.hyproj -o "$(BUILD_DIR)/nvme-controller-tests"
	"$(BUILD_DIR)/nvme-controller-tests"

test-nvme-boot: iso | check-run-tools
	python3 tests/storage/controller_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)"

test-partitions: check-build-tools ## Test partition handling
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/Partitions.hyproj -o "$(BUILD_DIR)/partition-tests"
	"$(BUILD_DIR)/partition-tests"

test-vfs: check-build-tools ## Test virtual filesystem
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/vfs/Vfs.hyproj -o "$(BUILD_DIR)/vfs-tests"
	"$(BUILD_DIR)/vfs-tests"

test-storage-failure-ahci: test-hyfs2-data-ahci

test-storage-failure-nvme: test-hyfs2-data-nvme

# ====================================================================
# HYFS FILESYSTEM TESTS
# ====================================================================
##@ HyFS Filesystem Tests

test-hyfs: test-hyfs2 ## Test default HyFS2 filesystem

test-hyfs1: $(BUILD_DIR)/host-vfs/Hyfs.hy | check-build-tools ## Test HyFS1 compatibility
	@mkdir -p "$(BUILD_DIR)"
	python3 tests/vfs/hyfs_v1_fixture.py
	"$(HYDROGEN)" build tests/vfs/Hyfs.hyproj -o "$(BUILD_DIR)/hyfs-tests"
	"$(BUILD_DIR)/hyfs-tests"

test-hyfs1-boot-ahci: iso-hyfs1 | check-run-tools
	python3 tests/storage/controller_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS1_ISO)" ahci

test-hyfs1-boot-nvme: iso-hyfs1 | check-run-tools
	python3 tests/storage/controller_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS1_ISO)"

test-hyfs1-serial-ahci: iso-hyfs1 | check-run-tools
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS1_ISO)" ahci

test-hyfs1-serial-nvme: iso-hyfs1 | check-run-tools
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS1_ISO)" nvme

test-hyfs1-storage-failure-ahci: iso-hyfs1 | check-run-tools
	python3 tests/console/storage_failure_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS1_ISO)" ahci

test-hyfs1-storage-failure-nvme: iso-hyfs1 | check-run-tools
	python3 tests/console/storage_failure_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS1_ISO)" nvme

test-hyfs2: $(BUILD_DIR)/host-vfs/Hyfs.hy | check-build-tools ## Run HyFS2 host tests
	@mkdir -p "$(BUILD_DIR)"
	python3 tests/vfs/hyfs2_image_test.py
	python3 tests/vfs/hyfs_v1_fixture.py --output "$(BUILD_DIR)/hyfs-v1-compat.img"
	python3 tests/vfs/make_hyfs2_fixture.py "$(BUILD_DIR)/hyfs2-host.img"
	"$(HYDROGEN)" build tests/vfs/Hyfs2.hyproj -o "$(BUILD_DIR)/hyfs2-tests"
	"$(BUILD_DIR)/hyfs2-tests"
	"$(HYDROGEN)" build tests/vfs/Hyfs2Writer.hyproj -o "$(BUILD_DIR)/hyfs2-writer-tests"
	"$(BUILD_DIR)/hyfs2-writer-tests"

test-hyfs2-writes: test-hyfs2 ## Test HyFS2 write operations

test-hyfs2-boot-ahci: iso-hyfs2 | check-run-tools
	python3 tests/storage/controller_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci

test-hyfs2-boot-nvme: iso-hyfs2 | check-run-tools
	python3 tests/storage/controller_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)"

test-hyfs2-serial-ahci: iso-hyfs2 | check-run-tools
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci hyfs2

test-hyfs2-serial-nvme: iso-hyfs2 | check-run-tools
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme hyfs2

test-hyfs2-data-ahci: iso-hyfs2 | check-run-tools
	python3 tests/storage/hyfs2_data_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci

test-hyfs2-data-nvme: iso-hyfs2 | check-run-tools
	python3 tests/storage/hyfs2_data_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

# ====================================================================
# GRAPHICS & GPU TESTS
# ====================================================================
##@ Graphics & GPU Tests

test-graphics: check-build-tools ## Run graphics unit tests
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/graphics/Graphics.hyproj -o "$(BUILD_DIR)/graphics-tests"
	"$(BUILD_DIR)/graphics-tests"

benchmark-graphics: check-build-tools ## Benchmark graphics rendering performance
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/graphics/GraphicsBenchmark.hyproj -o "$(BUILD_DIR)/graphics-benchmark"
	python3 tests/graphics/frame_benchmark.py "$(BUILD_DIR)/graphics-benchmark" "$(BUILD_DIR)/graphics-benchmark.json"

test-display-ahci: iso-hyfs2 | check-run-tools ## Test compositor boot over AHCI
	python3 tests/graphics/display_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci

test-display-nvme: iso-hyfs2 | check-run-tools ## Test compositor boot over NVMe
	python3 tests/graphics/display_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

test-display-fallback: iso-hyfs2 | check-run-tools ## Test graphics fallback behaviour
	python3 tests/graphics/display_fallback_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci
	python3 tests/graphics/display_fallback_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

test-virtio-gpu: iso-hyfs2 | check-run-tools ## Test VirtIO-GPU 2D and oversized display boot
	python3 tests/graphics/virtio_gpu_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci vga
	python3 tests/graphics/virtio_gpu_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci
	python3 tests/graphics/virtio_gpu_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme
	python3 tests/graphics/virtio_gpu_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci oversized

test-cursor-stress: iso-hyfs2 | check-run-tools ## Test native cursor under sustained input
	python3 tests/graphics/cursor_stress_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)"

test-virtio-gpu-3d: iso-hyfs2 | check-run-tools ## Test VirtIO-GPU 3D using render node
	@test -n "$(GPU_RENDER_NODE)" || { echo "No GPU render node available"; exit 1; }
	python3 tests/graphics/virtio_gpu_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci gl "$(GPU_RENDER_NODE)"

test-frame-pacing: iso-hyfs2 | check-run-tools ## Test display frame pacing
	python3 tests/graphics/frame_pacing_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci
	python3 tests/graphics/frame_pacing_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

# ====================================================================
# CONSOLE & SERIAL TESTS
# ====================================================================
##@ Console & Serial Tests

test-terminal: check-build-tools ## Run terminal host tests
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/console/Terminal.hyproj -o "$(BUILD_DIR)/terminal-tests"
	"$(BUILD_DIR)/terminal-tests"

test-serial-ahci: iso | check-run-tools ## Test serial console via AHCI
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci hyfs2

test-serial-nvme: iso | check-run-tools ## Test serial console via NVMe
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" nvme hyfs2

# ====================================================================
# TOOL & ENVIRONMENT CHECKS
# ====================================================================
##@ Tool & Environment Checks

help: ## Show this help menu
	@printf '\n\033[1;36m  AUSTRALIS OS - Build System\033[0m\n'
	@printf '  Usage: make \033[1;32m<target>\033[0m\n'
	@awk '\
	    /^##@ / { printf "\n\033[1;33m%s\033[0m\n", substr($$0, 5); next } \
	    /^[A-Za-z0-9_.-]+:.*## / { \
	        split($$0, parts, /## /); split(parts[1], t, /:/); \
	        printf "  \033[1;32m%-30s\033[0m %s\n", t[1], parts[2]; \
	    } \
	' $(MAKEFILE_LIST)
	@printf '\n'

list-targets: ## List all phony Makefile targets
	@$(MAKE) -rRqp -f $(firstword $(MAKEFILE_LIST)) : 2>/dev/null | \
	    awk '/^\.PHONY:/ { for (i = 2; i <= NF; i++) print $$i; }' | \
	    grep -v '^\\$$' | sort -u

check-build-tools: ## Check the Hydrogen compiler is available
	@command -v "$(HYDROGEN)" >/dev/null 2>&1 || { \
	echo "Hydrogen compiler '$(HYDROGEN)' was not found."; \
	echo "Build hydrogen-stage1 or run: make HYDROGEN=/path/to/hydrogen-stage1"; \
	exit 1; \
	}

check-image-tools: check-efi-image-tools check-iso-tools ## Check all image-packaging tools

check-efi-image-tools:
	@command -v mformat >/dev/null || { echo "mformat was not found."; exit 1; }
	@command -v mmd >/dev/null || { echo "mmd was not found."; exit 1; }
	@command -v mcopy >/dev/null || { echo "mcopy was not found."; exit 1; }

check-iso-tools:
	@command -v "$(XORRISO)" >/dev/null || { echo "$(XORRISO) was not found."; exit 1; }

check-run-tools: ## Check QEMU and OVMF are available
	@command -v "$(QEMU)" >/dev/null || { echo "$(QEMU) was not found."; exit 1; }
	@test -f "$(OVMF_CODE)" || { echo "OVMF firmware was not found at $(OVMF_CODE)."; exit 1; }

check-efi-binaries:
	@test -f "$(EFI_BINARY)" || { echo "Missing $(EFI_BINARY); run 'make build' first."; exit 1; }
	@test -f "$(KERNEL_BINARY)" || { echo "Missing $(KERNEL_BINARY); run 'make build' first."; exit 1; }

check-app-binaries:
	@test -f "$(APPLICATIONS_STAMP)" || { echo "Missing application build; run 'make applications' first."; exit 1; }
	@test -d "$(APPLICATIONS_DIR)/system" || { echo "Missing system applications; run 'make applications' first."; exit 1; }
	@find "$(APPLICATIONS_DIR)" -maxdepth 1 -name '*.exec' | grep -q . || { echo "No compiled root .exec files; run 'make applications' first."; exit 1; }

check-hyfs1-iso:
	@test -f "$(HYFS1_ISO)" || { echo "Missing $(HYFS1_ISO); run 'make iso-hyfs1' first."; exit 1; }

check-hyfs2-iso:
	@test -f "$(HYFS2_ISO)" || { echo "Missing $(HYFS2_ISO); run 'make iso' first."; exit 1; }

check-hyfs2-data-disk:
	@test -f "$(HYFS2_DATA_DISK)" || { echo "Missing $(HYFS2_DATA_DISK); run 'make hyfs2-data-disk' first."; exit 1; }
