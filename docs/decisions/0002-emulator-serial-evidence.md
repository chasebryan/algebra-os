# ADR 0002: Capture bounded serial diagnostics under QEMU

- **Status:** accepted for emulator bootstrap
- **Scope:** UEFI seed runtime evidence

[ADR 0003](0003-bounded-firmware-memory-map.md) extends the evidence gate
to require a memory-map validation record as well as the serial entry record.

## Decision

The bootstrap reference profile is QEMU's versioned `pc-q35-8.2` machine,
TCG acceleration, one `qemu64` CPU, 128 MiB RAM, no network interface, and
unsigned development OVMF firmware. This profile is an emulator premise;
physical-machine console discovery remains an open decision.

After the firmware console call, the seed initializes the emulated 16550
COM1 UART at ports `0x3f8` through `0x3fd`, using 115200 baud and 8N1. It
emits `Algebra serial 0001: uefi entry` followed by CRLF. The console call's
return status is preserved, and the seed still returns to firmware.

Each byte gets at most 65536 transmitter-ready polls. The seed abandons
serial output on exhaustion. This is a bounded instruction count, not a
wall-clock timeout or a claim that an absent physical UART can be detected.
The implementation only clobbers volatile registers after the firmware call.

`make boot-check` requires the complete serial record in two emulator boots.
Each boot gets its own copied firmware-variable template and copied ESP.
The host stops and reaps QEMU after observing the record, after unexpected
exit, or after 30 seconds. Serial capture is independent of firmware console
redirection, so firmware printing the old console message cannot satisfy
the test. A unique evidence directory prevents old captures from passing it.

The evidence includes the QEMU version, machine/CPU profile, firmware and
EFI SHA-256 hashes, exact commands, serial captures, and pass/fail outcome.
CI retains these with the EFI image. Firmware package versions can change;
the hashes identify the precise bytes exercised in each run. Packages are
recorded per run rather than claiming a permanently pinned installation.

## Limits

The record establishes that firmware loaded and entered Algebra code and
that the seed reached its serial-output path. The test stops at that point;
it does not establish a successful return to firmware, `ExitBootServices`,
kernel entry, user isolation, or completion of M1.

QEMU, OVMF, and Python are host validation instruments. They are not linked
into or distributed as components of the Algebra EFI image.

## Reference

- [QEMU invocation and versioned machine profiles](https://www.qemu.org/docs/master/system/invocation.html)
