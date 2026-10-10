"""Execute target table construction and independently walk its mappings."""

import ctypes
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[2] / "boot/x86_64/uefi/page-tables.S"
ADDRESS_MASK = 0x000ffffffffff000
NX = 1 << 63


@unittest.skipUnless(shutil.which("as") and shutil.which("ld"), "requires GNU binutils")
class PageTableTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix="algebra-page-tests-")
        cls.addClassCleanup(cls.scratch.cleanup)
        root = Path(cls.scratch.name)
        subprocess.run(["as", "--64", "--fatal-warnings", "-o", str(root / "tables.o"), str(SOURCE)], check=True)
        subprocess.run(["ld", "-shared", "-z", "noexecstack", "-o", str(root / "tables.so"), str(root / "tables.o")], check=True)
        cls.library = ctypes.CDLL(str(root / "tables.so"))
        cls.builder = cls.library.build_kernel_page_tables
        cls.builder.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        cls.builder.restype = ctypes.c_uint32

    def configuration(self, base=0x100000):
        return [base + 0x10000, base, 0x40000, base + 0x1000, base + 0x5000,
                base + 0x8000, base + 0x3f000,
                base + 0x20000, base + 0x21000, base + 0x22000, base + 0x23000]

    def build(self, fields):
        output = ctypes.create_string_buffer(bytes([0xaa]) * (32768 + 16))
        config = (ctypes.c_uint64 * 11)(*fields)
        status = self.builder(output, config)
        self.assertEqual(output.raw[32768:32784], bytes([0xaa]) * 16)
        return status, output.raw[:32768]

    def walk(self, tables, root, address):
        table = root
        for shift in (39, 30, 21, 12):
            offset = table - root + ((address >> shift) & 511) * 8
            self.assertTrue(0 <= offset <= len(tables) - 8)
            entry = struct.unpack_from("<Q", tables, offset)[0]
            if not entry & 1:
                return None
            self.assertFalse(entry & 4, "a bootstrap mapping grants user access")
            if shift != 12:
                self.assertFalse(entry & 128, "unexpected huge-page mapping")
            table = entry & ADDRESS_MASK
        return entry

    def test_permissions_and_guards_for_every_image_page(self):
        for base in (0x100000, 0x3ffe0000, 0xfffc0000):
            fields = self.configuration(base)
            status, tables = self.build(fields)
            self.assertEqual(status, 0)
            for address in range(base, base + fields[2], 4096):
                entry = self.walk(tables, fields[0], address)
                if address in fields[7:]:
                    self.assertIsNone(entry)
                    continue
                self.assertIsNotNone(entry)
                self.assertEqual(entry & ADDRESS_MASK, address)
                self.assertEqual(bool(entry & 2), fields[5] <= address < fields[6])
                self.assertEqual(bool(entry & NX), not fields[3] <= address < fields[4])
                self.assertFalse(entry & 2 and not entry & NX)
            for address in (0, base - 4096, base + fields[2], 0x400000000000):
                self.assertIsNone(self.walk(tables, fields[0], address))

    def test_invalid_configuration_leaves_output_untouched(self):
        changes = [
            (0, 0x110001), (1, 0), (1, 0xfffffffffffff000), (2, 0), (2, 0x101000),
            (3, 0x100000 - 4096), (4, 0x100000), (4, 0x101001),
            (5, 0x101000), (6, 0x141000), (7, 0x110000),
            (7, 0x101000), (7, 0x120001), (8, 0x120000),
        ]
        for index, value in changes:
            fields = self.configuration()
            fields[index] = value
            status, output = self.build(fields)
            self.assertEqual(status, 1, (index, value))
            self.assertEqual(output, bytes([0xaa]) * 32768)

    def test_null_and_aliasing_pointers_are_rejected(self):
        fields = (ctypes.c_uint64 * 11)(*self.configuration())
        output = ctypes.create_string_buffer(32768)
        self.assertEqual(self.builder(None, fields), 1)
        self.assertEqual(self.builder(output, None), 1)
        self.assertEqual(self.builder(output, ctypes.addressof(output) + 32), 1)
        self.assertEqual(self.builder(0xfffffffffffffff0, fields), 1)


if __name__ == "__main__":
    unittest.main()
