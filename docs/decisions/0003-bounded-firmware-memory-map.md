# ADR 0003: Retrieve and validate a bounded firmware memory map

- **Status:** accepted for emulator bootstrap
- **Scope:** preparing the loader's firmware handoff

## Decision

The seed calls UEFI `GetMemoryMap` after its console diagnostic, using a
64 KiB, eight-byte-aligned buffer owned by the seed's writable image section.
This deliberately fixed early capacity bounds the parsing work and avoids
introducing an allocation policy. A firmware map that needs more space
fails the bootstrap with the returned EFI status. Capacity growth remains
a later loader decision.

The seed retains the map key, byte size, descriptor stride, and descriptor
version. The validator accepts version 1, a nonempty map no larger than
64 KiB, and an eight-byte-aligned stride of at least 40 bytes. The map size
must be an exact multiple of that stride, and pointer-plus-length arithmetic
must not wrap. The firmware stride, rather than a hardcoded structure size,
advances the descriptor iteration.

Every descriptor must have a nonzero page count and page-aligned physical
and virtual starts. The last page's start must remain representable in
64 bits. This permits the final physical page at `0xfffffffffffff000` and
rejects overflowing ranges without constructing an overflowing end address.
Unknown memory types and attribute bits remain preserved for later policy.

The validator is Algebra assembly with an explicitly documented internal
register contract. Host tests assemble that same source as a host shared
object and call it through Python's ctypes. No host test object or runtime
is linked into the EFI image.

After successful validation, serial output includes
`Algebra memory map 0001: validated`. Emulator checks require both this
record and the seed entry record. A firmware error or invalid map emits
the failure record and returns an EFI error to firmware. On successful
validation the original console status remains the return value.

## Limits

This checks descriptor shape and range arithmetic. It does not check
overlapping descriptors, choose allocatable frames, establish mappings, or
exit boot services. The retrieved key may become stale through firmware
activity; a later handoff must reacquire the map and handle that race.

## Specification-derived x64 offsets

| Field | Byte offset |
| --- | ---: |
| EFI_SYSTEM_TABLE.BootServices | 96 |
| EFI_BOOT_SERVICES.GetMemoryMap | 56 |
| EFI_MEMORY_DESCRIPTOR.PhysicalStart | 8 |
| EFI_MEMORY_DESCRIPTOR.VirtualStart | 16 |
| EFI_MEMORY_DESCRIPTOR.NumberOfPages | 24 |
| EFI_MEMORY_DESCRIPTOR.Attribute | 32 |

The fifth `GetMemoryMap` argument is passed on the stack after 32 bytes
of shadow space. Nonvolatile registers are saved and restored, and the
stack is 16-byte aligned at each firmware and internal call site.

## References

- [UEFI 2.11: system and boot-services tables](https://uefi.org/specs/UEFI/2.11/04_EFI_System_Table.html)
- [UEFI 2.11: GetMemoryMap and descriptor definitions](https://uefi.org/specs/UEFI/2.11/07_Services_Boot_Services.html#efi-boot-services-getmemorymap)
