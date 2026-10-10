# Algebra Project Plan

> **Status:** architecture direction; controlled emulator handoff implemented
> **Target:** x86_64  
> **System name:** Algebra  
> **Repository:** `algebra-os`

This document records the current direction of Algebra. It is a working charter, not an implemented architecture, stable ABI, release promise, or security claim.

## Current implementation evidence

The M1 emulator gate is implemented: an original UEFI image retrieves and
validates the firmware map, exits boot services with bounded stale-key
retries, and enters an embedded kernel stub on its own stack with boot
information version 1. Two fresh emulator boots must produce all three
serial records in order. A separate test image deliberately supplies a
stale first map key and must also reach the kernel in two fresh boots.

`make check` verifies static image structure and byte-identical clean
builds. `make boot-check` captures the emulator profile, firmware/image
hashes, serial logs, and per-boot result. CI also runs the host regression
tests, which execute the target memory-map validator on boundary cases.
See [BOOTSTRAP.md](BOOTSTRAP.md) and ADRs 0002–0004 for exact evidence limits.

M2 mechanisms are implemented under the emulator profile: owned GDT/TSS/IDT,
four-level page tables, supervisor write protection, executable/data
separation, stack guards, and a sorted physical-frame catalog that excludes
the resident image. Deliberate exceptions, double-fault stack recovery, and
four memory-protection faults gate the tested paths. See ADRs 0005–0006
for the bounded image layout, evidence, and limitations. Allocation,
user-mode entry, distinct user address spaces, and preemption are next.

## 1. Charter

Algebra is a personal, from-scratch operating system for x86_64.

Its objective is to build the smallest understandable privileged substrate capable of supporting a complete and powerful computing environment through isolated, explicitly authorized components.

Algebra is intended to be:

- wholly original at the target-software layer;
- capability-oriented;
- component-based;
- assembly-first;
- developed toward its own structured and typed assembly language;
- minimal at the privileged boundary;
- auditable and deterministic where the hardware permits;
- eventually self-hosting.

Algebra may study the published ideas behind seL4, LionsOS, and other systems. It will not inherit their implementations, APIs, proofs, or assurance claims.

## 2. Boundaries

“From scratch” requires an explicit boundary.

| Layer | Algebra’s position |
| --- | --- |
| CPU, microcode, hardware, and device firmware | Platform premises outside Algebra’s authorship and control |
| Firmware before software handoff | Initial trust assumption and boot environment |
| Algebra loader, kernel, services, drivers, runtime, and tools | Independently implemented for Algebra |
| Published specifications and manuals | Permitted sources of interface knowledge |
| Host OS, emulator, assembler, linker, and debugger | Temporary bootstrap and validation instruments |
| Third-party target code and libraries | Not incorporated or distributed as part of Algebra |

The project will not import another kernel, bootloader, runtime, driver, protocol implementation, target library, or copied source fragment.

Temporary host tools must not silently introduce startup objects, runtime helpers, libraries, or foreign target code. Bootstrap artifacts will eventually require provenance records and binary inspection.

A host development distribution is disposable infrastructure. Its identity is not an architectural property of Algebra.

## 3. Proposed system architecture

The working architectural hypothesis is a small, capability-oriented microkernel surrounded by isolated user-space components.

It remains a hypothesis until its interfaces, invariants, and failure behavior are specified and tested.

### Privileged mechanisms

The kernel is expected to own only mechanisms that cannot safely be delegated:

- processor entry, exceptions, and privilege transitions;
- address-space and page-mapping enforcement;
- execution contexts and scheduling mechanisms;
- capability validation and kernel-object lifecycle;
- bounded IPC and notification primitives;
- interrupt routing, timers, and fault delivery.

The provisional object vocabulary may include threads, address spaces, frames, capability tables, endpoints, notifications, and interrupt authority. The final object model remains open.

### User-space responsibilities

The following should remain outside the kernel wherever practical:

- initial-system construction;
- memory and resource-allocation policy;
- PCI and device discovery;
- device drivers;
- storage and filesystems;
- executable and program-loading policy;
- terminals, input, and display;
- networking;
- shell, editor, debugger, and build tools.

Moving code into user space does not make it safe automatically. Until an IOMMU is configured, a DMA-capable driver and its device remain part of the effective trusted base.

### Initial boot route

