# Algebra

[![Bootstrap seed](https://github.com/chasebryan/algebra-os/actions/workflows/bootstrap.yml/badge.svg?branch=main)](https://github.com/chasebryan/algebra-os/actions/workflows/bootstrap.yml)

**Algebra** is a from-scratch operating system for x86_64: minimal at its privileged foundation, powerful through composition, and intended to remain understandable from firmware handoff to native development environment.

> **Status:** controlled emulator handoff. The original x86_64 UEFI image
> validates its firmware memory map, exits boot services, and enters an
> embedded kernel stub on its own stack. Static checks, reproducibility,
> and QEMU/OVMF boot variants gate the bootstrap. The machine foundation
> includes owned processor/page tables, memory protection, stack guards,
> classified faults, and frame accounting. User isolation remains next. Evidence
> of security or formal verification remains future work.

Algebra is not Linux, a Linux distribution, or a fork of another operating system. It is a project by Chase Bryan.

Its architecture is conceptually informed by systems such as seL4 and LionsOS, but Algebra does not incorporate their source code, binary artifacts, or security claims.

## Purpose

The goal is a personal computer in the literal sense: a system whose foundations can be understood, changed, and rebuilt by the person who inhabits it.

Algebra seeks power through composition rather than accumulation. A small set of precise privileged mechanisms should support richer systems without placing every service inside one trusted body of code.

## Principles

- Keep the privileged foundation small and understandable.
- Represent authority explicitly through capabilities.
- Isolate address spaces, services, drivers, and failures.
- Keep policy in user space wherever the hardware permits.
- Prefer deterministic and inspectable behavior over hidden machinery.
- Treat security as a property requiring evidence, not a label.
- Build toward complete self-hosting.
- Add mechanisms only when their authority and complexity costs are understood.

“Minimal” does not mean winning a line-count contest. It means minimizing privileged state, authority paths, parsers, object types, and operations that cannot be interrupted or bounded.

## Architecture

The working direction is a capability-oriented microkernel.

The privileged kernel should provide only mechanisms that require privilege:

- processor, interrupt, and fault entry;
- address spaces and memory mappings;
- threads and scheduling mechanisms;
- kernel objects and capability enforcement;
- IPC and notifications;
- interrupt routing, timers, and fault delivery.

Resource policy, hardware discovery, drivers, filesystems, terminals, networking, and the development environment should live in isolated user-space services.

The exact capability model, IPC semantics, scheduler, object lifecycle, and allocation policy remain design decisions—not inherited assumptions.

## Language and toolchain

Algebra does not assume that an operating system must be written in C.

The initial implementation will begin close to the x86_64 machine, using assembly and small bootstrap tools. It will then develop its own assembler, linker, image builder, disassembler, and assembly-derived language.

That language should retain instruction-level control while adding mechanically checkable structure:

- explicit register and stack effects;
- typed pointers and capabilities;
- structured control flow;
- compile-time data layouts;
- declared memory and privilege effects;
- contracts and checkable invariants;
- predictable code generation with no hidden runtime.

The purpose is not to disguise the machine. It is to make machine code safer to construct and easier to reason about.

## What “from scratch” means

Every executable component distributed as part of Algebra is intended to be independently authored for Algebra. No third-party implementation will be copied or linked into its loader, kernel, services, drivers, runtime, or native tools.

Published specifications, processor manuals, standards, papers, algorithms, and test vectors may be studied. Knowledge and interface definitions are not treated as borrowed implementations.

Algebra begins at the documented handoff from platform firmware. The processor, CPU microcode, motherboard firmware, device firmware, and hardware are platform premises—not components Algebra claims to create or control.

Existing host operating systems, assemblers, linkers, emulators, and debugging tools may be used temporarily during bootstrap. They are construction instruments, not Algebra components. Their use will be documented and progressively replaced.

Self-hosting will not erase that historical bootstrap chain. It will make the chain explicit, inspectable, and no longer necessary for ordinary development.

## Direction

The first path is:

1. Reach original Algebra code reproducibly on x86_64.
2. Establish diagnostics, exception handling, and memory management.
3. Enter user mode and demonstrate address-space isolation.
4. introduce explicit capabilities and bounded IPC.
5. Start the first isolated user-space services.
6. Support a deliberately narrow physical hardware profile.
7. Add storage, persistence, and an interactive environment.
8. Replace bootstrap tools with Algebra’s own toolchain.
9. Build Algebra from within Algebra.

Detailed milestones and acceptance gates are recorded in [docs/PLAN.md](docs/PLAN.md).

## Build the bootstrap seed

With GNU binutils, POSIX `sh`, and `make` available:

```sh
make
make check
make boot-check  # additionally requires Python 3, QEMU, and OVMF
```

This creates the removable-media path
`build/esp/EFI/BOOT/BOOTX64.EFI`, audits the image boundary, and verifies that
two clean builds are byte-identical. See [docs/BOOTSTRAP.md](docs/BOOTSTRAP.md)
for the exact scope, host-tool provenance, and current verification limits.

## The name

The system is called **Algebra**. `algebra-os` is the repository name, not the product name.

*Algebra* reaches English through the Arabic *al-jabr*. The work of al-Khwarizmi also gave computing the word *algorithm*. The name connects symbolic structure, exact transformation, and the deeper intellectual history beneath computer science.
