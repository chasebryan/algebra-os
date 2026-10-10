"""Execute target frame accounting against synthetic firmware ranges."""

import ctypes
from pathlib import Path
import random
import shutil
import struct
import subprocess
import tempfile
import unittest


SOURCES = Path(__file__).resolve().parents[2] / "boot/x86_64/uefi"
CATALOG_SIZE = 81920
FREE_OFFSET = 52480


@unittest.skipUnless(shutil.which("as") and shutil.which("ld"), "requires GNU binutils")
class FrameCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix="algebra-frame-tests-")
        cls.addClassCleanup(cls.scratch.cleanup)
        root = Path(cls.scratch.name)
        objects = []
        for source in ("frames", "memory-map"):
            target = root / f"{source}.o"
            subprocess.run(["as", "--64", "--fatal-warnings", "-o", str(target), str(SOURCES / f"{source}.S")], check=True)
            objects.append(str(target))
        subprocess.run(["ld", "-shared", "-z", "noexecstack", "-o", str(root / "frames.so"), *objects], check=True)
        cls.library = ctypes.CDLL(str(root / "frames.so"))
        cls.builder = cls.library.build_frame_catalog
        cls.builder.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint64]
        cls.builder.restype = ctypes.c_uint32

    def build(self, ranges, image=(256, 16), stride=48, version=1, capacity=CATALOG_SIZE):
        data = b"".join(struct.pack("<IIQQQQ", kind, 0, start << 12, 0, pages, attributes)
                        + bytes(stride - 40) for start, pages, kind, attributes in ranges)
        memory_map = ctypes.create_string_buffer(data)
        config = (ctypes.c_uint64 * 6)(ctypes.addressof(memory_map), len(data), stride,
                                     version, image[0] << 12, image[1] << 12)
        output = ctypes.create_string_buffer(b"x" * (CATALOG_SIZE + 16))
        status = self.builder(output, config, capacity)
        self.assertEqual(output.raw[CATALOG_SIZE:CATALOG_SIZE + 16], b"x" * 16)
        return status, output.raw[:CATALOG_SIZE]

    def catalog(self, ranges, **kwargs):
        status, data = self.build(ranges, **kwargs)
        self.assertEqual(status, 0)
        self.assertEqual(data[:8], b"ALGFRM1\0")
        version, size = struct.unpack_from("<II", data, 8)
        self.assertEqual((version, size), (1, CATALOG_SIZE))
        descriptors, count, frames, total, first, end = struct.unpack_from("<6Q", data, 16)
        work = [struct.unpack_from("<4Q", data, 64 + i * 32) for i in range(descriptors)]
        free = [struct.unpack_from("<2Q", data, FREE_OFFSET + i * 16) for i in range(count)]
        self.assertEqual(work, sorted(work))
        self.assertEqual(frames, sum(pages for start, pages in free))
        self.assertEqual(total, sum(pages for start, pages, kind, attr in work))
        for start, pages in free:
            self.assertTrue(start + pages <= first or start >= end)
        for left, right in zip(free, free[1:]):
            self.assertLessEqual(left[0] + left[1], right[0])
        return free, frames, work

    def test_unsorted_ranges_and_image_split(self):
        free, count, work = self.catalog([(300, 10, 7, 0), (250, 40, 4, 0), (50, 20, 9, 0)])
        self.assertEqual(free, [(250, 6), (272, 18), (300, 10)])
        self.assertEqual(count, 34)

    def test_only_reclaimable_types_without_runtime_authority_are_available(self):
        free, _, _ = self.catalog([(i * 8, 4, i, 0) for i in range(17)]
                                  + [(200, 4, 7, 1 << 63)])
        self.assertEqual(free, [(24, 4), (32, 4), (56, 4)])

    def test_image_exclusion_across_multiple_ranges(self):
        free, count, _ = self.catalog([(100, 10, 7, 0), (110, 10, 7, 0),
                                      (120, 10, 7, 0), (130, 10, 7, 0)], image=(105, 30))
        self.assertEqual(free, [(100, 5), (135, 5)])
        self.assertEqual(count, 10)

    def test_overlap_and_duplicate_descriptors_invalidate_catalog(self):
        for ranges in ([(100, 10, 7, 0), (105, 10, 4, 0)],
                       [(100, 10, 7, 0), (100, 10, 7, 0)]):
            status, data = self.build(ranges)
            self.assertEqual(status, 1)
            self.assertEqual(data[:8], bytes(8))

    def test_last_physical_page_and_full_address_space_accounting(self):
        free, count, _ = self.catalog([((1 << 52) - 1, 1, 7, 0)])
        self.assertEqual(free, [((1 << 52) - 1, 1)])
        free, count, _ = self.catalog([(0, 1 << 52, 7, 0)])
        self.assertEqual(count, (1 << 52) - 16)

    def test_maximum_descriptor_capacity_and_one_extra_split(self):
        ranges = [(i * 4, 4, 7, 0) for i in range(1638)]
        free, count, _ = self.catalog(list(reversed(ranges)), image=(1, 1), stride=40)
        self.assertEqual(len(free), 1639)
        self.assertEqual(count, 1638 * 4 - 1)

    def test_malformed_shape_and_image_extent_fail(self):
        for kwargs in ({"version": 2}, {"image": (256, 0)}, {"capacity": 81919}):
            status, _ = self.build([(100, 5, 7, 0)], **kwargs)
            self.assertEqual(status, 1)
        self.assertEqual(self.build([])[0], 1)
        self.assertEqual(self.build([(0, 0, 7, 0)])[0], 1)

    def test_deterministic_range_accounting_against_page_set(self):
        rng = random.Random(0xa16f16)
        for _ in range(30):
            ranges = []
            position = 0
            expected = set()
            for index in range(30):
                position += rng.randrange(3)
                pages = rng.randrange(1, 9)
                kind = rng.choice([3, 4, 7, 2, 9, 16])
                attributes = rng.choice([0, 0, 1 << 63])
                ranges.append((position, pages, kind, attributes))
                if kind in (3, 4, 7) and not attributes & (1 << 63):
                    expected.update(range(position, position + pages))
                position += pages
            expected.difference_update(range(40, 80))
            rng.shuffle(ranges)
            free, count, _ = self.catalog(ranges, image=(40, 40), stride=56)
            observed = set().union(*(set(range(start, start + pages)) for start, pages in free))
            self.assertEqual(observed, expected)
            self.assertEqual(count, len(expected))


if __name__ == "__main__":
    unittest.main()
