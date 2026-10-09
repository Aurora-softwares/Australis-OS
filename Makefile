HYDROGEN ?= ../Hylang-Compiler/build/self_hosting/hydrogen-stage1
QEMU ?= qemu-system-x86_64
XORRISO ?= xorriso
OVMF_CODE ?= /usr/share/OVMF/OVMF_CODE_4M.fd

BUILD_DIR := build
EFI_DIR := $(BUILD_DIR)/efi
EFI_BOOT_DIR := $(EFI_DIR)/EFI/BOOT
EFI_BINARY := $(EFI_BOOT_DIR)/BOOTX64.EFI
KERNEL_BINARY := $(EFI_DIR)/EFI/AUSTRALIS/KERNEL.BIN
SYSTEM_BINARY := $(EFI_DIR)/EFI/AUSTRALIS/SYSTEM.EFI
IMAGE := $(BUILD_DIR)/australis-hylang-uefi.img
EFI_BOOT_IMAGE := $(BUILD_DIR)/boot/efiboot.img
HYFS_IMAGE := $(BUILD_DIR)/boot/root.hyfs.img
HYFS_GPT_TYPE := 9f5eb82e-692e-5a8f-b968-adaaa349dd93
ISO_ROOT := $(BUILD_DIR)/iso-root
ISO := $(BUILD_DIR)/australis-hylang.iso
PROJECT := src/australlis.hyproj
AHCI_DISK_ARGS = -device ich9-ahci,id=ahci0 -drive if=none,id=sata0,format=raw,snapshot=on,file="$(ISO)" -device ide-hd,drive=sata0,bus=ahci0.0
NVME_DISK_ARGS = -drive if=none,id=nvme0,format=raw,readonly=on,file="$(ISO)" -device nvme,serial=australis,drive=nvme0

.PHONY: all build test-usb test-storage test-ahci test-ahci-controller test-ahci-boot test-nvme test-nvme-controller test-nvme-boot test-partitions test-vfs test-hyfs test-serial-ahci test-serial-nvme image iso run run-emu run-gop run-disk run-disk-serial run-nvme run-nvme-serial run-serial run-serial-nvme clean check-build-tools check-image-tools check-run-tools

all: build image iso

build: check-build-tools
	"$(HYDROGEN)" build "$(PROJECT)" -o "$(EFI_DIR)"

#
# TESTS
#
test-usb: check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/usb/UsbDrivers.hyproj -o "$(BUILD_DIR)/usb-tests"
	"$(BUILD_DIR)/usb-tests"

test-storage: check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/BlockDevice.hyproj -o "$(BUILD_DIR)/storage-tests"
	"$(BUILD_DIR)/storage-tests"

test-ahci: check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/Ahci.hyproj -o "$(BUILD_DIR)/ahci-tests"
	"$(BUILD_DIR)/ahci-tests"

test-ahci-controller: check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/AhciController.hyproj -o "$(BUILD_DIR)/ahci-controller-tests"
	"$(BUILD_DIR)/ahci-controller-tests"

test-nvme: check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/Nvme.hyproj -o "$(BUILD_DIR)/nvme-tests"
	"$(BUILD_DIR)/nvme-tests"

test-nvme-controller: check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/NvmeController.hyproj -o "$(BUILD_DIR)/nvme-controller-tests"
	"$(BUILD_DIR)/nvme-controller-tests"

test-nvme-boot: iso | check-run-tools
	python3 tests/storage/controller_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)"

test-ahci-boot: iso | check-run-tools
	python3 tests/storage/controller_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci

test-serial-ahci: iso | check-run-tools
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci

test-serial-nvme: iso | check-run-tools
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" nvme

test-partitions: check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/Partitions.hyproj -o "$(BUILD_DIR)/partition-tests"
	"$(BUILD_DIR)/partition-tests"

test-vfs: check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/vfs/Vfs.hyproj -o "$(BUILD_DIR)/vfs-tests"
	"$(BUILD_DIR)/vfs-tests"

