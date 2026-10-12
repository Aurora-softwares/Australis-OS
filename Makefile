HYDROGEN ?= ../Hylang-Compiler/build/self_hosting/hydrogen-stage1
QEMU ?= qemu-system-x86_64
XORRISO ?= xorriso
OVMF_CODE ?= /usr/share/OVMF/OVMF_CODE_4M.fd

BUILD_DIR := build
EFI_DIR := $(BUILD_DIR)/efi
EFI_BOOT_DIR := $(EFI_DIR)/EFI/BOOT
EFI_BINARY := $(EFI_BOOT_DIR)/BOOTX64.EFI
KERNEL_BINARY := $(EFI_DIR)/EFI/AUSTRALIS/KERNEL.BIN
IMAGE := $(BUILD_DIR)/australis-hylang-uefi.img
EFI_BOOT_IMAGE := $(BUILD_DIR)/boot/efiboot.img
HYFS1_IMAGE := $(BUILD_DIR)/boot/root.hyfs1.img
HYFS2_IMAGE := $(BUILD_DIR)/boot/root.hyfs2.img
GENERATED_ROOTFS := $(BUILD_DIR)/rootfs
APPLICATIONS_PROJECT ?= applications/Applications.hyproj
APPLICATIONS_DIR := $(BUILD_DIR)/applications
APPLICATIONS_STAMP := $(APPLICATIONS_DIR)/.built
APP_COMPILER := $(BUILD_DIR)/hydrogen-apps
APP_COMPILER_INPUTS := $(wildcard ../Hylang-Compiler/samples/self_hosting/*/*.hy ../Hylang-Compiler/samples/self_hosting/*/*.hyproj)
# Space separated, prebuilt .exec files from independently versioned app repos.
APPLICATION_ARTIFACTS ?=
ROOTFS_STAMP := $(GENERATED_ROOTFS)/.staged
HYFS_GPT_TYPE := 9f5eb82e-692e-5a8f-b968-adaaa349dd93
ISO_ROOT := $(BUILD_DIR)/iso-root
ISO := $(BUILD_DIR)/australis-hylang.iso
HYFS1_ISO_ROOT := $(BUILD_DIR)/iso-root-hyfs1
HYFS1_ISO := $(BUILD_DIR)/australis-hyfs1.iso
# Compatibility name used by the HyFS 2 specific tests and data-disk tools.
# The normal Australis ISO now uses HyFS 2.
HYFS2_ISO := $(ISO)
HYFS2_DATA_DISK ?= $(BUILD_DIR)/hyfs2-data.img
PROJECT := src/australlis.hyproj
AHCI_DISK_ARGS = -device ich9-ahci,id=ahci0 -drive if=none,id=sata0,format=raw,snapshot=on,file="$(ISO)" -device ide-hd,drive=sata0,bus=ahci0.0
NVME_DISK_ARGS = -drive if=none,id=nvme0,format=raw,readonly=on,file="$(ISO)" -device nvme,serial=australis,drive=nvme0
HYFS2_AHCI_DISK_ARGS = -device ich9-ahci,id=ahci0 -drive if=none,id=sata0,format=raw,snapshot=on,file="$(HYFS2_ISO)" -device ide-hd,drive=sata0,bus=ahci0.0
HYFS2_NVME_DISK_ARGS = -drive if=none,id=nvme0,format=raw,readonly=on,file="$(HYFS2_ISO)" -device nvme,serial=australis,drive=nvme0
HYFS1_AHCI_DISK_ARGS = -device ich9-ahci,id=ahci0 -drive if=none,id=sata0,format=raw,snapshot=on,file="$(HYFS1_ISO)" -device ide-hd,drive=sata0,bus=ahci0.0
HYFS1_NVME_DISK_ARGS = -drive if=none,id=nvme0,format=raw,readonly=on,file="$(HYFS1_ISO)" -device nvme,serial=australis,drive=nvme0
USB_INPUT_ARGS = -device qemu-xhci,id=xhci0 -device usb-kbd,bus=xhci0.0
USB_STORAGE_ARGS = -device qemu-xhci,id=xhci0 -drive if=none,id=usb0,format=raw,readonly=on,file="$(ISO)" -device usb-storage,drive=usb0,bus=xhci0.0

