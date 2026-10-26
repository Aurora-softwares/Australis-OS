# GNU Makefile for Australis OS.

# Build compilation, packaging, and QEMU launching are intentionally separate.
# Run `make help` to see the supported commands.
.DEFAULT_GOAL := help

# Defaults. Override these on the command line, e.g.:
# make run HYFS=1 GPU_DRIVER=gop BOOT_DEVICE=nvme
HYFS              ?= 2
GPU_DRIVER        ?= virtio2d
BOOT_DEVICE       ?= ahci
BOOT_CDROM        ?= 0
USB_STORAGE       ?= 0
DATA_DISK         ?= $(if $(filter 1,$(HYFS)),none,ahci)
SERIAL            ?= stdio
QEMU_MEMORY       ?= 256M
QEMU_EXTRA_ARGS   ?=

# External tools and host configuration
HYDROGEN		?= ../Hylang-Compiler/build/self_hosting/hydrogen-stage1
QEMU			?= qemu-system-x86_64
QEMU_DISPLAY	?= sdl
XORRISO			?= xorriso
OVMF_CODE		?= /usr/share/OVMF/OVMF_CODE_4M.fd
GPU_RENDER_NODE	?= $(firstword $(wildcard /dev/dri/renderD*))
TIMESTAMP		?= false
TIMESTAMP_ARGS	?=

# Reject typos instead of silently running an unintended configuration.
define validate-option
	$(if $(filter $(strip $($(1))),$(2)),,$(error Invalid $(1)='$($(1))'; valid values: $(2)))
endef
$(call validate-option,HYFS,1 2)
$(call validate-option,GPU_DRIVER,gop virtio2d virgl3d)
$(call validate-option,BOOT_DEVICE,ahci nvme usb cdrom)
$(call validate-option,BOOT_CDROM,0 1)
$(call validate-option,USB_STORAGE,0 1)
$(call validate-option,DATA_DISK,none ahci nvme)
$(call validate-option,SERIAL,stdio none only)

# Build directories
BUILD_DIR := build
EFI_DIR := $(BUILD_DIR)/efi
EFI_BOOT_DIR := $(EFI_DIR)/EFI/BOOT
GENERATED_ROOTFS := $(BUILD_DIR)/rootfs
APPLICATIONS_DIR := $(BUILD_DIR)/applications

# EFI and kernel
PROJECT := src/australis.hyproj
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

