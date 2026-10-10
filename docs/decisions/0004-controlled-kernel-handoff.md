# ADR 0004: End boot services and enter an embedded kernel stub

- **Status:** accepted for emulator bootstrap
- **Scope:** M1 controlled handoff

## Decision

The first kernel entry is embedded in the original Algebra EFI image. This
avoids adding an executable-file parser before the processor foundation is
established. It runs on a 16 KiB Algebra-owned stack, receives a versioned
boot-information record, emits a post-firmware diagnostic, and halts.

The loader retrieves and validates the current firmware map, then calls
`ExitBootServices` with the current map key and original image handle. A
stale-key result (`EFI_INVALID_PARAMETER`) triggers another map retrieval
and exit attempt. There are at most three exit attempts. No other firmware
services are called after the first exit attempt. Errors at that point
produce a serial failure record and halt because firmware may already have
partially shut down. Earlier map errors can still return to firmware.

On success, the loader disables maskable interrupts, clears the direction
flag, switches stacks, clears RBP, and jumps to `kernel_entry` with RDI
pointing at the boot-information record. The stack is 16-byte aligned at
the jump. There is no return address or return-to-firmware path. The kernel
checks the record's magic/version/size/exit flag and revalidates its map
before printing `Algebra kernel 0001: boot services exited`.

COM1 output is reusable assembly code and uses no firmware interfaces.
The boot test requires entry, map validation, and kernel records in that
order in two fresh boots. Other firmware text between records is permitted.

A separate CI build defines `TEST_STALE_MAP_KEY`, changing exactly the first
exit attempt's key. It must still reach the kernel in two fresh boots after
reacquiring the map. That test variant is built in `build/stale-key` and its
image and logs are retained separately; the ordinary image contains no
injected key change.

## Boot information version 1

All integers are little-endian. Pointers are 64-bit addresses in the inherited
identity-mapped firmware address space. The record and map are resident in
the loaded image and must remain reserved when frame accounting is added.

| Byte offset | Size | Field |
| ---: | ---: | --- |
| 0 | 8 | Magic: ASCII `ALGBOOT` followed by zero |
| 8 | 4 | Version: 1 |
| 12 | 4 | Record size: 80 |
| 16 | 8 | Flags: bit 0 means boot services successfully exited |
| 24 | 8 | Firmware map pointer |
| 32 | 8 | Firmware map byte size |
| 40 | 8 | Firmware descriptor stride |
| 48 | 4 | Firmware descriptor version |
| 52 | 4 | Reserved: zero |
| 56 | 8 | Diagnostic UART base port: `0x3f8` |
| 64 | 8 | Loaded image base |
| 72 | 8 | Loaded image extent, rounded to 4 KiB |

The map, boot record, code, and stack all fall inside the image extent.
The firmware map key is consumed by the loader and is not a kernel service.

## Limits

The stub still inherits firmware page tables, GDT, and IDT. It has no
Algebra-owned fault handlers, scheduler, frame allocator, or user tasks.
Disabling maskable interrupts does not prevent NMI or machine-check events.
Replacing inherited processor state is the next M2 step. Physical-machine
support and a separate kernel image format remain open decisions.

## Reference

- [UEFI 2.11: ExitBootServices and retry restrictions](https://uefi.org/specs/UEFI/2.11/07_Services_Boot_Services.html#efi-boot-services-exitbootservices)
