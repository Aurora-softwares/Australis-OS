HYDROGEN ?= ../Hylang-Compiler/build/self_hosting/hydrogen-stage1
QEMU ?= qemu-system-x86_64
XORRISO ?= xorriso
OVMF_CODE ?= /usr/share/OVMF/OVMF_CODE_4M.fd

BUILD_DIR := build
EFI_DIR := $(BUILD_DIR)/efi
EFI_BOOT_DIR := $(EFI_DIR)/EFI/BOOT
EFI_BINARY := $(EFI_BOOT_DIR)/BOOTX64.EFI
KERNEL_BINARY := $(EFI_DIR)/EFI/AUSTRALIS/KERNEL.EFI
IMAGE := $(BUILD_DIR)/australis-hylang-uefi.img
EFI_BOOT_IMAGE := $(BUILD_DIR)/boot/efiboot.img
ISO_ROOT := $(BUILD_DIR)/iso-root
ISO := $(BUILD_DIR)/australis-hylang.iso
BOOTLOADER_SRC := src/bootloader/program.hy
KERNEL_SRC := src/kernel/program.hy

.PHONY: all build image iso run run-disk clean check-build-tools check-image-tools check-run-tools

all: build image iso

check-build-tools:
	@command -v "$(HYDROGEN)" >/dev/null 2>&1 || { \
		echo "Hydrogen compiler '$(HYDROGEN)' was not found."; \
		echo "Build hydrogen-stage1 or run: make HYDROGEN=/path/to/hydrogen-stage1"; \
		exit 1; \
	}

check-image-tools:
	@command -v mformat >/dev/null || { echo "mformat was not found."; exit 1; }
	@command -v mmd >/dev/null || { echo "mmd was not found."; exit 1; }
	@command -v mcopy >/dev/null || { echo "mcopy was not found."; exit 1; }
	@command -v "$(XORRISO)" >/dev/null || { echo "$(XORRISO) was not found."; exit 1; }

check-run-tools:
	@command -v "$(QEMU)" >/dev/null || { echo "$(QEMU) was not found."; exit 1; }
	@test -f "$(OVMF_CODE)" || { echo "OVMF firmware was not found at $(OVMF_CODE)."; exit 1; }

build: check-build-tools $(EFI_BINARY) $(KERNEL_BINARY)

$(KERNEL_BINARY): $(KERNEL_SRC) | check-build-tools
	@mkdir -p "$(dir $@)"
	"$(HYDROGEN)" compile "$<" --target uefi-x64 -o "$@"

$(EFI_BINARY): $(BOOTLOADER_SRC) $(KERNEL_BINARY) | check-build-tools
	@mkdir -p "$(EFI_BOOT_DIR)"
	"$(HYDROGEN)" compile "$<" --target uefi-x64 -o "$@"

$(IMAGE): $(EFI_BINARY) | check-image-tools
	@mkdir -p "$(BUILD_DIR)"
	@rm -f "$(IMAGE)"
	truncate -s 64M "$(IMAGE)"
	mformat -i "$(IMAGE)" -F ::
	mmd -i "$(IMAGE)" ::/EFI ::/EFI/BOOT ::/EFI/AUSTRALIS
	mcopy -i "$(IMAGE)" "$(EFI_BINARY)" ::/EFI/BOOT/BOOTX64.EFI
	mcopy -i "$(IMAGE)" "$(KERNEL_BINARY)" ::/EFI/AUSTRALIS/KERNEL.EFI

image: $(IMAGE)

$(EFI_BOOT_IMAGE): $(EFI_BINARY) | check-image-tools
	@mkdir -p "$(dir $(EFI_BOOT_IMAGE))"
	@rm -f "$(EFI_BOOT_IMAGE)"
	truncate -s 8M "$(EFI_BOOT_IMAGE)"
	mformat -i "$(EFI_BOOT_IMAGE)" ::
	mmd -i "$(EFI_BOOT_IMAGE)" ::/EFI ::/EFI/BOOT ::/EFI/AUSTRALIS
	mcopy -i "$(EFI_BOOT_IMAGE)" "$(EFI_BINARY)" ::/EFI/BOOT/BOOTX64.EFI
	mcopy -i "$(EFI_BOOT_IMAGE)" "$(KERNEL_BINARY)" ::/EFI/AUSTRALIS/KERNEL.EFI

$(ISO): $(EFI_BOOT_IMAGE) | check-image-tools
	@rm -rf "$(ISO_ROOT)"
	@mkdir -p "$(ISO_ROOT)/EFI/BOOT"
	cp "$(EFI_BOOT_IMAGE)" "$(ISO_ROOT)/EFI/BOOT/efiboot.img"
	"$(XORRISO)" -as mkisofs -R -J \
		-eltorito-alt-boot -e EFI/BOOT/efiboot.img -no-emul-boot \
		-efi-boot-part --efi-boot-image \
		-o "$@" "$(ISO_ROOT)"

iso: $(ISO)

run-emu: iso | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(ISO)" -net none

run: iso | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -drive format=raw,file="$(ISO)" -net none

clean:
	rm -rf "$(BUILD_DIR)"
