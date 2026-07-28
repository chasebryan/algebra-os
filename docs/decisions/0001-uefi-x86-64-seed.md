# ADR 0001: Enter through an x86_64 UEFI application

- **Status:** accepted
- **Date:** 2026-07-28
- **Scope:** seed bootstrap only

## Context

Algebra needs an inspectable first transition from platform firmware into
Algebra-authored code. The project plan proposes UEFI but intentionally leaves
the route undecided. Implementing later kernel mechanisms before fixing this
boundary would make the bootstrap contract accidental.

The seed must not import a target runtime, startup object, library, or external
bootloader. Host tools are temporary construction instruments and must leave an
artifact whose relevant structure can be inspected independently.

## Decision

The first x86_64 seed is a UEFI application in PE32+ format. Removable-media
build output is placed at `EFI/BOOT/BOOTX64.EFI`.

The seed uses only the UEFI x64 image-entry contract and the system table's
Simple Text Output protocol. It emits the versioned record
`Algebra seed 0001: x86_64 uefi`, returns the firmware status from
`OutputString`, and performs no allocation, device discovery, image loading, or
exit from boot services.

The target code is direct Algebra-authored assembly. GNU `as`, `ld`, and
`objcopy` are temporary host tools. The resulting image must be an x86_64
PE32+ EFI application with:

- no import directory or unresolved symbol;
- separate code, read-only data, writable data, and relocation sections;
- a real `IMAGE_REL_BASED_DIR64` relocation, allowing firmware placement away
  from the preferred image base;
- a zero PE timestamp and byte-identical clean builds.

## Consequences

This accepts UEFI firmware and its console implementation as bootstrap
premises. It does not make them part of Algebra, and it does not decide the
post-`ExitBootServices` kernel contract.

The seed proves only that Algebra can construct an inspectable firmware image.
Runtime boot evidence remains absent until the image is exercised under a
recorded emulator/OVMF version. Deterministic serial diagnostics, the boot
information contract, memory-map handling, and the kernel transition remain
M1 work.

Legacy BIOS and third-party bootloaders are outside the initial route. Secure
Boot signing is deferred; accepting an unsigned development image is an
explicit emulator and test-machine assumption, not a production policy.

## References

- [UEFI 2.11, x64 platform calling convention](https://uefi.org/specs/UEFI/2.11/02_Overview.html#x64-platforms)
- [UEFI 2.11, EFI System Table](https://uefi.org/specs/UEFI/2.11/04_EFI_System_Table.html#efi-system-table)
- [UEFI 2.11, Simple Text Output protocol](https://uefi.org/specs/UEFI/2.11/12_Protocols_Console_Support.html#simple-text-output-protocol)
- [Microsoft PE/COFF format](https://learn.microsoft.com/en-us/windows/win32/debug/pe-format)
