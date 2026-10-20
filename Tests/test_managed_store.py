"""Synthetic malformed-input and overlapping-copy checks for the unpacker."""

import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts/extract_managed_store.py"
SPEC = importlib.util.spec_from_file_location("managed_store", SCRIPT)
STORE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STORE)


class ManagedStoreTests(unittest.TestCase):
    def test_literal_block(self):
        self.assertEqual(STORE.decode_lz4_block(b"\x50hello", 5), b"hello")

    def test_overlapping_match(self):
        # One literal followed by an offset-one match of eight bytes.
        self.assertEqual(STORE.decode_lz4_block(b"\x14A\x01\x00", 9), b"A" * 9)

    def test_extended_literal_length(self):
        self.assertEqual(STORE.decode_lz4_block(b"\xf0\x05" + b"B" * 20, 20), b"B" * 20)

    def test_reject_invalid_back_reference(self):
        for data in [b"\x00\x00\x00", b"\x00\x01\x00"]:
            with self.subTest(data=data), self.assertRaises(ValueError):
                STORE.decode_lz4_block(data, 4)

    def test_reject_truncation_and_declared_overflow(self):
        for data, size in [(b"\xf0", 20), (b"\x50hi", 5), (b"\x50hello", 4), (b"\x10A", 2)]:
            with self.subTest(data=data, size=size), self.assertRaises(ValueError):
                STORE.decode_lz4_block(data, size)

    def test_reject_wrong_carrier(self):
        with self.assertRaises(ValueError):
            STORE.payload_from_elf(b"not an ELF")


if __name__ == "__main__":
    unittest.main()
