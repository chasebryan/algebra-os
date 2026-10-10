"""Execute the target descriptor/hex builders against host-owned buffers."""

import ctypes
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[2] / "boot/x86_64/uefi/descriptors.S"


@unittest.skipUnless(shutil.which("as") and shutil.which("ld"), "requires GNU binutils")
class DescriptorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix="algebra-descriptors-")
        cls.addClassCleanup(cls.scratch.cleanup)
        root = Path(cls.scratch.name)
        subprocess.run(["as", "--64", "--fatal-warnings", "-o", str(root / "descriptor.o"), str(SOURCE)], check=True)
        subprocess.run(["ld", "-shared", "-z", "noexecstack", "-o", str(root / "descriptor.so"), str(root / "descriptor.o")], check=True)
        cls.library = ctypes.CDLL(str(root / "descriptor.so"))
        cls.library.build_idt.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint64]
        cls.library.build_tss_descriptor.argtypes = [ctypes.c_void_p, ctypes.c_uint64]
        cls.library.encode_hex64.argtypes = [ctypes.c_void_p, ctypes.c_uint64]

    def test_all_gate_addresses_and_emergency_stacks(self):
        base = 0xffff800012340000
        offsets = (ctypes.c_int32 * 256)(*(i * 16 - 32 for i in range(256)))
        storage = ctypes.create_string_buffer(bytes([0xaa]) * 4112)
        self.library.build_idt(storage, offsets, base)
        for vector in range(256):
            low, selector, ist, flags, middle, high, reserved = struct.unpack_from("<HHBBHII", storage.raw, vector * 16)
            self.assertEqual(low | middle << 16 | high << 32, base + offsets[vector])
            self.assertEqual(selector, 8)
            self.assertEqual(flags, 0x8e)
            self.assertEqual(ist, {8: 1, 2: 2, 18: 3}.get(vector, 0))
            self.assertEqual(reserved, 0)
        self.assertEqual(storage.raw[4096:4112], bytes([0xaa]) * 16)

    def test_tss_full_width_base_and_exact_limit(self):
        for base in (0, 0x123456789abcdef0, 0xffff800000010000):
            storage = ctypes.create_string_buffer(bytes([0xaa]) * 24)
            self.library.build_tss_descriptor(storage, base)
            low, middle, base16, access, flags, base24, high, reserved = struct.unpack_from("<HHBBBBII", storage.raw)
            self.assertEqual(low, 103)
            self.assertEqual(middle | base16 << 16 | base24 << 24 | high << 32, base)
            self.assertEqual((access, flags, reserved), (0x89, 0, 0))
            self.assertEqual(storage.raw[16:24], bytes([0xaa]) * 8)

    def test_hex_encoding_preserves_leading_zeroes_and_buffer_boundary(self):
        for value in (0, 1, 0xabcdef, 0x0123456789abcdef, 0xffffffffffffffff):
            storage = ctypes.create_string_buffer(b"x" * 20)
            self.library.encode_hex64(storage, value)
            self.assertEqual(storage.raw[:16], f"{value:016x}".encode("ascii"))
            self.assertEqual(storage.raw[16:20], b"xxxx")


if __name__ == "__main__":
    unittest.main()