.PHONY: all build applications force-applications test-kernel-panic test-stage2 test-stage2-boot test-stage2-boot-ahci test-stage2-boot-nvme test-stage3 test-stage3-ahci test-stage3-nvme test-stage4 test-stage4-ahci test-stage4-nvme test-stage5 test-stage5-host test-auex-file-api test-auex-portable-api test-auex-arguments test-auex-arguments-image test-stage5-ahci test-stage5-nvme test-stage6 test-stage6-image test-stage6-ahci test-stage6-nvme test-usb test-storage test-ahci test-ahci-controller test-ahci-boot test-nvme test-nvme-controller test-nvme-boot test-partitions test-vfs test-hyfs test-hyfs1 test-hyfs1-boot-ahci test-hyfs1-boot-nvme test-hyfs1-serial-ahci test-hyfs1-serial-nvme test-hyfs1-storage-failure-ahci test-hyfs1-storage-failure-nvme test-hyfs2 test-hyfs2-writes test-hyfs2-boot-ahci test-hyfs2-boot-nvme test-hyfs2-serial-ahci test-hyfs2-serial-nvme test-hyfs2-data-ahci test-hyfs2-data-nvme test-terminal test-serial-ahci test-serial-nvme test-storage-failure-ahci test-storage-failure-nvme image iso iso-hyfs1 iso-hyfs2 hyfs2-data-disk run run-emu run-gop run-disk run-disk-serial run-nvme run-nvme-serial run-disk-hyfs1 run-disk-hyfs2 run-hyfs1 run-hyfs1-serial run-hyfs1-nvme run-hyfs1-nvme-serial run-hyfs2-serial run-hyfs2-nvme-serial run-usb-storage run-usb-storage-nvme clean check-build-tools check-image-tools check-run-tools

all: build image iso

build: check-build-tools
	"$(HYDROGEN)" build "$(PROJECT)" -o "$(EFI_DIR)"

#
# TESTS
#
test-stage2: check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/kernel/Stage2.hyproj -o "$(BUILD_DIR)/stage2-tests"
	"$(BUILD_DIR)/stage2-tests"

test-kernel-panic: iso | check-run-tools
	python3 tests/kernel/panic_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)"

test-stage2-boot: test-stage2-boot-ahci test-stage2-boot-nvme

test-stage2-boot-ahci: iso | check-run-tools
	python3 tests/kernel/stage2_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci

test-stage2-boot-nvme: iso | check-run-tools
	python3 tests/kernel/stage2_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" nvme

test-stage3: test-stage3-ahci test-stage3-nvme

test-stage3-ahci: iso | check-run-tools
	python3 tests/usb/xhci_keyboard_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci

test-stage3-nvme: iso | check-run-tools
	python3 tests/usb/xhci_keyboard_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" nvme

test-stage4: test-stage4-ahci test-stage4-nvme

test-stage4-ahci: iso | check-run-tools
	python3 tests/usb/xhci_storage_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci

test-stage4-nvme: iso | check-run-tools
	python3 tests/usb/xhci_storage_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" nvme

test-stage5: test-stage5-host test-stage5-ahci test-stage5-nvme

test-stage5-host: check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/user/UserRuntime.hyproj -o "$(BUILD_DIR)/user-runtime-tests"
	"$(BUILD_DIR)/user-runtime-tests"

test-auex-file-api: $(APP_COMPILER)
	@mkdir -p "$(BUILD_DIR)"
	"$(APP_COMPILER)" build applications/Australis-Inspector/Inspector.hyproj -o "$(BUILD_DIR)/inspector-file-api.exec"
	"$(APP_COMPILER)" build tests/user/FileApiApp.hyproj -o "$(BUILD_DIR)/file-api-test.exec"
	"$(HYDROGEN)" build tests/user/UserRuntime.hyproj -o "$(BUILD_DIR)/user-runtime-tests"
	"$(BUILD_DIR)/user-runtime-tests" inspector "$(BUILD_DIR)/inspector-file-api.exec"
	"$(BUILD_DIR)/user-runtime-tests" file-api "$(BUILD_DIR)/file-api-test.exec"

test-auex-portable-api: $(APP_COMPILER)
	@mkdir -p "$(BUILD_DIR)"
	"$(APP_COMPILER)" build applications/Australis.Dev-user-demo/UserDemo.hyproj -o "$(BUILD_DIR)/portable-api-test.exec"
	"$(APP_COMPILER)" build tests/user/PortableApiApp.hyproj -o "$(BUILD_DIR)/portable-io-test.exec"
	"$(HYDROGEN)" build tests/user/UserRuntime.hyproj -o "$(BUILD_DIR)/user-runtime-tests"
	"$(BUILD_DIR)/user-runtime-tests" portable-api "$(BUILD_DIR)/portable-api-test.exec"
	"$(BUILD_DIR)/user-runtime-tests" portable-io "$(BUILD_DIR)/portable-io-test.exec"