# HyFS image configuration, shared between both filesystem versions.
HYFS_SOURCES := $(wildcard tools/HyFS$(HYFS)Image/*.hy)
HYFS_TOOL := $(BUILD_DIR)/tools/hyfs$(HYFS)-image
HYFS_PROJECT := tools/HyFS$(HYFS)Image/HyFS$(HYFS)Image.hyproj
HYFS_IMAGE := $(BUILD_DIR)/boot/root.hyfs$(HYFS).img
HYFS_ISO_ROOT := $(BUILD_DIR)/iso-root-hyfs$(HYFS)
hyfs_iso = $(BUILD_DIR)/australis-hyfs$(1).iso
ISO := $(call hyfs_iso,$(HYFS))
HYFS_IMAGE_BUILDER := tools/make_hyfs$(HYFS)_image.py

# HyFS2 adds system app manifests and supports a persistent, writable data disk.
HYFS2_DATA_DISK ?= $(BUILD_DIR)/hyfs2-data.img

# QEMU composition: one boot source, one display selection, optional peripherals.
HYFS_GPT_TYPE := 9f5eb82e-692e-5a8f-b968-adaaa349dd93
QEMU_BASE_ARGS = -machine q35 -m $(QEMU_MEMORY) -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)"
AHCI_DISK_ARGS = -device ich9-ahci,id=ahci0 -drive if=none,id=sata0,format=raw,snapshot=on,file="$(ISO)" -device ide-hd,drive=sata0,bus=ahci0.0
NVME_DISK_ARGS = -drive if=none,id=nvme0,format=raw,readonly=on,file="$(ISO)" -device nvme,serial=australis,drive=nvme0
USB_CONTROLLER_ARGS = -device qemu-xhci,id=xhci0
USB_INPUT_ARGS = -device usb-kbd,bus=xhci0.0 -device usb-mouse,bus=xhci0.0
USB_STORAGE_ARGS = -drive if=none,id=usb0,format=raw,readonly=on,file="$(ISO)" -device usb-storage,drive=usb0,bus=xhci0.0

ifeq ($(HYFS),1)
	ifneq ($(DATA_DISK),none)
		$(error Writable DATA_DISK requires HYFS=2)
	endif
endif

ifeq ($(HYFS),2)
	HYFS_IMAGE_INPUTS := tools/hyfs2.py src/userland/system/startup.manifest src/userland/system/capabilities.manifest $(APPLICATIONS_STAMP)
	HYFS_IMAGE_EXTRA_ARGS := --system-apps "$(APPLICATIONS_DIR)/system"
endif

ifeq ($(TIMESTAMP),true)
    TIMESTAMP_ARGS := 2>&1 | perl -MTime::HiRes=time -ne 'BEGIN { $$|=1; $$last=time } $$now=time; printf "[+%.3fs] %s", $$now-$$last, $$_; $$last=$$now'
endif

ifeq ($(BOOT_DEVICE),ahci)
	RUN_BOOT_ARGS = $(AHCI_DISK_ARGS)
else ifeq ($(BOOT_DEVICE),nvme)
	RUN_BOOT_ARGS = $(NVME_DISK_ARGS)
else ifeq ($(BOOT_DEVICE),usb)
	RUN_BOOT_ARGS = $(USB_STORAGE_ARGS)
else
	RUN_BOOT_ARGS = -cdrom "$(ISO)"
endif

# An optional second CD-ROM retains the previous dual-attachment boot setup.
ifneq ($(BOOT_DEVICE),cdrom)
	ifeq ($(BOOT_CDROM),1)
		RUN_CDROM_ARGS = -cdrom "$(ISO)"
	endif
endif

ifeq ($(SERIAL),only)
    RUN_DISPLAY_ARGS = -display none
else ifeq ($(GPU_DRIVER),gop)
    RUN_DISPLAY_ARGS = -display $(QEMU_DISPLAY) -vga std
else ifeq ($(GPU_DRIVER),virtio2d)
    RUN_DISPLAY_ARGS = -display $(QEMU_DISPLAY) -vga none -device virtio-vga,id=gpu0
else ifeq ($(GPU_DRIVER),virgl3d)
    RUN_DISPLAY_ARGS = -display $(QEMU_DISPLAY),gl=on -vga none -device virtio-vga-gl,id=gpu0
endif

ifeq ($(SERIAL),none)
	RUN_SERIAL_ARGS =
else
	RUN_SERIAL_ARGS = -serial stdio
endif

ifneq ($(SERIAL),only)
	RUN_USB_INPUT_ARGS = $(USB_INPUT_ARGS)
endif

ifeq ($(USB_STORAGE),1)
	ifneq ($(BOOT_DEVICE),usb)
		RUN_USB_STORAGE_ARGS = $(USB_STORAGE_ARGS)
	endif
endif

ifeq ($(DATA_DISK),ahci)
	ifeq ($(BOOT_DEVICE),ahci)
		# Reuse the boot AHCI controller, placing the writable disk on port 1.
		RUN_DATA_ARGS = -drive if=none,id=data0,format=raw,file="$(HYFS2_DATA_DISK)" -device ide-hd,drive=data0,bus=ahci0.1
	else
		RUN_DATA_ARGS = -device ich9-ahci,id=ahci-data -drive if=none,id=data0,format=raw,file="$(HYFS2_DATA_DISK)" -device ide-hd,drive=data0,bus=ahci-data.0
	endif
else ifeq ($(DATA_DISK),nvme)
	RUN_DATA_ARGS = -drive if=none,id=data0,format=raw,file="$(HYFS2_DATA_DISK)" -device nvme,serial=australis-data,drive=data0
endif

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

RELEASE_DOCS :=

# ====================================================================
# PHONY TARGET DECLARATIONS
# ====================================================================

# Build & Compilation
.PHONY: all build applications rebuild-applications
.PHONY: clean

# Images & Packaging
.PHONY: image boot_image iso iso-hyfs1
.PHONY: iso-hyfs2 data-disk

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
.PHONY: test-display test-display-fallback test-virtio-gpu test-virtio-gpu-3d test-frame-pacing

# Console & Serial Tests
.PHONY: test-terminal test-serial-ahci test-serial-nvme

# Tool & Environment Checks
.PHONY: help config list-targets check-build-tools check-image-tools
.PHONY: check-efi-image-tools check-iso-tools check-run-tools check-efi-binaries
.PHONY: check-app-binaries check-hyfs-iso check-hyfs1-iso check-hyfs2-iso check-data-disk

# Permissions
.PHONY: test-retained-denial test-ci-retained-denial

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

$(IMAGE): $(EFI_INPUT_STAMP) $(EFI_BINARY) $(KERNEL_BINARY) | check-efi-image-tools check-efi-binaries
	@mkdir -p "$(BUILD_DIR)"
	@rm -f "$@"
	truncate -s 64M "$@"
	mformat -i "$@" -F ::
	mmd -i "$@" ::/EFI ::/EFI/BOOT ::/EFI/AUSTRALIS
	mcopy -i "$@" "$(EFI_BINARY)" ::/EFI/BOOT/BOOTX64.EFI
	mcopy -i "$@" "$(KERNEL_BINARY)" ::/EFI/AUSTRALIS/KERNEL.BIN

$(EFI_BOOT_IMAGE): $(EFI_INPUT_STAMP) $(EFI_BINARY) $(KERNEL_BINARY) | check-efi-image-tools check-efi-binaries
	@mkdir -p "$(dir $(EFI_BOOT_IMAGE))"
	@rm -f "$@"
	truncate -s 8M "$@"
	mformat -i "$@" ::
	mmd -i "$@" ::/EFI ::/EFI/BOOT ::/EFI/AUSTRALIS
	mcopy -i "$@" "$(EFI_BINARY)" ::/EFI/BOOT/BOOTX64.EFI
	mcopy -i "$@" "$(KERNEL_BINARY)" ::/EFI/AUSTRALIS/KERNEL.BIN

# Compile the selected image tool (maintained for direct tool builds).
$(HYFS_TOOL): $(HYFS_PROJECT) $(HYFS_SOURCES) | check-build-tools
	@mkdir -p "$(dir $@)"
	"$(HYDROGEN)" build "$(HYFS_PROJECT)" -o "$@"

# Construct either HyFS1 or HyFS2 with the appropriate generator and inputs.
$(HYFS_IMAGE): $(HYFS_IMAGE_BUILDER) $(HYFS_IMAGE_INPUTS) $(ROOTFS_STAMP)
	@mkdir -p "$(dir $@)"
	python3 "$(HYFS_IMAGE_BUILDER)" "$(GENERATED_ROOTFS)" "$@" $(HYFS_IMAGE_EXTRA_ARGS)

# Existing writable HyFS2 data-disk format; intentionally version-specific.
$(HYFS2_DATA_DISK): $(wildcard $(call hyfs_iso,2)) | check-hyfs2-iso
	python3 tools/make_hyfs2_data_disk.py "$(call hyfs_iso,2)" "$@"

# Bootable ISO packaging, common to both filesystem versions.
$(ISO): $(EFI_BOOT_IMAGE) $(HYFS_IMAGE) | check-iso-tools check-efi-binaries check-app-binaries
	@rm -rf "$(HYFS_ISO_ROOT)"
	@mkdir -p "$(HYFS_ISO_ROOT)/EFI/BOOT"
	cp "$(EFI_BOOT_IMAGE)" "$(HYFS_ISO_ROOT)/EFI/BOOT/efiboot.img"
	"$(XORRISO)" -as mkisofs -R -J \
	-eltorito-alt-boot -e EFI/BOOT/efiboot.img -no-emul-boot \
	-efi-boot-part --efi-boot-image \
	-append_partition 4 "$(HYFS_GPT_TYPE)" "$(HYFS_IMAGE)" -appended_part_as_gpt \
	-o "$@" "$(HYFS_ISO_ROOT)"

# VFS host test input

$(BUILD_DIR)/host-vfs/Hyfs.hy: src/kernel/vfs/Hyfs.hy tests/vfs/build_host_hyfs.py
	python3 tests/vfs/build_host_hyfs.py "$<" "$@"

# ====================================================================
# BUILD & COMPILATION
# ====================================================================
##@ Build & Compilation

all: ## Compile the OS and applications, then create EFI and selected HyFS ISO (no QEMU)
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

iso: check-efi-binaries check-app-binaries $(ISO) ## Build the selected HyFS ISO (default: v2)

iso-hyfs1: ## Build the HyFS1 ISO (regardless of HYFS setting)
	@$(MAKE) iso HYFS=1 PROJECT="$(PROJECT)"

iso-hyfs2: ## Build the HyFS2 ISO (regardless of HYFS setting)
	@$(MAKE) iso HYFS=2 PROJECT="$(PROJECT)"

data-disk: $(HYFS2_DATA_DISK) ## Generate a writable HyFS2 data disk

# ====================================================================
# QEMU & EMULATION
# ====================================================================
##@ QEMU & Emulation

run: | check-run-tools check-hyfs-iso $(if $(filter none,$(DATA_DISK)),,check-data-disk) ## Boot HyFS2, VirtIO 2D, AHCI disk by default
	"$(QEMU)" $(QEMU_BASE_ARGS) $(RUN_BOOT_ARGS) $(RUN_CDROM_ARGS) $(USB_CONTROLLER_ARGS) $(RUN_USB_INPUT_ARGS) $(RUN_USB_STORAGE_ARGS) $(RUN_DATA_ARGS) $(RUN_DISPLAY_ARGS) -net none -monitor none $(RUN_SERIAL_ARGS) $(QEMU_EXTRA_ARGS) $(TIMESTAMP_ARGS)

# Preserve versioned run-* targets without duplicating QEMU invocations.
define versioned-run-alias
run-$(1)-hyfs$(2):
	@$(MAKE) run-$(1) HYFS=$(2) $(if $(filter 1,$(2)),GPU_DRIVER=gop,)
endef
$(foreach v,1 2,$(foreach mode,gop serial disk disk-serial nvme nvme-serial usb-storage usb-storage-nvme,$(eval $(call versioned-run-alias,$(mode),$(v)))))

run-data-ahci-hyfs2: run-data-ahci
run-data-nvme-hyfs2: run-data-nvme

# ====================================================================
# KERNEL & BOOT TESTS
# ====================================================================
##@ Kernel & Boot Tests

test-rescue-boot: image | check-run-tools ## Smoke-test the rescue monitor boot
	python3 tests/console/rescue_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(IMAGE)"

test-bootloader-negative: image | check-run-tools ## Test missing or invalid kernel boot cases
	python3 tests/bootloader/negative_kernel_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(IMAGE)" "$(KERNEL_BINARY)"

test-boot-modes: iso-hyfs2 | check-run-tools ## Test bootloader boot modes
	python3 tests/bootloader/boot_modes.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)"

test-kmon-recovery: iso-hyfs2 | check-run-tools ## Test kernel monitor recovery commands
	python3 tests/console/recovery_commands_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)"

test-kernel-panic: iso-hyfs2 | check-run-tools ## Test kernel panic behaviour
	python3 tests/kernel/panic_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)"
	python3 tests/kernel/panic_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" gpu

test-stage2: check-build-tools ## Run kernel Stage 2 host tests
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/kernel/Stage2.hyproj -o "$(BUILD_DIR)/stage2-tests"
	@chmod +x "$(BUILD_DIR)/stage2-tests"
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
	@chmod +x "$(BUILD_DIR)/usb-tests"
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
	@chmod +x "$(BUILD_DIR)/user-runtime-tests"
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
	@chmod +x "$(BUILD_DIR)/user-runtime-tests"
	"$(BUILD_DIR)/user-runtime-tests" inspector "$(BUILD_DIR)/inspector-file-api.exec"
	"$(BUILD_DIR)/user-runtime-tests" file-api "$(BUILD_DIR)/file-api-test.exec"

test-auex-portable-api: $(APP_COMPILER) ## Test AUEX portable API
	@mkdir -p "$(BUILD_DIR)"
	"$(APP_COMPILER)" build applications/Australis.Dev-user-demo/UserDemo.hyproj -o "$(BUILD_DIR)/portable-api-test.exec"
	"$(APP_COMPILER)" build tests/user/PortableApiApp.hyproj -o "$(BUILD_DIR)/portable-io-test.exec"
	"$(HYDROGEN)" build tests/user/UserRuntime.hyproj -o "$(BUILD_DIR)/user-runtime-tests"
	@chmod +x "$(BUILD_DIR)/user-runtime-tests"
	"$(BUILD_DIR)/user-runtime-tests" portable-api "$(BUILD_DIR)/portable-api-test.exec"
	"$(BUILD_DIR)/user-runtime-tests" portable-io "$(BUILD_DIR)/portable-io-test.exec"

test-auex-arguments: test-auex-arguments-image ## Test native application arguments
	python3 tests/user/argument_program_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci
	python3 tests/user/argument_program_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

test-auex-arguments-image: $(APP_COMPILER) | check-run-tools
	"$(APP_COMPILER)" build tests/user/ArgumentApp.hyproj -o "$(BUILD_DIR)/argv-check.exec"
	"$(MAKE)" iso-hyfs2 APPLICATION_ARTIFACTS="$(BUILD_DIR)/argv-check.exec"

test-userland-stage1: test-userland-stage1-host test-userland-stage1-image ## Run Stage 1 userland boot tests
	python3 tests/user/stage1_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci
	python3 tests/user/stage1_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

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
	python3 tests/user/stage1_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci

test-userland-stage1-nvme: test-userland-stage1-image
	python3 tests/user/stage1_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

test-userland-stage2: iso-hyfs2 | check-run-tools ## Test Stage 2 userland boot and context
	"$(APP_COMPILER)" build tests/user/ContextProbe.hyproj -o "$(BUILD_DIR)/context-probe.exec"
	python3 tests/user/stage2_shell_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" "$(BUILD_DIR)/context-probe.exec" ahci
	python3 tests/user/stage2_shell_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" "$(BUILD_DIR)/context-probe.exec" nvme

test-userland-stage3: iso-hyfs2 | check-run-tools ## Test userland system recovery
	python3 tests/user/system_image_recovery_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci
	python3 tests/user/system_image_recovery_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

test-userland-stage4-supervision: iso-hyfs2 | check-run-tools ## Test supervisor fault handling
	python3 tests/user/stage4_supervision_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" "$(APPLICATIONS_DIR)/user-fault.exec" ahci
	python3 tests/user/stage4_supervision_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" "$(APPLICATIONS_DIR)/user-fault.exec" nvme

test-userland-stage4-concurrency: test-userland-stage4-concurrency-image ## Test concurrent userland applications
	python3 tests/user/stage4_concurrency_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci
	python3 tests/user/stage4_concurrency_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

test-userland-stage4-concurrency-image: $(APP_COMPILER) | check-run-tools
	"$(APP_COMPILER)" build tests/user/ConcurrentA.hyproj -o "$(BUILD_DIR)/concurrent-a.exec"
	"$(APP_COMPILER)" build tests/user/ConcurrentB.hyproj -o "$(BUILD_DIR)/concurrent-b.exec"
	"$(APP_COMPILER)" build tests/user/ConcurrentProbe.hyproj -o "$(BUILD_DIR)/concurrent-probe.exec"
	"$(MAKE)" iso-hyfs2 APPLICATION_ARTIFACTS="$(BUILD_DIR)/concurrent-a.exec $(BUILD_DIR)/concurrent-b.exec $(BUILD_DIR)/concurrent-probe.exec"

test-userland-stage5-ipc: test-userland-stage5-ipc-image ## Test userland IPC across processes
	python3 tests/user/stage5_ipc_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci
	python3 tests/user/stage5_ipc_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

test-userland-stage5-ipc-image: $(APP_COMPILER) | check-run-tools
	"$(APP_COMPILER)" build tests/user/IpcProbe.hyproj -o "$(BUILD_DIR)/ipc-probe.exec"
	"$(APP_COMPILER)" build tests/user/IpcChild.hyproj -o "$(BUILD_DIR)/ipc-child.exec"
	"$(APP_COMPILER)" build tests/user/IpcExit.hyproj -o "$(BUILD_DIR)/ipc-exit.exec"
	"$(APP_COMPILER)" build tests/user/IpcDenied.hyproj -o "$(BUILD_DIR)/ipc-denied.exec"
	"$(APP_COMPILER)" build tests/user/IpcNoop.hyproj -o "$(BUILD_DIR)/ipc-noop.exec"
	"$(MAKE)" iso-hyfs2 APPLICATION_ARTIFACTS="$(BUILD_DIR)/ipc-probe.exec $(BUILD_DIR)/ipc-child.exec $(BUILD_DIR)/ipc-exit.exec $(BUILD_DIR)/ipc-denied.exec $(BUILD_DIR)/ipc-noop.exec"

test-userland-cat: iso-hyfs2 | check-run-tools ## Test cat command in QEMU
	python3 tests/user/cat_program_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci
	python3 tests/user/cat_program_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

test-userland-info: PROJECT = tests/user/BootImage.hyproj
test-userland-info: iso-hyfs2 | check-run-tools ## Test system information commands
	python3 tests/user/system_info_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci
	python3 tests/user/system_info_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

test-userland-files-processes: PROJECT = tests/user/BootImage.hyproj
test-userland-files-processes: iso-hyfs2 | check-run-tools ## Test file and process command support
	python3 tests/user/files_processes_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci
	python3 tests/user/files_processes_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

test-userland-shell-preview: $(APP_COMPILER) check-build-tools ## Test CommandShell via host runtime
	"$(APP_COMPILER)" build src/shell/australis.shell.hyproj -o "$(BUILD_DIR)/CommandShell.exec"
	"$(HYDROGEN)" build tests/user/UserRuntime.hyproj -o "$(BUILD_DIR)/user-runtime-tests"
	@chmod +x "$(BUILD_DIR)/user-runtime-tests"
	"$(BUILD_DIR)/user-runtime-tests" shell-preview "$(BUILD_DIR)/CommandShell.exec"
	"$(BUILD_DIR)/user-runtime-tests" shell-commands "$(BUILD_DIR)/CommandShell.exec"

test-userland-system-host: $(APP_COMPILER) check-build-tools ## Test System.exec via host runtime
	"$(APP_COMPILER)" build src/userland/australis.userland.hyproj -o "$(BUILD_DIR)/System.exec"
	"$(HYDROGEN)" build tests/user/UserRuntime.hyproj -o "$(BUILD_DIR)/user-runtime-tests"
	@chmod +x "$(BUILD_DIR)/user-runtime-tests"
	"$(BUILD_DIR)/user-runtime-tests" system-launch "$(BUILD_DIR)/System.exec"
	"$(BUILD_DIR)/user-runtime-tests" system-failure "$(BUILD_DIR)/System.exec"

test-userland-system-boot: iso-hyfs2 | check-run-tools ## Smoke-test system boot in QEMU
	python3 tests/user/system_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci
	python3 tests/user/system_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

test-userland-essentials: iso-hyfs2 | check-run-tools ## Smoke-test essential userland services
	python3 tests/user/essentials_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci
	python3 tests/user/essentials_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

# ====================================================================
# NATIVE EXECUTION & STORAGE PERSISTENCE TESTS
# ====================================================================
##@ Native Execution & Storage Persistence Tests

test-native-user-mode: test-native-user-mode-image ## Test native user-mode isolation and process execution
	python3 tests/user/native_user_mode_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci
	python3 tests/user/native_user_mode_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

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
	python3 tests/user/native_files_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci
	python3 tests/user/native_files_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

test-stage6: test-hyfs2 test-stage6-ahci test-stage6-nvme ## Run Stage 6 persistent filesystem tests

test-stage6-image: $(APP_COMPILER) | check-run-tools
	"$(APP_COMPILER)" build tests/user/PersistentFileApp.hyproj -o "$(BUILD_DIR)/stage6-file-test.exec"
	"$(MAKE)" iso-hyfs2 APPLICATION_ARTIFACTS="$(BUILD_DIR)/stage6-file-test.exec"

test-stage6-ahci: test-stage6-image
	python3 tests/storage/hyfs2_persistent_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci

test-stage6-nvme: test-stage6-image
	python3 tests/storage/hyfs2_persistent_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

# ====================================================================
# STORAGE & CONTROLLER TESTS
# ====================================================================
##@ Storage & Controller Tests

test-storage: check-build-tools ## Run block-device host tests
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/BlockDevice.hyproj -o "$(BUILD_DIR)/storage-tests"
	@chmod +x "$(BUILD_DIR)/storage-tests"
	"$(BUILD_DIR)/storage-tests"

test-ahci: check-build-tools ## Test AHCI block driver
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/Ahci.hyproj -o "$(BUILD_DIR)/ahci-tests"
	@chmod +x "$(BUILD_DIR)/ahci-tests"
	"$(BUILD_DIR)/ahci-tests"

test-ahci-controller: check-build-tools ## Test AHCI controller logic
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/AhciController.hyproj -o "$(BUILD_DIR)/ahci-controller-tests"
	@chmod +x "$(BUILD_DIR)/ahci-controller-tests"
	"$(BUILD_DIR)/ahci-controller-tests"

test-ahci-boot: iso | check-run-tools
	python3 tests/storage/controller_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci

test-nvme: check-build-tools ## Test NVMe block driver
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/Nvme.hyproj -o "$(BUILD_DIR)/nvme-tests"
	@chmod +x "$(BUILD_DIR)/nvme-tests"
	"$(BUILD_DIR)/nvme-tests"

test-nvme-controller: check-build-tools ## Test NVMe controller logic
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/NvmeController.hyproj -o "$(BUILD_DIR)/nvme-controller-tests"
	@chmod +x "$(BUILD_DIR)/nvme-controller-tests"
	"$(BUILD_DIR)/nvme-controller-tests"

test-nvme-boot: iso | check-run-tools
	python3 tests/storage/controller_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)"

test-partitions: check-build-tools ## Test partition handling
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/Partitions.hyproj -o "$(BUILD_DIR)/partition-tests"
	@chmod +x "$(BUILD_DIR)/partition-tests"
	"$(BUILD_DIR)/partition-tests"

test-vfs: check-build-tools ## Test virtual filesystem
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/vfs/Vfs.hyproj -o "$(BUILD_DIR)/vfs-tests"
	@chmod +x "$(BUILD_DIR)/vfs-tests"
	"$(BUILD_DIR)/vfs-tests"

test-storage-failure-ahci: test-hyfs2-data-ahci

test-storage-failure-nvme: test-hyfs2-data-nvme

# ====================================================================
# HYFS FILESYSTEM TESTS
# ====================================================================
##@ HyFS Filesystem Tests

test-hyfs: test-hyfs$(HYFS) ## Test selected HyFS filesystem

test-hyfs1: $(BUILD_DIR)/host-vfs/Hyfs.hy | check-build-tools ## Test HyFS1 compatibility
	@mkdir -p "$(BUILD_DIR)"
	python3 tests/vfs/hyfs_v1_fixture.py
	"$(HYDROGEN)" build tests/vfs/Hyfs.hyproj -o "$(BUILD_DIR)/hyfs-tests"
	@chmod +x "$(BUILD_DIR)/hyfs-tests"
	"$(BUILD_DIR)/hyfs-tests"

test-hyfs1-boot-ahci: iso-hyfs1 | check-run-tools
	python3 tests/storage/controller_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,1)" ahci

test-hyfs1-boot-nvme: iso-hyfs1 | check-run-tools
	python3 tests/storage/controller_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,1)"

test-hyfs1-serial-ahci: iso-hyfs1 | check-run-tools
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,1)" ahci

test-hyfs1-serial-nvme: iso-hyfs1 | check-run-tools
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,1)" nvme

test-hyfs1-storage-failure-ahci: iso-hyfs1 | check-run-tools
	python3 tests/console/storage_failure_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,1)" ahci

test-hyfs1-storage-failure-nvme: iso-hyfs1 | check-run-tools
	python3 tests/console/storage_failure_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,1)" nvme

test-hyfs2: $(BUILD_DIR)/host-vfs/Hyfs.hy | check-build-tools ## Run HyFS2 host tests
	@mkdir -p "$(BUILD_DIR)"
	python3 tests/vfs/hyfs2_image_test.py
	python3 tests/vfs/hyfs_v1_fixture.py --output "$(BUILD_DIR)/hyfs-v1-compat.img"
	python3 tests/vfs/make_hyfs2_fixture.py "$(BUILD_DIR)/hyfs2-host.img"
	"$(HYDROGEN)" build tests/vfs/Hyfs2.hyproj -o "$(BUILD_DIR)/hyfs2-tests"
	@chmod +x "$(BUILD_DIR)/hyfs2-tests"
	"$(BUILD_DIR)/hyfs2-tests"
	"$(HYDROGEN)" build tests/vfs/Hyfs2Writer.hyproj -o "$(BUILD_DIR)/hyfs2-writer-tests"
	@chmod +x "$(BUILD_DIR)/hyfs2-writer-tests"
	"$(BUILD_DIR)/hyfs2-writer-tests"

test-hyfs2-writes: test-hyfs2 ## Test HyFS2 write operations

test-hyfs2-boot-ahci: iso-hyfs2 | check-run-tools
	python3 tests/storage/controller_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci

test-hyfs2-boot-nvme: iso-hyfs2 | check-run-tools
	python3 tests/storage/controller_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)"

test-hyfs2-serial-ahci: iso-hyfs2 | check-run-tools
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci hyfs2

test-hyfs2-serial-nvme: iso-hyfs2 | check-run-tools
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme hyfs2

test-hyfs2-data-ahci: iso-hyfs2 | check-run-tools
	python3 tests/storage/hyfs2_data_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci

test-hyfs2-data-nvme: iso-hyfs2 | check-run-tools
	python3 tests/storage/hyfs2_data_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

# ====================================================================
# GRAPHICS & GPU TESTS
# ====================================================================
##@ Graphics & GPU Tests

test-graphics: check-build-tools ## Run graphics unit tests
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/graphics/Graphics.hyproj -o "$(BUILD_DIR)/graphics-tests"
	@chmod +x "$(BUILD_DIR)/graphics-tests"
	"$(BUILD_DIR)/graphics-tests"

benchmark-graphics: check-build-tools ## Benchmark graphics rendering performance
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/graphics/GraphicsBenchmark.hyproj -o "$(BUILD_DIR)/graphics-benchmark"
	@chmod +x "$(BUILD_DIR)/graphics-benchmark"
	python3 tests/graphics/frame_benchmark.py "$(BUILD_DIR)/graphics-benchmark" "$(BUILD_DIR)/graphics-benchmark.json"

test-display: test-display-ahci test-display-nvme test-display-fallback

test-display-ahci: iso-hyfs2 | check-run-tools ## Test compositor boot over AHCI
	python3 tests/graphics/display_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci

test-display-nvme: iso-hyfs2 | check-run-tools ## Test compositor boot over NVMe
	python3 tests/graphics/display_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

test-display-fallback: iso-hyfs2 | check-run-tools ## Test graphics fallback behaviour
	python3 tests/graphics/display_fallback_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci
	python3 tests/graphics/display_fallback_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

test-virtio-gpu: iso-hyfs2 | check-run-tools ## Test VirtIO-GPU 2D and oversized display boot
	python3 tests/graphics/virtio_gpu_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci vga
	python3 tests/graphics/virtio_gpu_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci
	python3 tests/graphics/virtio_gpu_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme
	python3 tests/graphics/virtio_gpu_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci oversized

test-cursor-stress: iso-hyfs2 | check-run-tools ## Test native cursor under sustained input
	python3 tests/graphics/cursor_stress_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)"

test-virtio-gpu-3d: iso-hyfs2 | check-run-tools ## Test VirtIO-GPU 3D using render node
	@test -n "$(GPU_RENDER_NODE)" || { echo "No GPU render node available"; exit 1; }
	python3 tests/graphics/virtio_gpu_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci gl "$(GPU_RENDER_NODE)"

test-frame-pacing: iso-hyfs2 | check-run-tools ## Test display frame pacing
	python3 tests/graphics/frame_pacing_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci
	python3 tests/graphics/frame_pacing_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

# ====================================================================
# CONSOLE & SERIAL TESTS
# ====================================================================
##@ Console & Serial Tests

test-terminal: check-build-tools ## Run terminal host tests
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/console/Terminal.hyproj -o "$(BUILD_DIR)/terminal-tests"
	@chmod +x "$(BUILD_DIR)/terminal-tests"
	"$(BUILD_DIR)/terminal-tests"

test-serial-ahci: iso-hyfs2 | check-run-tools ## Test serial console via AHCI
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci hyfs2

test-serial-nvme: iso-hyfs2 | check-run-tools ## Test serial console via NVMe
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" nvme hyfs2

# ====================================================================
# PERMISSIONS TESTS
# ====================================================================
##@ Permissions Tests

test-retained-denial: $(APP_COMPILER) | check-run-tools
	@mkdir -p "$(BUILD_DIR)"
	@if grep -q '^/System/Bin/retained-permission\.exec|' src/userland/system/capabilities.manifest; then \
		echo "ERROR: retained test application has capabilities"; \
		exit 1; \
	fi
	"$(APP_COMPILER)" build tests/user/RetainedPermissionApp.hyproj -o "$(BUILD_DIR)/retained-permission.exec"
	"$(MAKE)" iso-hyfs2 APPLICATION_ARTIFACTS="$(BUILD_DIR)/retained-permission.exec"
	python3 tests/user/retained_permission_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" ahci
	python3 tests/user/retained_permission_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(call hyfs_iso,2)" nvme

# ====================================================================
# AUTOMATIC CI TEST REGISTRY
# ====================================================================
# Every independent test-ci-* target is discovered by tools/run_ci_tests.py.
# CI executes all aliases, including default HyFS2, VirtIO-GPU 2D, storage,
# user isolation, persistence, recovery and both AHCI/NVMe boot paths.
# Use leaf targets only; aggregate test-* targets would run the same test twice.
# Future tests require only a test-ci-NAME target, not workflow YAML changes.
# Headless CI cannot run test-virtio-gpu-3d without a DRM render node.
.PHONY: test-ci-storage test-ci-ahci test-ci-ahci-controller test-ci-nvme test-ci-nvme-controller test-ci-partitions test-ci-vfs test-ci-usb test-ci-terminal test-ci-stage2 test-ci-graphics test-ci-hyfs1 test-ci-hyfs2 test-ci-rescue-boot test-ci-bootloader-negative test-ci-boot-modes test-ci-kmon-recovery test-ci-kernel-panic test-ci-stage2-boot-ahci test-ci-stage2-boot-nvme test-ci-stage3-ahci test-ci-stage3-nvme test-ci-stage4-ahci test-ci-stage4-nvme test-ci-mouse-ahci test-ci-mouse-nvme test-ci-stage5-host test-ci-stage5-ahci test-ci-stage5-nvme test-ci-xhci-multi test-ci-serial-ahci test-ci-serial-nvme test-ci-hyfs2-boot-ahci test-ci-hyfs2-boot-nvme test-ci-hyfs1-boot-ahci test-ci-hyfs1-boot-nvme test-ci-display-ahci test-ci-display-nvme test-ci-display-fallback test-ci-virtio-gpu test-ci-frame-pacing test-ci-userland-system-host test-ci-userland-shell-preview test-ci-userland-system-boot test-ci-userland-essentials test-ci-userland-cat test-ci-native-files test-ci-auex-file-api test-ci-auex-portable-api test-ci-auex-arguments test-ci-userland-stage1-host test-ci-userland-stage1-ahci test-ci-userland-stage1-nvme test-ci-userland-stage2 test-ci-userland-stage3 test-ci-userland-stage4-supervision test-ci-userland-stage4-concurrency test-ci-userland-stage5-ipc test-ci-userland-info test-ci-userland-files-processes test-ci-native-user-mode test-ci-stage6-ahci test-ci-stage6-nvme test-ci-hyfs1-serial-ahci test-ci-hyfs1-serial-nvme test-ci-hyfs1-storage-failure-ahci test-ci-hyfs1-storage-failure-nvme test-ci-hyfs2-data-ahci test-ci-hyfs2-data-nvme test-ci-cursor-stress

test-ci-storage: test-storage
test-ci-ahci: test-ahci
test-ci-ahci-controller: test-ahci-controller
test-ci-nvme: test-nvme
test-ci-nvme-controller: test-nvme-controller
test-ci-partitions: test-partitions
test-ci-vfs: test-vfs
test-ci-usb: test-usb
test-ci-terminal: test-terminal
test-ci-stage2: test-stage2
test-ci-graphics: test-graphics
test-ci-hyfs1: test-hyfs1
test-ci-hyfs2: test-hyfs2
test-ci-rescue-boot: test-rescue-boot
test-ci-bootloader-negative: test-bootloader-negative
test-ci-boot-modes: test-boot-modes
test-ci-kmon-recovery: test-kmon-recovery
test-ci-kernel-panic: test-kernel-panic
test-ci-stage2-boot-ahci: test-stage2-boot-ahci
test-ci-stage2-boot-nvme: test-stage2-boot-nvme
test-ci-stage3-ahci: test-stage3-ahci
test-ci-stage3-nvme: test-stage3-nvme
test-ci-stage4-ahci: test-stage4-ahci
test-ci-stage4-nvme: test-stage4-nvme
test-ci-mouse-ahci: test-mouse-ahci
test-ci-mouse-nvme: test-mouse-nvme
test-ci-stage5-host: test-stage5-host
test-ci-stage5-ahci: test-stage5-ahci
test-ci-stage5-nvme: test-stage5-nvme
test-ci-xhci-multi: test-xhci-multi
test-ci-serial-ahci: test-serial-ahci
test-ci-serial-nvme: test-serial-nvme
test-ci-hyfs2-boot-ahci: test-hyfs2-boot-ahci
test-ci-hyfs2-boot-nvme: test-hyfs2-boot-nvme
test-ci-hyfs1-boot-ahci: test-hyfs1-boot-ahci
test-ci-hyfs1-boot-nvme: test-hyfs1-boot-nvme
test-ci-display-ahci: test-display-ahci
test-ci-display-nvme: test-display-nvme
test-ci-display-fallback: test-display-fallback
test-ci-virtio-gpu: test-virtio-gpu
test-ci-frame-pacing: test-frame-pacing
test-ci-userland-system-host: test-userland-system-host
test-ci-userland-shell-preview: test-userland-shell-preview
test-ci-userland-system-boot: test-userland-system-boot
test-ci-userland-essentials: test-userland-essentials
test-ci-userland-cat: test-userland-cat
test-ci-native-files: test-native-files
test-ci-auex-file-api: test-auex-file-api
test-ci-auex-portable-api: test-auex-portable-api
test-ci-auex-arguments: test-auex-arguments
test-ci-userland-stage1-host: test-userland-stage1-host
test-ci-userland-stage1-ahci: test-userland-stage1-ahci
test-ci-userland-stage1-nvme: test-userland-stage1-nvme
test-ci-userland-stage2: test-userland-stage2
test-ci-userland-stage3: test-userland-stage3
test-ci-userland-stage4-supervision: test-userland-stage4-supervision
test-ci-userland-stage4-concurrency: test-userland-stage4-concurrency
test-ci-userland-stage5-ipc: test-userland-stage5-ipc
test-ci-userland-info: test-userland-info
test-ci-userland-files-processes: test-userland-files-processes
test-ci-native-user-mode: test-native-user-mode
test-ci-stage6-ahci: test-stage6-ahci
test-ci-stage6-nvme: test-stage6-nvme
test-ci-hyfs1-serial-ahci: test-hyfs1-serial-ahci
test-ci-hyfs1-serial-nvme: test-hyfs1-serial-nvme
test-ci-hyfs1-storage-failure-ahci: test-hyfs1-storage-failure-ahci
test-ci-hyfs1-storage-failure-nvme: test-hyfs1-storage-failure-nvme
test-ci-hyfs2-data-ahci: test-hyfs2-data-ahci
test-ci-hyfs2-data-nvme: test-hyfs2-data-nvme
test-ci-cursor-stress: test-cursor-stress
test-ci-retained-denial: test-retained-denial

# ====================================================================
# TOOL & ENVIRONMENT CHECKS
# ====================================================================
##@ Tool & Environment Checks

config: ## Show the selected QEMU and filesystem settings
	@printf 'Australis OS configuration\n'
	@printf '  HYFS:        %s\n' '$(HYFS)'
	@printf '  GPU_DRIVER:  %s\n' '$(GPU_DRIVER)'
	@printf '  BOOT_DEVICE: %s\n' '$(BOOT_DEVICE)'
	@printf '  BOOT_CDROM:  %s\n' '$(BOOT_CDROM)'
	@printf '  USB_STORAGE: %s\n' '$(USB_STORAGE)'
	@printf '  DATA_DISK:   %s\n' '$(DATA_DISK)'
	@printf '  SERIAL:      %s\n' '$(SERIAL)'
	@printf '  ISO:         %s\n' '$(ISO)'

help: ## Show this help menu
	@printf '\n\033[1;36m  AUSTRALIS OS - Build System\033[0m\n'
	@printf '  Usage: make \033[1;32m<target>\033[0m [HYFS=1] [GPU_DRIVER=gop] [BOOT_DEVICE=nvme]\n'
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

check-hyfs-iso:
	@test -f "$(ISO)" || { echo "Missing $(ISO); run 'make iso HYFS=$(HYFS)' first."; exit 1; }

check-hyfs1-iso:
	@test -f "$(call hyfs_iso,1)" || { echo "Missing $(call hyfs_iso,1); run 'make iso-hyfs1' first."; exit 1; }

check-hyfs2-iso:
	@test -f "$(call hyfs_iso,2)" || { echo "Missing $(call hyfs_iso,2); run 'make iso' first."; exit 1; }

check-data-disk:
	@test -f "$(HYFS2_DATA_DISK)" || { echo "Missing $(HYFS2_DATA_DISK); run 'make data-disk' first."; exit 1; }
