# ADR 0005: Own descriptor tables and terminal fault diagnostics

- **Status:** accepted for the single-CPU emulator foundation
- **Scope:** first M2 processor-state and exception-entry mechanisms

## Decision

After validating boot information, the kernel installs an Algebra-owned
GDT, 104-byte x86_64 TSS, and 256-entry IDT. It reloads CS and data selectors,
loads the task register, and clears inherited FS, GS, and kernel-GS bases.
All interrupt gates are present ring-0 gates. Maskable interrupts remain
disabled; interrupt routing and scheduling have not been implemented.

The GDT contains a null descriptor, 64-bit ring-0 code, ring-0 data, and
the two-slot 64-bit TSS descriptor. The TSS supplies RSP0 and separate
16 KiB emergency stacks for double fault (IST1), NMI (IST2), and machine
check (IST3). Tables and stacks reside in the reserved loaded-image extent.
Guard pages will be added with owned page tables.

Each vector has its own assembly entry stub. The stubs normalize the
hardware error-code frame, push the vector, and save all 15 general-purpose
registers other than RSP before calling diagnostic code. The saved hardware
frame supplies original RSP, RFLAGS, and RIP. Diagnostics also report CR2;
CR2 denotes the last page-fault address and has meaning as a fault address
only for a page-fault record.

Fault handling is currently terminal. It produces vector/error/RIP/CR2,
all saved general registers, original stack/flags state, and a completion
record, then halts with maskable interrupts disabled. A breakpoint test
therefore terminates just like other deliberate kernel faults. Returning
from faults or recovering user tasks belongs to later mechanisms.

The descriptor and hexadecimal-format builders are ordinary Algebra
assembly routines. Host tests execute those same routines on host-owned
buffers and check every gate, full-width TSS bases, exact limits, emergency
stack selection, reserved fields, hexadecimal values, and buffer boundaries.

## Runtime cases

CI builds each test image separately and requires two fresh emulator boots
with all boot records plus a complete, classified fault capture. The
ordinary image contains none of the deliberate fault instructions.

| Test symbol | Trigger | Vector | Error / additional evidence |
| --- | --- | ---: | --- |
| TEST_BREAKPOINT | `int3` | 3 | Error zero |
| TEST_DIVIDE_ERROR | Division by zero | 0 | Error zero; saved RAX=1, RCX=0, RDX=0 |
| TEST_INVALID_OPCODE | `ud2` | 6 | Error zero |
| TEST_GENERAL_PROTECTION | Invalid DS selector | 13 | Error `0xfff8` |
| TEST_PAGE_FAULT | Unmapped canonical address read | 14 | Error zero; CR2 and saved RAX=`0x400000000000` |
| TEST_DOUBLE_FAULT | Invalid DS selector with RSP=0 | 8 | Error zero; original saved RSP=0 |

The double-fault case exercises the emergency stack when the interrupted
stack cannot receive a frame. NMI and machine-check stack assignment is
verified structurally, but those hardware paths are not yet runtime-tested.

## Limits and next work

Firmware page tables still supply address translation. Kernel-owned page
tables, executable/data enforcement, and physical-frame accounting remain
M2 work. No user-mode transition or preemption is claimed.

The initial GDT/TSS/IDT replacement has a short transition window and does
not claim immunity to an NMI or machine check during table replacement.
Fatal nested faults during diagnostic output are not independently
recoverable. Once the tables are active, the named emulator fault cases
are the evidence for the implemented paths.

## Reference

- [Intel 64 and IA-32 Software Developer Manuals, system programming: descriptor tables, TSS, interrupt stack table, exception frames](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html)
