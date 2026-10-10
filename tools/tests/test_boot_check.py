"""Exercise emulator timeout, exit, success, and process cleanup paths."""

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "boot_check", Path(__file__).resolve().parents[1] / "boot-check.py"
)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class Process:
    def __init__(self, exit_code=None, stubborn=False):
        self.exit_code = exit_code
        self.stubborn = stubborn
        self.terminated = False
        self.killed = False

    def poll(self):
        return self.exit_code

    @property
    def returncode(self):
        return self.exit_code

    def terminate(self):
        self.terminated = True

    def kill(self):
        self.killed = True
        self.exit_code = -9

    def wait(self, timeout=None):
        if self.stubborn and not self.killed:
            raise runner.subprocess.TimeoutExpired("qemu", timeout)
        self.exit_code = self.exit_code if self.exit_code is not None else -15
        return self.exit_code


class BootCheckTests(unittest.TestCase):
    def diagnostic(self):
        lines = [runner.MARKER,
                 b"Algebra fault 0001: vector=000000000000000e error=0000000000000000 "
                 b"rip=0000000000100000 cr2=0000400000000000\r\n"]
        for index, name in enumerate(sorted(runner.REGISTER_NAMES)):
            lines.append(f"Algebra register 0001: {name:3}={index:016x}\r\n".encode("ascii"))
        lines.extend([b"Algebra state 0001: rsp=0000000000200000 rflags=0000000000000046\r\n",
                      runner.FAULT_COMPLETE])
        return b"".join(lines)

    def test_fault_capture_requires_every_register_and_completion(self):
        data = self.diagnostic()
        fault = runner.fault_record(data)
        self.assertEqual(fault["vector"], 14)
        self.assertEqual(fault["cr2"], 0x400000000000)
        self.assertEqual(set(fault["registers"]), runner.REGISTER_NAMES)
        self.assertIsNone(runner.fault_record(data.replace(runner.FAULT_COMPLETE, b"")))
        self.assertIsNone(runner.fault_record(data.replace(b"rax=", b"rbx=")))
        self.assertIsNone(runner.fault_record(data.replace(b"Algebra state 0001:", b"missing state:")))
        self.assertIsNone(runner.fault_record(data.replace(runner.MARKER, b"") + runner.MARKER))

    def run_boot(self, process, serial_bytes=b"", timeout=False):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            esp = root / "esp"
            esp.mkdir()
            (esp / "sentinel").write_bytes(b"source ESP")
            variables = root / "vars.fd"
            variables.write_bytes(b"firmware template")
            output = root / "output"
            output.mkdir()

            def launch(command, **kwargs):
                # The guest must use copies, not mutable repository inputs.
                self.assertNotIn(f"format=raw,file=fat:rw:{esp}", command)
                self.assertTrue(Path(kwargs["env"]["TMPDIR"]).is_dir())
                (output / "serial.log").write_bytes(serial_bytes)
                return process

            clock = [0, 1] if timeout else [0, 0]
            with patch.object(runner.subprocess, "Popen", side_effect=launch), \
                    patch.object(runner.time, "monotonic", side_effect=clock):
                runner.boot("qemu", esp, root / "code.fd", variables, output, 0.5)
            self.assertEqual(variables.read_bytes(), b"firmware template")
            self.assertEqual((esp / "sentinel").read_bytes(), b"source ESP")

    def test_marker_stops_and_reaps_emulator(self):
        process = Process()
        self.run_boot(process, runner.MARKER)
        self.assertTrue(process.terminated)
        self.assertIsNotNone(process.exit_code)

    def test_firmware_console_text_is_not_seed_serial_evidence(self):
        process = Process()
        with self.assertRaisesRegex(RuntimeError, "absent"):
            self.run_boot(process, b"Algebra seed 0001: x86_64 uefi\r\n", timeout=True)
        self.assertTrue(process.terminated)

    def test_entry_and_map_records_cannot_satisfy_kernel_handoff(self):
        self.assertFalse(runner.records_seen(b"".join(runner.REQUIRED_RECORDS[:2])))

    def test_records_must_appear_in_order(self):
        self.assertFalse(runner.records_seen(b"".join(reversed(runner.REQUIRED_RECORDS))))
        self.assertTrue(runner.records_seen(b"firmware output\n".join(runner.REQUIRED_RECORDS)))

    def test_early_emulator_exit_fails(self):
        process = Process(exit_code=1)
        with self.assertRaisesRegex(RuntimeError, "exited"):
            self.run_boot(process)
        self.assertFalse(process.terminated)

    def test_unresponsive_process_is_killed_and_reaped(self):
        process = Process(stubborn=True)
        self.run_boot(process, runner.MARKER)
        self.assertTrue(process.terminated)
        self.assertTrue(process.killed)
        self.assertEqual(process.exit_code, -9)


if __name__ == "__main__":
    unittest.main()