test-stage5-ahci: iso | check-run-tools
	python3 tests/user/user_program_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci

test-stage5-nvme: iso | check-run-tools
	python3 tests/user/user_program_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" nvme

test-stage6: test-hyfs2 test-stage6-ahci test-stage6-nvme

test-auex-arguments: test-auex-arguments-image
	python3 tests/user/argument_program_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci
	python3 tests/user/argument_program_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

test-auex-arguments-image: $(APP_COMPILER) | check-run-tools
	"$(APP_COMPILER)" build tests/user/ArgumentApp.hyproj -o "$(BUILD_DIR)/argv-check.exec"
	"$(MAKE)" iso-hyfs2 APPLICATION_ARTIFACTS="$(BUILD_DIR)/argv-check.exec"

test-stage6-image: $(APP_COMPILER) | check-run-tools
	"$(APP_COMPILER)" build tests/user/PersistentFileApp.hyproj -o "$(BUILD_DIR)/stage6-file-test.exec"
	"$(MAKE)" iso-hyfs2 APPLICATION_ARTIFACTS="$(BUILD_DIR)/stage6-file-test.exec"

test-stage6-ahci: test-stage6-image
	python3 tests/storage/hyfs2_persistent_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" ahci

test-stage6-nvme: test-stage6-image
	python3 tests/storage/hyfs2_persistent_boot.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS2_ISO)" nvme

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
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" ahci hyfs2

test-terminal: check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/console/Terminal.hyproj -o "$(BUILD_DIR)/terminal-tests"
	"$(BUILD_DIR)/terminal-tests"

test-serial-nvme: iso | check-run-tools
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(ISO)" nvme hyfs2

test-storage-failure-ahci: test-hyfs2-data-ahci

test-storage-failure-nvme: test-hyfs2-data-nvme

test-hyfs1-storage-failure-ahci: iso-hyfs1 | check-run-tools
	python3 tests/console/storage_failure_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS1_ISO)" ahci

test-hyfs1-storage-failure-nvme: iso-hyfs1 | check-run-tools
	python3 tests/console/storage_failure_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS1_ISO)" nvme

test-partitions: check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/storage/Partitions.hyproj -o "$(BUILD_DIR)/partition-tests"
	"$(BUILD_DIR)/partition-tests"

test-vfs: check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build tests/vfs/Vfs.hyproj -o "$(BUILD_DIR)/vfs-tests"
	"$(BUILD_DIR)/vfs-tests"

$(BUILD_DIR)/host-vfs/Hyfs.hy: src/kernel/vfs/Hyfs.hy tests/vfs/build_host_hyfs.py
	python3 tests/vfs/build_host_hyfs.py "$<" "$@"

test-hyfs1: $(BUILD_DIR)/host-vfs/Hyfs.hy | check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	python3 tests/vfs/hyfs_v1_fixture.py
	"$(HYDROGEN)" build tests/vfs/Hyfs.hyproj -o "$(BUILD_DIR)/hyfs-tests"
	"$(BUILD_DIR)/hyfs-tests"

test-hyfs: test-hyfs2

test-hyfs1-boot-ahci: iso-hyfs1 | check-run-tools
	python3 tests/storage/controller_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS1_ISO)" ahci

test-hyfs1-boot-nvme: iso-hyfs1 | check-run-tools
	python3 tests/storage/controller_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS1_ISO)"

test-hyfs1-serial-ahci: iso-hyfs1 | check-run-tools
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS1_ISO)" ahci

test-hyfs1-serial-nvme: iso-hyfs1 | check-run-tools
	python3 tests/console/serial_boot_smoke.py "$(QEMU)" "$(OVMF_CODE)" "$(HYFS1_ISO)" nvme

test-hyfs2: $(BUILD_DIR)/host-vfs/Hyfs.hy | check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	python3 tests/vfs/hyfs2_image_test.py
	python3 tests/vfs/hyfs_v1_fixture.py --output "$(BUILD_DIR)/hyfs-v1-compat.img"
	python3 tests/vfs/make_hyfs2_fixture.py "$(BUILD_DIR)/hyfs2-host.img"
	"$(HYDROGEN)" build tests/vfs/Hyfs2.hyproj -o "$(BUILD_DIR)/hyfs2-tests"
	"$(BUILD_DIR)/hyfs2-tests"
	"$(HYDROGEN)" build tests/vfs/Hyfs2Writer.hyproj -o "$(BUILD_DIR)/hyfs2-writer-tests"
	"$(BUILD_DIR)/hyfs2-writer-tests"