test-hyfs: check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/vfs/Hyfs.hyproj -o "$(BUILD_DIR)/hyfs-tests"
	"$(BUILD_DIR)/hyfs-tests"

#
# Tools
#
$(IMAGE): build | check-image-tools
	@mkdir -p "$(BUILD_DIR)"
	@rm -f "$(IMAGE)"
	truncate -s 64M "$(IMAGE)"
	mformat -i "$(IMAGE)" -F ::
	mmd -i "$(IMAGE)" ::/EFI ::/EFI/BOOT ::/EFI/AUSTRALIS
	mcopy -i "$(IMAGE)" "$(EFI_BINARY)" ::/EFI/BOOT/BOOTX64.EFI
	mcopy -i "$(IMAGE)" "$(KERNEL_BINARY)" ::/EFI/AUSTRALIS/KERNEL.BIN
	mcopy -i "$(IMAGE)" "$(SYSTEM_BINARY)" ::/EFI/AUSTRALIS/SYSTEM.EFI

$(EFI_BOOT_IMAGE): build | check-image-tools
	@mkdir -p "$(dir $(EFI_BOOT_IMAGE))"
	@rm -f "$(EFI_BOOT_IMAGE)"
	truncate -s 8M "$(EFI_BOOT_IMAGE)"
	mformat -i "$(EFI_BOOT_IMAGE)" ::
	mmd -i "$(EFI_BOOT_IMAGE)" ::/EFI ::/EFI/BOOT ::/EFI/AUSTRALIS
	mcopy -i "$(EFI_BOOT_IMAGE)" "$(EFI_BINARY)" ::/EFI/BOOT/BOOTX64.EFI
	mcopy -i "$(EFI_BOOT_IMAGE)" "$(KERNEL_BINARY)" ::/EFI/AUSTRALIS/KERNEL.BIN
	mcopy -i "$(EFI_BOOT_IMAGE)" "$(SYSTEM_BINARY)" ::/EFI/AUSTRALIS/SYSTEM.EFI

$(HYFS_IMAGE): tools/make_hyfs_image.py $(wildcard rootfs/*)
	python3 tools/make_hyfs_image.py rootfs "$@"

$(ISO): $(EFI_BOOT_IMAGE) $(HYFS_IMAGE) | check-image-tools
	@rm -rf "$(ISO_ROOT)"
	@mkdir -p "$(ISO_ROOT)/EFI/BOOT"
	cp "$(EFI_BOOT_IMAGE)" "$(ISO_ROOT)/EFI/BOOT/efiboot.img"
	"$(XORRISO)" -as mkisofs -R -J \
		-eltorito-alt-boot -e EFI/BOOT/efiboot.img -no-emul-boot \
		-efi-boot-part --efi-boot-image \
		-append_partition 4 "$(HYFS_GPT_TYPE)" "$(HYFS_IMAGE)" -appended_part_as_gpt \
		-o "$@" "$(ISO_ROOT)"

iso: $(ISO)
image: $(IMAGE)

# Start QEMU with its graphical window and the standard VGA device. OVMF
# publishes EFI_GRAPHICS_OUTPUT_PROTOCOL for this device, which lets the
# post-handoff kernel use its direct framebuffer console.
run: iso | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(ISO)" $(AHCI_DISK_ARGS) -net none

run-serial: iso | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(ISO)" $(AHCI_DISK_ARGS) -net none -display none -monitor none -serial stdio

run-disk: iso | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" $(AHCI_DISK_ARGS) -net none

run-disk-serial: iso | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" $(AHCI_DISK_ARGS) -net none -display none -monitor none -serial stdio

run-nvme: iso | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(ISO)" $(NVME_DISK_ARGS) -net none

run-nvme-serial: iso | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(ISO)" $(NVME_DISK_ARGS) -net none -display none -monitor none -serial stdio


#
# Utilities
#
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
#
clean:
	rm -rf "$(BUILD_DIR)"
