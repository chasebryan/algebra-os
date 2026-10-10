AS ?= as
ASFLAGS ?=
LD ?= ld
OBJCOPY ?= objcopy
OBJDUMP ?= objdump
READELF ?= readelf
NM ?= nm
PYTHON ?= python3
QEMU ?= qemu-system-x86_64
OVMF_CODE ?= /usr/share/OVMF/OVMF_CODE_4M.fd
OVMF_VARS ?= /usr/share/OVMF/OVMF_VARS_4M.fd

BUILD_DIR ?= build
SEED_DIR := $(BUILD_DIR)/seed
ESP_DIR := $(BUILD_DIR)/esp
SEED_OBJECT := $(SEED_DIR)/seed.o
MAP_OBJECT := $(SEED_DIR)/memory-map.o
SERIAL_OBJECT := $(SEED_DIR)/serial.o
KERNEL_OBJECT := $(SEED_DIR)/kernel-entry.o
SEED_ELF := $(SEED_DIR)/seed.elf
SEED_EFI := $(ESP_DIR)/EFI/BOOT/BOOTX64.EFI

.DEFAULT_GOAL := all

.PHONY: all audit check reproducible boot-check

all: $(SEED_EFI)

$(SEED_DIR) $(ESP_DIR)/EFI/BOOT:
	mkdir -p $@

$(SEED_OBJECT): boot/x86_64/uefi/seed.S | $(SEED_DIR)
	$(AS) --64 --fatal-warnings $(ASFLAGS) -o $@ $<

$(MAP_OBJECT): boot/x86_64/uefi/memory-map.S | $(SEED_DIR)
	$(AS) --64 --fatal-warnings $(ASFLAGS) -o $@ $<

$(SERIAL_OBJECT): boot/x86_64/uefi/serial.S | $(SEED_DIR)
	$(AS) --64 --fatal-warnings $(ASFLAGS) -o $@ $<

$(KERNEL_OBJECT): boot/x86_64/uefi/kernel-entry.S | $(SEED_DIR)
	$(AS) --64 --fatal-warnings $(ASFLAGS) -o $@ $<

$(SEED_ELF): $(SEED_OBJECT) $(MAP_OBJECT) $(SERIAL_OBJECT) $(KERNEL_OBJECT) boot/x86_64/uefi/seed.ld
	$(LD) -nostdlib --fatal-warnings --build-id=none \
		-T boot/x86_64/uefi/seed.ld -o $@ $(SEED_OBJECT) $(MAP_OBJECT) $(SERIAL_OBJECT) $(KERNEL_OBJECT)

$(SEED_EFI): $(SEED_ELF) | $(ESP_DIR)/EFI/BOOT
	SOURCE_DATE_EPOCH=0 $(OBJCOPY) \
		--only-section=.text \
		--only-section=.rdata \
		--only-section=.data \
		--only-section=.reloc \
		--output-target=pei-x86-64 \
		--subsystem=10 \
		--image-base=0 \
		--section-alignment=4096 \
		--file-alignment=512 \
		$< $@

audit: $(SEED_EFI)
	OBJDUMP=$(OBJDUMP) READELF=$(READELF) NM=$(NM) \
		sh tools/audit-seed.sh $(SEED_ELF) $(SEED_EFI)

reproducible:
	@set -eu; \
	temp_root=$$(mktemp -d "$${TMPDIR:-/tmp}/algebra-repro.XXXXXX"); \
	trap 'rm -rf -- "$$temp_root"' EXIT HUP INT TERM; \
	$(MAKE) --no-print-directory BUILD_DIR="$$temp_root/first" all; \
	$(MAKE) --no-print-directory BUILD_DIR="$$temp_root/second" all; \
	cmp "$$temp_root/first/esp/EFI/BOOT/BOOTX64.EFI" \
		"$$temp_root/second/esp/EFI/BOOT/BOOTX64.EFI"; \
	printf '%s\n' 'reproducibility: identical clean-build images'

check: audit reproducible

boot-check: audit
	$(PYTHON) tools/boot-check.py --esp "$(ESP_DIR)" \
		--evidence "$(BUILD_DIR)/boot-evidence" --qemu "$(QEMU)" \
		--code "$(OVMF_CODE)" --vars "$(OVMF_VARS)"
