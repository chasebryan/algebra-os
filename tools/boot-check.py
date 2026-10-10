#!/usr/bin/env python3
"""Boot the seed twice with fresh OVMF variables and retain measured evidence."""

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


REQUIRED_RECORDS = (
    b"Algebra serial 0001: uefi entry\r\n",
    b"Algebra memory map 0001: validated\r\n",
    b"Algebra kernel 0001: boot services exited\r\n",
    b"Algebra machine 0001: descriptor tables installed\r\n",
    b"Algebra memory 0001: own page tables active\r\n",
    b"Algebra frames 0001: inventory ready\r\n",
)
MARKER = b"".join(REQUIRED_RECORDS)
FAULT_COMPLETE = b"Algebra fault 0001: diagnostics complete\r\n"
REGISTER_NAMES = {"rax", "rcx", "rdx", "rbx", "rbp", "rsi", "rdi"} | {f"r{i}" for i in range(8, 16)}


def records_end(data):
    position = 0
    for record in REQUIRED_RECORDS:
        found = data.find(record, position)
        if found < 0:
            return None
        position = found + len(record)
    return position


def records_seen(data):
    return records_end(data) is not None


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def memory_record(data):
    match = re.search(rb"Algebra frames 0001: extents=([0-9a-f]{16}) free=([0-9a-f]{16})\r\n", data)
    if match is None:
        return None
    extents, frames = (int(value, 16) for value in match.groups())
    if not 0 < extents <= 1639 or not extents <= frames <= 1 << 52:
        return None
    return {"free_extents": extents, "free_frames": frames}


def fault_record(data):
    start = records_end(data)
    if start is None:
        return None
    data = data[start:]
    header = re.search(
        rb"Algebra fault 0001: vector=([0-9a-f]{16}) error=([0-9a-f]{16}) "
        rb"rip=([0-9a-f]{16}) cr2=([0-9a-f]{16})\r\n", data,
    )
    if header is None:
        return None
    complete = data.find(FAULT_COMPLETE, header.end())
    if complete < 0:
        return None
    capture = data[header.end():complete]
    registers = re.findall(rb"Algebra register 0001: ([a-z0-9 ]{3})=([0-9a-f]{16})\r\n", capture)
    names = [name.decode("ascii").strip() for name, value in registers]
    if len(names) != 15 or set(names) != REGISTER_NAMES:
        return None
    state = re.search(rb"Algebra state 0001: rsp=([0-9a-f]{16}) rflags=([0-9a-f]{16})\r\n", capture)
    if state is None:
        return None
    result = dict(zip(("vector", "error", "rip", "cr2"), (int(value, 16) for value in header.groups())))
    result["registers"] = {name: int(value, 16) for name, (_, value) in zip(names, registers)}
    result.update(rsp=int(state[1], 16), rflags=int(state[2], 16))
    return result


