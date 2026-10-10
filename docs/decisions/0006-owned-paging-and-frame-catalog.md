# ADR 0006: Own page tables and account for physical frames

- **Status:** accepted for the emulator bootstrap
- **Scope:** remaining M2 memory mechanisms

## Address translation and permissions

The kernel replaces firmware CR3 with Algebra-built four-level tables using
4 KiB pages. The initial image must be page aligned, nonzero, no larger
than 1 MiB, and wholly below 4 GiB. A linker assertion enforces the size
bound. These are explicit limits of the first bootstrap profile, not a
general physical-machine loader contract.

Eight image-resident pages hold one PML4, one PDPT, four page directories,
and two page tables. An image of at most 1 MiB can span at most two 2 MiB
regions, including a 1 GiB boundary. Tables map only the image's pages;
other leaf entries remain absent. Host tests independently walk all image
pages and check layouts crossing 1 GiB and ending exactly at 4 GiB.

| Image region | Writable | Executable | User accessible |
| --- | --- | --- | --- |
| Code | No | Yes | No |
| Writable data, tables, and stacks | Yes | No | No |
| Headers, read-only data, and relocations | No | No | No |
| Four stack guard pages | Unmapped | Unmapped | No |

The builder rejects overlapping code/data boundaries, unaligned ranges,
duplicate guards, guards outside data, guards inside the paging structures,
and aliased configuration/output storage before writing tables. It preserves
the internal callee-saved register contract and uses no host runtime.

The installer requires processor execute-disable support and four-level
paging. It enables EFER.NXE and CR0.WP, clears CR4.PGE and PCIDE to remove
firmware global/PCID translations, and loads the new CR3. The current
instruction stream, active stack, descriptor tables, map, and diagnostics
are all within the new mappings. UART diagnostics use port I/O.

## Physical-frame catalog

The kernel builds a bounded catalog from the firmware map after switching
to owned translation. The same target assembly revalidates descriptor
shape/ranges, normalizes addresses to physical frame numbers (PFNs), sorts
the records, and rejects overlaps and duplicate regions.

PFNs avoid an overflowing byte end address for the last representable
physical page. The catalog retains type and attributes for every described
region. Only EfiBootServicesCode, EfiBootServicesData, and EfiConventionalMemory
without the runtime attribute are candidates for reuse. Loader memory,
runtime memory, ACPI, device mappings, unaccepted memory, unknown types, and
other reserved categories remain excluded.

The loaded image extent is removed from every candidate range. A crossing
range is split into left/right free extents; wholly reserved ranges yield
none. This protects the kernel, raw map, catalog, tables, and stacks even
if a map describes those pages with a reusable type. The kernel requires
a nonempty inventory under the declared reference profile.

The catalog is fixed at 81920 bytes. At most 1638 raw descriptors can fit
the 64 KiB map bound with the minimum 40-byte stride. Sorting uses bounded
insertion sort, at most 1638 records. Removing one contiguous image range
from nonoverlapping records can add at most one free extent, so capacity
for 1639 free extents is sufficient.

| Offset | Size | Catalog content |
| ---: | ---: | --- |
| 0 | 8 | Magic `ALGFRM1` followed by zero, published after successful construction |
| 8 | 4 | Version 1 |
| 12 | 4 | Total storage size: 81920 |
| 16 | 8 | Raw descriptor count |
| 24 | 8 | Free extent count |
| 32 | 8 | Free frame count |
| 40 | 8 | Total described frame count |
| 48 | 8 | Reserved image first PFN |
| 56 | 8 | Reserved image end PFN, exclusive |
| 64 | 1638 × 32 | Sorted records: first PFN, pages, type, attributes |
| 52480 | 1639 × 16 | Free extents: first PFN, pages |

The caller checks the constructor status before using the catalog. Valid
caller-owned buffers must not alias the configuration or raw map. This
helper is not a system-call interface for arbitrary user pointers.

## Evidence and next mechanisms

Ordinary emulator boots must reach the owned-paging and nonempty-inventory
records. Evidence retains free extent/frame counts. Four additional test
images must fault on a code write, read-only-data write, data execution,
and guard read. They require page-fault vector 14, precise error codes,
and CR2 matching the saved attempted address.

Host tests execute the actual target builders. Frame tests include shuffled
inputs, forbidden types, runtime attributes, overlapping/duplicate ranges,
image reservation across several ranges, the last physical page, the maximum
descriptor count and split, and deterministic comparisons against a separate
page-set reference model. No validation shared object enters the EFI image.

Accounting does not allocate or reassign frames yet. Allocator policy,
clearing frames on reassignment, user page tables, and mapping authorization
will be introduced with user isolation and capabilities. SMP, user tasks,
preemption, broad hardware support, and security assurance remain later work.

## Reference

- [Intel 64 and IA-32 Software Developer Manuals: paging, execute disable, write protection, and translation invalidation](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html)
- [UEFI 2.11: memory descriptors and ExitBootServices](https://uefi.org/specs/UEFI/2.11/07_Services_Boot_Services.html)