The accepted initial route begins with an original x86_64 UEFI application,
first tested under emulation and later on one explicitly selected physical
machine. [ADR 0001](decisions/0001-uefi-x86-64-seed.md) fixes only the
firmware-to-seed boundary; evolving the seed into the system loader remains M1
work.

The proposed transition is:

`platform firmware → Algebra loader → exit firmware boot services → Algebra kernel → initial user task`

The loader would implement only the required firmware and image formats from their published specifications. It would not use an external bootloader or target runtime.

UEFI-first is accepted for the bootstrap seed. The precise firmware subset
beyond image entry and console output remains to be decided. Legacy BIOS
support is not an initial requirement.

## 4. Security program

Algebra is security-oriented, but it is not presently described as secure.

A small kernel and capability system can reduce authority and audit surface. Neither establishes security without a threat model, correct implementation, and supporting evidence.

### Initial adversary

The initial design should account for:

- malformed or hostile user tasks;
- compromised user-space services or drivers;
- malformed system calls and IPC;
- capability forgery and rights-amplification attempts;
- invalid system-image and filesystem data;
- hostile input arriving through supported devices;
- faults and infinite loops in untrusted tasks.

### Initial exclusions

The first threat model will not claim protection against:

- malicious CPU microcode, SMM, or platform firmware;
- malicious device firmware;
- invasive physical attacks;
- all speculative-execution or microarchitectural side channels;
- unrestricted DMA before IOMMU support;
- complete denial-of-service resistance;
- rollback-resistant secure boot or remote attestation.

These exclusions may be narrowed later, but they must never be hidden.

### Intended invariants

The architecture should make the following properties precise and testable:

1. Authority originates only from the initial system endowment or an explicit capability operation.
2. Deriving or transferring a capability cannot increase its rights.
3. A task cannot access memory without both authority and a valid mapping.
4. Kernel memory and metadata are inaccessible from user mode.
5. Executable memory is not writable under the same authority.
6. Memory is cleared before reassignment between protection domains.
7. A user fault cannot corrupt the kernel or an unrelated task.
8. Device and interrupt access is explicitly delegated.
9. Kernel inputs, lengths, addresses, and arithmetic are validated before effects occur.
10. Potentially unbounded privileged operations are avoided, budgeted, or restartable.

NX, supervisor write protection, W^X, SMEP, SMAP, and IOMMU protections should be used when present in the declared hardware baseline.

### Evidence

Security descriptions will distinguish between:

- **implemented** — the mechanism exists;
- **tested** — named positive and adversarial tests pass;
- **model-checked** — state transitions satisfy a written model;
- **formally verified** — a stated property has a machine-checked proof under stated assumptions;
- **independently reviewed** — the evidence has been examined outside its implementation path.

No document or release may use a stronger description than its evidence supports.

## 5. Assembly and the native toolchain

C is not a required implementation language, and no C runtime is intended to enter the target system.

Early Algebra code will be direct x86_64 assembly. The project will then develop an original assembly-derived language that preserves visible machine behavior while allowing more invariants to be checked before execution.

Its intended properties include:

- explicit register inputs, outputs, and clobbers;
- explicit stack shape and alignment;
- integer widths and address classes;
- typed pointers and capability values;
- declared memory, I/O, privilege, and fault effects;
- structured control flow with known indirect targets;
- compile-time layouts and bounds;
- no hidden heap, runtime, or control flow;
- deterministic instruction encoding.

The language’s syntax, type system, escape rules, and checker are still open. A typed assembly language becomes a security aid only when those parts are precisely specified and validated.

### Bootstrap stages

1. **Seed:** Algebra-authored source is assembled into an inspectable seed image using temporary host tools.
2. **Owned host tools:** An Algebra-authored assembler and image builder run on the host environment.
3. **Checked toolchain:** Algebra gains its own linker, disassembler, structured-assembly checker, and independent binary checks.
4. **Native tools:** Those tools run as Algebra programs.
5. **Self-build:** Algebra reproducibly constructs a new Algebra image while running Algebra.

Self-hosting removes an ordinary build dependency. It does not rewrite or conceal the historical bootstrap path.

## 6. Milestones and acceptance gates

Milestones are evidence-gated rather than date-gated.

### M0 — Charter

Produce:

- the platform and authorship boundary;
- an initial threat model;
- the bootstrap and provenance policy;
- the first architecture decisions;
- a reproducibility and binary-inspection procedure.

**Gate:** every external assumption and temporary tool category is documented.

### M1 — Controlled handoff