def boot(qemu, esp, code, variables, output, timeout, expected_fault=None, expected_error=None, expected_cr2=None, expected_registers=None, cr2_register=None):
    serial = output / "serial.log"
    with tempfile.TemporaryDirectory(prefix="algebra-boot-") as scratch:
        scratch = Path(scratch)
        # Never let the guest write the firmware template or source ESP.
        shutil.copyfile(variables, scratch / "vars.fd")
        shutil.copytree(esp, scratch / "esp")
        command = [
            qemu, "-machine", "pc-q35-8.2", "-accel", "tcg",
            "-cpu", "qemu64", "-m", "128M", "-smp", "1",
            "-drive", f"if=pflash,format=raw,readonly=on,file={code}",
            "-drive", f"if=pflash,format=raw,file={scratch / 'vars.fd'}",
            "-drive", f"format=raw,file=fat:rw:{scratch / 'esp'}",
            "-display", "none", "-monitor", "none",
            "-serial", f"file:{serial}", "-nic", "none", "-no-reboot",
        ]
        (output / "command.json").write_text(json.dumps(command, indent=2) + "\n")
        with (output / "qemu.log").open("wb") as log:
            environment = dict(os.environ, TMPDIR=str(scratch))
            process = subprocess.Popen(command, stdout=log, stderr=log, env=environment)
            try:
                deadline = time.monotonic() + timeout
                while True:
                    if serial.is_file():
                        data = serial.read_bytes()
                        if records_seen(data) and memory_record(data) is not None:
                            if expected_fault is None:
                                return None
                            fault = fault_record(data)
                            if fault is not None:
                                for name, expected in (("vector", expected_fault), ("error", expected_error), ("cr2", expected_cr2)):
                                    if expected is not None and fault[name] != expected:
                                        raise RuntimeError(f"fault {name}: expected {expected:#x}, observed {fault[name]:#x}")
                                for name, expected in (expected_registers or {}).items():
                                    observed = fault.get(name, fault["registers"].get(name))
                                    if observed != expected:
                                        raise RuntimeError(f"saved {name}: expected {expected:#x}, observed {observed:#x}")
                                if cr2_register and fault["cr2"] != fault["registers"][cr2_register]:
                                    raise RuntimeError(f"CR2 does not match saved {cr2_register}")
                                return fault
                    if process.poll() is not None:
                        raise RuntimeError(f"QEMU exited before the seed record: {process.returncode}")
                    if time.monotonic() >= deadline:
                        raise RuntimeError(f"seed record absent after {timeout:g} seconds")
                    time.sleep(0.1)
            finally:
                if process.poll() is None:
                    process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--esp", type=Path, required=True)
    parser.add_argument("--code", type=Path, required=True)
    parser.add_argument("--vars", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--qemu", default="qemu-system-x86_64")
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--expect-fault", type=lambda value: int(value, 0), choices=range(256), metavar="VECTOR")
    parser.add_argument("--expect-error", type=lambda value: int(value, 0))
    parser.add_argument("--expect-cr2", type=lambda value: int(value, 0))
    parser.add_argument("--expect-register", action="append", default=[], metavar="NAME=VALUE")
    parser.add_argument("--expect-cr2-register", choices=sorted(REGISTER_NAMES))
    args = parser.parse_args()
    registers = {}
    for item in args.expect_register:
        try:
            name, text = item.split("=", 1)
            value = int(text, 0)
        except ValueError:
            parser.error("register expectations use NAME=VALUE")
        if name not in REGISTER_NAMES | {"rsp", "rflags"} or name in registers or not 0 <= value < 1 << 64:
            parser.error(f"invalid or duplicate register expectation: {item}")
        registers[name] = value
    if args.expect_fault is None and (args.expect_error is not None or args.expect_cr2 is not None or registers or args.expect_cr2_register):
        parser.error("expected error and CR2 require --expect-fault")
    if any(value is not None and not 0 <= value < 1 << 64 for value in (args.expect_error, args.expect_cr2)):
        parser.error("expected error and CR2 must fit an unsigned 64-bit value")
    if not 0 < args.timeout <= 300:
        parser.error("timeout must be greater than zero and at most 300 seconds")
    qemu = shutil.which(args.qemu)
    if qemu is None:
        parser.error(f"QEMU executable not found: {args.qemu}")
    esp, code, variables = args.esp.resolve(), args.code.resolve(), args.vars.resolve()
    image = esp / "EFI/BOOT/BOOTX64.EFI"
    for path in (image, code, variables):
        if not path.is_file():
            parser.error(f"required input missing: {path}")
    # QEMU's option parser uses commas as separators even in argv strings.
    if any("," in str(path) for path in (esp, code, variables, args.evidence.resolve())):
        parser.error("QEMU paths must not contain commas")
    args.evidence.mkdir(parents=True, exist_ok=True)
    # A unique directory ensures an earlier log can never satisfy a new run.
    output = Path(tempfile.mkdtemp(prefix="run-", dir=args.evidence.resolve()))
    result = {
        "qemu_version": subprocess.check_output([qemu, "--version"], text=True).strip(),
        "machine": "pc-q35-8.2", "accelerator": "tcg", "cpu": "qemu64",
        "memory_mib": 128, "cpus": 1, "network": "none",
        "image_sha256": digest(image), "ovmf_code_sha256": digest(code),
        "ovmf_vars_sha256": digest(variables), "marker": MARKER.decode("ascii"),
        "boots": [], "passed": False,
        "expected_fault": args.expect_fault, "expected_error": args.expect_error, "expected_cr2": args.expect_cr2,
        "expected_registers": registers,
        "expected_cr2_register": args.expect_cr2_register,
    }
    try:
        for number in (1, 2):
            boot_output = output / f"boot-{number}"
            boot_output.mkdir()
            fault = boot(qemu, esp, code, variables, boot_output, args.timeout,
                         args.expect_fault, args.expect_error, args.expect_cr2, registers, args.expect_cr2_register)
            memory = memory_record((boot_output / "serial.log").read_bytes())
            result["boots"].append({"number": number, "marker_seen": True, "fault": fault, "memory": memory})
        result["passed"] = True
    except (OSError, RuntimeError) as error:
        result["error"] = str(error)
    finally:
        (output / "evidence.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"boot evidence: {output}", flush=True)
    if not result["passed"]:
        raise SystemExit(result.get("error", "boot check failed"))
    print("boot check: kernel handoff records observed in two fresh boots")


if __name__ == "__main__":
    main()
