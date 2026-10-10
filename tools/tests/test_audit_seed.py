"""Ensure a failed ELF inspection cannot be mistaken for a clean audit."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


AUDIT = Path(__file__).resolve().parents[1] / "audit-seed.sh"
HEADERS = """file format pei-x86-64
Magic 020b
Subsystem 0000000a
AddressOfEntryPoint 0000000000001000
Time/Date Thu Jan 1 00:00:00 1970
Entry 1 0000000000000000 00000000 Import Directory
Entry 5 0000000000004000 0000000c Base Relocation Directory [.reloc]
"""
SECTIONS = """ 0 .text 00000020
CONTENTS, ALLOC, LOAD, READONLY, CODE
 1 .rdata 00000020
CONTENTS, ALLOC, LOAD, READONLY, DATA
 2 .data 00000008
CONTENTS, ALLOC, LOAD, DATA
 3 .reloc 0000000c
CONTENTS, ALLOC, LOAD, READONLY, DATA
"""


class AuditTests(unittest.TestCase):
    def audit(self, readelf_status=0, nm_status=0, headers=HEADERS):
        with tempfile.TemporaryDirectory(prefix="algebra audit ") as root:
            root = Path(root)
            elf, efi = root / "seed.elf", root / "seed.efi"
            elf.write_bytes(b"input placeholder")
            efi.write_bytes(b"input placeholder")
            objdump = root / "mock objdump"
            objdump.write_text(
                "#!/bin/sh\nif [ \"$1\" = -p ]; then\n"
                "cat <<'HEADERS'\n" + headers + "HEADERS\nelse\n"
                "cat <<'SECTIONS'\n" + SECTIONS + "SECTIONS\nfi\n"
            )
            readelf, nm = root / "mock readelf", root / "mock nm"
            readelf.write_text(f"#!/bin/sh\nexit {readelf_status}\n")
            nm.write_text(f"#!/bin/sh\nexit {nm_status}\n")
            for tool in (objdump, readelf, nm):
                tool.chmod(0o700)
            env = dict(os.environ, OBJDUMP=str(objdump), READELF=str(readelf), NM=str(nm))
            return subprocess.run(
                ["sh", str(AUDIT), str(elf), str(efi)], env=env,
                capture_output=True, text=True, timeout=5,
            )

    def test_successful_inspections_with_spaces_in_tool_paths(self):
        result = self.audit()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_readelf_failure_is_reported(self):
        result = self.audit(readelf_status=7)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("readelf could not inspect", result.stderr)

    def test_nm_failure_is_reported(self):
        result = self.audit(nm_status=7)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("nm could not inspect", result.stderr)

    def test_nonzero_timestamp_in_1970_is_rejected(self):
        result = self.audit(headers=HEADERS.replace("00:00:00 1970", "00:00:01 1970"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("timestamp", result.stderr)


if __name__ == "__main__":
    unittest.main()
