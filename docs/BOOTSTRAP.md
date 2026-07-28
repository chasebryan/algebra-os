# Bootstrap seed

The first Algebra artifact is a freestanding x86_64 UEFI application. Its job
is deliberately limited to demonstrating a controlled firmware-to-Algebra
entry and emitting one stable identity record.

The architectural choice and its limits are recorded in
[ADR 0001](decisions/0001-uefi-x86-64-seed.md).

## Host requirements

The seed currently uses these temporary host tools:

| Tool | Target-artifact role |
| --- | --- |
| GNU `as` | Assemble Algebra's x86_64 source into an ELF object |
| GNU `ld` | Resolve and lay out the freestanding ELF intermediate |
| GNU `objcopy` | Encode the selected sections as an x86_64 PE32+ image |
| GNU `objdump`, `readelf`, `nm` | Inspect format, imports, relocations, and symbols |
| POSIX `sh`, `make`, `cmp` | Orchestrate checks and compare clean builds |

No compiler runtime, C library, firmware header, startup object, host object, or
third-party target code enters the image.

## Build and inspect

Run:

```sh
make
make check
```

The removable-media tree is created at:

```text
build/esp/
└── EFI/
    └── BOOT/
        └── BOOTX64.EFI
```

`make check` rejects the image unless its PE/COFF machine, PE32+ magic, EFI
application subsystem, import directory, base-relocation directory, timestamp,
sections, and ELF symbol dependencies match the recorded contract. It then
performs two isolated clean builds and compares the resulting images byte for
byte.

The audit establishes static structure and reproducibility. It is not boot
evidence. When QEMU and OVMF are available, the next bootstrap step is to pin
their versions, record the emulator profile, boot this exact ESP tree, and
capture the `Algebra seed 0001: x86_64 uefi` record as runtime evidence.