test-hyfs2-writes: test-hyfs2

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

$(EFI_BOOT_IMAGE): build | check-image-tools
	@mkdir -p "$(dir $(EFI_BOOT_IMAGE))"
	@rm -f "$(EFI_BOOT_IMAGE)"
	truncate -s 8M "$(EFI_BOOT_IMAGE)"
	mformat -i "$(EFI_BOOT_IMAGE)" ::
	mmd -i "$(EFI_BOOT_IMAGE)" ::/EFI ::/EFI/BOOT ::/EFI/AUSTRALIS
	mcopy -i "$(EFI_BOOT_IMAGE)" "$(EFI_BINARY)" ::/EFI/BOOT/BOOTX64.EFI
	mcopy -i "$(EFI_BOOT_IMAGE)" "$(KERNEL_BINARY)" ::/EFI/AUSTRALIS/KERNEL.BIN

force-applications:

applications: $(APPLICATIONS_STAMP)

$(APP_COMPILER): $(APP_COMPILER_INPUTS) | check-build-tools
	@mkdir -p "$(BUILD_DIR)"
	"$(HYDROGEN)" build ../Hylang-Compiler/samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj -o "$(APP_COMPILER)"
	@chmod +x "$(APP_COMPILER)"

$(APPLICATIONS_STAMP): force-applications $(APPLICATIONS_PROJECT) $(APP_COMPILER) | check-build-tools
	@rm -rf "$(APPLICATIONS_DIR)"
	@mkdir -p "$(APPLICATIONS_DIR)"
	"$(APP_COMPILER)" build "$(APPLICATIONS_PROJECT)" -o "$(APPLICATIONS_DIR)"
	@touch "$@"

