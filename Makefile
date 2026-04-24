BFLAT ?= $(shell command -v bflat 2>/dev/null || printf '%s' tools/bflat/bflat)
QEMU ?= qemu-system-x86_64
OVMF_CODE ?= /usr/share/OVMF/OVMF_CODE_4M.fd
LOCAL_LIB_DIR := $(CURDIR)/tools/lib
LLVM_LIB_DIR := $(CURDIR)/tools/libroot/usr/lib/llvm-18/lib
BFLAT_DIR := $(dir $(abspath $(BFLAT)))
RUN_WITH_LOCAL_LIBS := LD_LIBRARY_PATH=$(BFLAT_DIR):$(LOCAL_LIB_DIR):$(LLVM_LIB_DIR):$$LD_LIBRARY_PATH

BUILD_DIR := build
EFI_DIR := $(BUILD_DIR)/efi
EFI_BOOT_DIR := $(EFI_DIR)/EFI/BOOT
EFI_BINARY := $(EFI_BOOT_DIR)/BOOTX64.EFI
IMAGE := $(BUILD_DIR)/australis-uefi.img
KERNEL_SRC := src/boot/Program.cs

.PHONY: all build image run clean check-tools

all: build

check-tools:
	@test -x "$(BFLAT)" || { echo "bflat was not found. Install bflat or place it at tools/bflat/bflat."; exit 1; }
	@command -v mformat >/dev/null || { echo "mformat was not found."; exit 1; }
	@command -v mmd >/dev/null || { echo "mmd was not found."; exit 1; }
	@command -v mcopy >/dev/null || { echo "mcopy was not found."; exit 1; }
	@command -v "$(QEMU)" >/dev/null || { echo "$(QEMU) was not found."; exit 1; }
	@test -f "$(OVMF_CODE)" || { echo "OVMF firmware was not found at $(OVMF_CODE)."; exit 1; }

build: check-tools $(EFI_BINARY)

$(EFI_BINARY): $(KERNEL_SRC)
	@mkdir -p "$(EFI_BOOT_DIR)"
	$(RUN_WITH_LOCAL_LIBS) "$(BFLAT)" build --stdlib:zero --os:uefi --arch:x64 -o "$@" "$<"

image: build
	@mkdir -p "$(BUILD_DIR)"
	@rm -f "$(IMAGE)"
	@truncate -s 64M "$(IMAGE)"
	mformat -i "$(IMAGE)" -F ::
	mmd -i "$(IMAGE)" ::/EFI ::/EFI/BOOT
	mcopy -i "$(IMAGE)" "$(EFI_BINARY)" ::/EFI/BOOT/BOOTX64.EFI

run: build
	"$(QEMU)" \
		-machine q35 \
		-m 256M \
		-drive if=pflash,format=raw,readonly=on,file="$(OVMF_CODE)" \
		-drive format=raw,file=fat:rw:"$(EFI_DIR)" \
		-net none

clean:
	rm -rf "$(BUILD_DIR)"
