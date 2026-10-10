"""Run the target assembly validator on host buffers using host-only ctypes."""

import ctypes
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[2] / "boot/x86_64/uefi/memory-map.S"


@unittest.skipUnless(shutil.which("as") and shutil.which("ld"), "requires GNU binutils")
class MemoryMapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix="algebra-map-test-")
        cls.addClassCleanup(cls.scratch.cleanup)
        root = Path(cls.scratch.name)
        subprocess.run(["as", "--64", "--fatal-warnings", "-o", str(root / "map.o"), str(SOURCE)], check=True)
        subprocess.run(["ld", "-shared", "-z", "noexecstack", "-o", str(root / "map.so"), str(root / "map.o")], check=True)
        cls.library = ctypes.CDLL(str(root / "map.so"))
        cls.validate = cls.library.validate_memory_map
        cls.validate.argtypes = [ctypes.c_void_p, ctypes.c_uint64, ctypes.c_uint64, ctypes.c_uint32]
        cls.validate.restype = ctypes.c_uint32

    def check_map(self, physical=0x1000, virtual=0, pages=1, stride=48, version=1, size=None):
        descriptor = struct.pack("<IIQQQQ", 7, 0, physical, virtual, pages, 0)
        data = descriptor + bytes(max(0, stride - len(descriptor)))
        buffer = ctypes.create_string_buffer(data)
        return self.validate(buffer, len(data) if size is None else size, stride, version)

    def test_firmware_stride_is_used(self):
        for stride in (40, 48, 56):
            self.assertEqual(self.check_map(stride=stride), 0)

    def test_bad_shape_is_rejected_before_iteration(self):
        for change in ({"stride": 0}, {"stride": 32}, {"stride": 41},
                       {"version": 2}, {"size": 0}, {"size": 65537}, {"size": 47}):
            self.assertEqual(self.check_map(**change), 1, change)

    def test_page_alignment_and_nonzero_count(self):
        for change in ({"physical": 1}, {"virtual": 1}, {"pages": 0}):
            self.assertEqual(self.check_map(**change), 1, change)

    def test_page_range_cannot_wrap(self):
        for change in ({"physical": 0xfffffffffffff000, "pages": 2},
                       {"virtual": 0xfffffffffffff000, "pages": 2}, {"pages": (1 << 52) + 1}):
            self.assertEqual(self.check_map(**change), 1, change)

    def test_last_representable_page_is_valid(self):
        self.assertEqual(self.check_map(physical=0xfffffffffffff000), 0)
        self.assertEqual(self.check_map(physical=0, pages=1 << 52), 0)

    def test_null_and_wrapping_buffer_pointers_are_rejected(self):
        self.assertEqual(self.validate(None, 48, 48, 1), 1)
        self.assertEqual(self.validate(0xfffffffffffffff0, 48, 48, 1), 1)

    def test_later_descriptors_are_checked(self):
        good = struct.pack("<IIQQQQ", 7, 0, 0x1000, 0, 1, 0) + bytes(8)
        bad = struct.pack("<IIQQQQ", 7, 0, 0x2001, 0, 1, 0) + bytes(8)
        buffer = ctypes.create_string_buffer(good + bad)
        self.assertEqual(self.validate(buffer, 96, 48, 1), 1)


if __name__ == "__main__":
    unittest.main()
