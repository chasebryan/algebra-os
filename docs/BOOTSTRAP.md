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
| Python 3, QEMU, OVMF | Run the emulator test and capture runtime evidence |

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

The audit establishes static structure and reproducibility. Runtime evidence
is collected separately:

```sh
make boot-check
```

This requires `qemu-system-x86_64`, Python 3, and matching OVMF 4 MiB code
and variable files. Defaults are `/usr/share/OVMF/OVMF_CODE_4M.fd` and
`/usr/share/OVMF/OVMF_VARS_4M.fd`; override `OVMF_CODE`, `OVMF_VARS`, and
`QEMU` when necessary. The emulator must support `pc-q35-8.2`.

Two fresh boots must each emit `Algebra serial 0001: uefi entry` and
`Algebra memory map 0001: validated` over COM1 within 30 seconds.
They must then emit `Algebra kernel 0001: boot services exited` after
successful firmware termination and entry on the Algebra-owned stack.
Descriptor-table installation emits `Algebra machine 0001: descriptor tables installed`.
It is followed by `Algebra memory 0001: own page tables active` and
`Algebra frames 0001: inventory ready`, with measured free extent/frame counts.
The firmware map is retrieved into a bounded buffer and its descriptor
shape and address arithmetic are checked by the target assembly validator.
See [ADR 0003](decisions/0003-bounded-firmware-memory-map.md).
Logs and measured inputs are retained under
`build/boot-evidence/run-*/`, including failures. The source ESP and firmware
variable template are copied before starting the guest. See
[ADR 0002](decisions/0002-emulator-serial-evidence.md) for the complete
profile, bounded UART behavior, and precise limits of this evidence.
The boot-information contract and firmware-exit behavior are in
[ADR 0004](decisions/0004-controlled-kernel-handoff.md).

The GitHub workflow runs both checks and publishes the image and boot logs.
It additionally runs six deliberate processor-fault variants, requiring
two boots and full register diagnostics for each. `BOOT_CHECK_FLAGS` accepts
`--expect-fault`, `--expect-error`, `--expect-cr2`, and repeatable
`--expect-register NAME=VALUE` expectations. For example:

```sh
make BUILD_DIR=build/fault-breakpoint ASFLAGS=--defsym=TEST_BREAKPOINT=1 \
  BOOT_CHECK_FLAGS='--expect-fault 3 --expect-error 0' boot-check
```

The exact cases, table layout, emergency stacks, and limitations are recorded
in [ADR 0005](decisions/0005-processor-tables-and-faults.md).
Four further variants exercise code and read-only-data writes, data execution,
and a stack-guard read. Their page-fault error codes and attempted addresses
must match the expected protection. `--expect-cr2-register NAME` checks CR2
against a saved register when the image's load address varies. Paging and
frame-catalog contracts are recorded in
[ADR 0006](decisions/0006-owned-paging-and-frame-catalog.md).
An individual passing run establishes evidence for the recorded inputs;
changing firmware, emulator versions, or source requires a new run.