Implement the selected x86_64 UEFI boot route.

Produce:

- an independently authored loader image;
- a versioned boot-information contract;
- deterministic serial diagnostics;
- a reproducible emulator boot;
- an audit showing no foreign target objects or runtimes.

**Gate:** control reaches Algebra code reproducibly and emits an identifiable serial record.

### M2 — Machine foundation

Produce:

- Algebra-owned page tables and privilege state;
- exception and fault entry;
- register-state diagnostics;
- physical-frame accounting;
- executable-data separation.

**Gate:** deliberate faults are classified and reported without uncontrolled kernel failure.

### M3 — User isolation

Produce:

- user-mode entry and return;
- at least two distinct user address spaces;
- a minimal system-call path;
- user-task fault delivery or termination;
- timer-based recovery from an infinite user loop.

**Gate:** neither user address space can read, write, or execute the other’s private memory.

### M4 — Capabilities and IPC

Produce:

- the initial kernel-object model;
- capability storage and lookup;
- rights-reducing derivation and explicit transfer;
- stale-handle protection;
- bounded IPC or notification primitives;
- documented revocation behavior.

**Gate:** forged, stale, amplified, and unauthorized capability operations fail closed.

### M5 — Component system

Produce:

- an initial user task;
- user-space resource policy;
- explicit component construction and authority delegation;
- user-space interrupt delivery;
- at least one isolated user-space service.

**Gate:** a deliberately faulty component can crash or spin while the kernel and an unrelated component continue operating.

### M6 — Physical machine and persistence

Select one exact hardware profile and produce:

- repeatable physical boot;
- documented interrupt, timer, PCI, and console behavior;
- one original storage driver;
- one deliberately small persistent format;
- documented DMA assumptions or IOMMU enforcement.

**Gate:** malformed storage input remains confined to the responsible service and cannot create authority.

### M7 — Native development environment

Produce original implementations of:

- terminal and input handling;
- source-entry or editing tools;
- shell or command environment;
- debugger and test runner;
- assembler, checker, linker, and image builder.

**Gate:** useful Algebra development can occur without another operating system serving as the interactive environment.

### M8 — Self-hosting

Produce:

- a complete documented bootstrap chain;
- an Algebra-native system build;
- reproducible output with differences either absent or completely explained.

**Gate:** Algebra builds a new bootable Algebra image using its own resident tools and no third-party target object.

### M9 — Assurance

For each security property, publish:

- the exact claim;
- assumptions and exclusions;
- tests and counter-tests;
- relevant state-machine or proof artifacts;
- privileged binary measurements.

**Gate:** every public security description points to matching evidence.

## 7. Explicitly deferred work

The first system does not require:

- SMP;
- Linux, Unix, or POSIX compatibility;
- a C ABI;
- dynamic linking;
- broad commodity-hardware support;
- networking;
- USB, audio, or accelerated graphics;
- a desktop environment;
- package management;
- virtualization;
- loadable kernel modules;
- production cryptography.

These features are not permanently forbidden. Each must arrive as an isolated component or as a separately justified change to the privileged architecture.

## 8. Open decisions

The following must be resolved through written architecture decisions rather than accidental implementation:

- exact x86_64 feature baseline;
- initial emulator profile;
- first physical reference machine;
- precise UEFI subset beyond the accepted seed handoff;
- system-image and executable formats;
- synchronous, asynchronous, or combined IPC;
- capability derivation, delegation, and revocation;
- scheduling and preemption policy;
- kernel memory-allocation policy;
- interrupt ownership and delivery;
- object lifecycle and failure semantics;
- timing of SMP support;
- IOMMU and DMA policy;
- secure-boot policy;
- structured-assembly syntax and verification model;
- project license and contribution policy.

Until a license is chosen and published, the repository should not describe itself as open source or invite code contributions.

## 9. First meaningful release

The first meaningful Algebra release is a defensible substrate, not yet a general-purpose desktop.

It should:

- boot through an original Algebra loader;
- establish user-mode address-space isolation;
- enforce explicit capability-authorized operations;
- provide bounded inter-component communication;
- preempt and contain an untrusted user component;
- delegate at least one hardware interrupt to a user-space driver;
- run on one documented physical x86_64 machine;
- be built from original Algebra source with Algebra’s own tools;
- publish its threat model, provenance record, assumptions, privileged size, and acceptance-test results.

From that foundation, a complete personal computing environment can be constructed without turning the kernel into the entire system.