$(ROOTFS_STAMP): $(APPLICATIONS_STAMP) $(wildcard rootfs/*) $(APPLICATION_ARTIFACTS)
	@rm -rf "$(GENERATED_ROOTFS)"
	@mkdir -p "$(GENERATED_ROOTFS)"
	@cp rootfs/* "$(GENERATED_ROOTFS)/"
	@cp "$(APPLICATIONS_DIR)"/*.exec "$(GENERATED_ROOTFS)/"
	@for artifact in $(APPLICATION_ARTIFACTS); do \
		name=$$(basename "$$artifact"); \
		test ! -e "$(GENERATED_ROOTFS)/$$name" || { echo "duplicate root executable: $$name"; exit 1; }; \
		cp "$$artifact" "$(GENERATED_ROOTFS)/$$name"; \
	done
	@touch "$@"

$(HYFS1_IMAGE): tools/make_hyfs_image.py $(ROOTFS_STAMP)
	python3 tools/make_hyfs_image.py "$(GENERATED_ROOTFS)" "$@"

$(HYFS2_IMAGE): tools/hyfs2.py tools/make_hyfs2_image.py $(ROOTFS_STAMP)
	python3 tools/make_hyfs2_image.py "$(GENERATED_ROOTFS)" "$@" --system-apps "$(APPLICATIONS_DIR)/system"

iso-hyfs1: $(HYFS1_ISO)

# Kept as an explicit alias for existing scripts. HyFS 2 is the default image.
iso-hyfs2: iso

hyfs2-data-disk: $(HYFS2_DATA_DISK)

# Order-only ISO prerequisite: never overwrite a data disk after first creation.
$(HYFS2_DATA_DISK): | $(HYFS2_ISO)
	python3 tools/make_hyfs2_data_disk.py "$(HYFS2_ISO)" "$@"

$(ISO): Makefile $(EFI_BOOT_IMAGE) $(HYFS2_IMAGE) | check-image-tools
	@rm -rf "$(ISO_ROOT)"
	@mkdir -p "$(ISO_ROOT)/EFI/BOOT"
	cp "$(EFI_BOOT_IMAGE)" "$(ISO_ROOT)/EFI/BOOT/efiboot.img"
	"$(XORRISO)" -as mkisofs -R -J \
		-eltorito-alt-boot -e EFI/BOOT/efiboot.img -no-emul-boot \
		-efi-boot-part --efi-boot-image \
		-append_partition 4 "$(HYFS_GPT_TYPE)" "$(HYFS2_IMAGE)" -appended_part_as_gpt \
		-o "$@" "$(ISO_ROOT)"

$(HYFS1_ISO): Makefile $(EFI_BOOT_IMAGE) $(HYFS1_IMAGE) | check-image-tools
	@rm -rf "$(HYFS1_ISO_ROOT)"
	@mkdir -p "$(HYFS1_ISO_ROOT)/EFI/BOOT"
	cp "$(EFI_BOOT_IMAGE)" "$(HYFS1_ISO_ROOT)/EFI/BOOT/efiboot.img"
	"$(XORRISO)" -as mkisofs -R -J \
		-eltorito-alt-boot -e EFI/BOOT/efiboot.img -no-emul-boot \
		-efi-boot-part --efi-boot-image \
		-append_partition 4 "$(HYFS_GPT_TYPE)" "$(HYFS1_IMAGE)" -appended_part_as_gpt \
		-o "$@" "$(HYFS1_ISO_ROOT)"

iso: $(ISO)
image: $(IMAGE)

# Start QEMU with its graphical window and the standard VGA device. OVMF
# publishes EFI_GRAPHICS_OUTPUT_PROTOCOL for this device, which lets the
# post-handoff kernel use its direct framebuffer console.
run: iso | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(ISO)" $(AHCI_DISK_ARGS) $(USB_INPUT_ARGS) -net none

# Show the scrolling framebuffer while accepting shell input through COM1 on
# the launching terminal. The USB keyboard and COM1 share the shell input path.
run-gop: iso | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(ISO)" $(AHCI_DISK_ARGS) $(USB_INPUT_ARGS) -net none -monitor none -serial stdio

run-serial: iso | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(ISO)" $(AHCI_DISK_ARGS) -net none -display none -monitor none -serial stdio

run-disk: iso | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" $(AHCI_DISK_ARGS) $(USB_INPUT_ARGS) -net none

run-disk-serial: iso | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" $(AHCI_DISK_ARGS) -net none -display none -monitor none -serial stdio

run-nvme: iso | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(ISO)" $(NVME_DISK_ARGS) $(USB_INPUT_ARGS) -net none

run-nvme-serial: iso | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(ISO)" $(NVME_DISK_ARGS) -net none -display none -monitor none -serial stdio

run-serial-nvme: run-nvme-serial

run-hyfs1: iso-hyfs1 | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS1_ISO)" $(HYFS1_AHCI_DISK_ARGS) $(USB_INPUT_ARGS) -net none

run-disk-hyfs1: iso-hyfs1 | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" $(HYFS1_AHCI_DISK_ARGS) $(USB_INPUT_ARGS) -net none

run-hyfs1-serial: iso-hyfs1 | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS1_ISO)" $(HYFS1_AHCI_DISK_ARGS) -net none -display none -monitor none -serial stdio

run-hyfs1-nvme: iso-hyfs1 | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS1_ISO)" $(HYFS1_NVME_DISK_ARGS) $(USB_INPUT_ARGS) -net none

run-hyfs1-nvme-serial: iso-hyfs1 | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS1_ISO)" $(HYFS1_NVME_DISK_ARGS) -net none -display none -monitor none -serial stdio


run-disk-hyfs2: iso-hyfs2 | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" $(AHCI_DISK_ARGS) $(USB_INPUT_ARGS) -net none

run-hyfs2-serial: iso-hyfs2 | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS2_ISO)" $(HYFS2_AHCI_DISK_ARGS) -net none -display none -monitor none -serial stdio

run-hyfs2-nvme-serial: iso-hyfs2 | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS2_ISO)" $(HYFS2_NVME_DISK_ARGS) -net none -display none -monitor none -serial stdio

run-hyfs2-data-ahci: hyfs2-data-disk | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS2_ISO)" -device ich9-ahci,id=ahci0 -drive if=none,id=data0,format=raw,file="$(HYFS2_DATA_DISK)" -device ide-hd,drive=data0,bus=ahci0.0 -net none -display none -monitor none -serial stdio

run-hyfs2-data-nvme: hyfs2-data-disk | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(HYFS2_ISO)" -drive if=none,id=data0,format=raw,file="$(HYFS2_DATA_DISK)" -device nvme,serial=australis-data,drive=data0 -net none -display none -monitor none -serial stdio

# The live controller currently owns one root-port device. Use COM1 for input
# while the xHCI device is occupied by the removable mass-storage volume.
run-usb-storage: iso | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(ISO)" $(AHCI_DISK_ARGS) $(USB_STORAGE_ARGS) -net none -display none -monitor none -serial stdio

run-usb-storage-nvme: iso | check-run-tools
	"$(QEMU)" -machine q35 -m 256M -drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" -cdrom "$(ISO)" $(NVME_DISK_ARGS) $(USB_STORAGE_ARGS) -net none -display none -monitor none -serial stdio


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
