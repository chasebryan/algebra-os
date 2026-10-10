#!/usr/bin/env python3
"""Boot the seed twice with fresh OVMF variables and retain measured evidence."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


REQUIRED_RECORDS = (
    b"Algebra serial 0001: uefi entry\r\n",
    b"Algebra memory map 0001: validated\r\n",
    b"Algebra kernel 0001: boot services exited\r\n",
)
MARKER = b"".join(REQUIRED_RECORDS)


def records_seen(data):
    position = 0
    for record in REQUIRED_RECORDS:
        found = data.find(record, position)
        if found < 0:
            return False
        position = found + len(record)
    return True


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def boot(qemu, esp, code, variables, output, timeout):
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
                    if serial.is_file() and records_seen(serial.read_bytes()):
                        return
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
    args = parser.parse_args()
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
    }
    try:
        for number in (1, 2):
            boot_output = output / f"boot-{number}"
            boot_output.mkdir()
            boot(qemu, esp, code, variables, boot_output, args.timeout)
            result["boots"].append({"number": number, "marker_seen": True})
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
