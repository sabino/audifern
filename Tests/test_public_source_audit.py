# SPDX-License-Identifier: GPL-3.0-only
"""Privacy regression cases use synthetic source, identifiers and PNG data."""
import importlib.util
from pathlib import Path
import struct
import unittest
import zlib


_path = Path(__file__).resolve().parents[1] / "scripts/audit-public-source.py"
_spec = importlib.util.spec_from_file_location("public_source_audit", _path)
audit = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(audit)


def chunk(kind, payload=b""):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))


def png(*metadata, pixels=b"\0\0\0"):
    # A complete one-row RGB image. Level-zero deflate deliberately preserves
    # arbitrary byte sequences in IDAT, reproducing the heuristic false alarm.
    width = (len(pixels) + 2) // 3
    samples = pixels.ljust(width * 3, b"\0")
    header = struct.pack(">IIBBBBB", width, 1, 8, 2, 0, 0, 0)
    return (audit.PNG_SIGNATURE + chunk(b"IHDR", header) + b"".join(metadata)
            + chunk(b"IDAT", zlib.compress(b"\0" + samples, level=0)) + chunk(b"IEND"))


def categories(data, known=(), path=None):
    return {category for category, _ in audit.scan_bytes(data, list(known), path=path)}


class PublicSourceAuditTests(unittest.TestCase):
    def test_ordinary_source_still_checks_content_and_line_numbers(self):
        source = b'let count = 2\nlet password = "' + b'synthetic-fixture-password"\n'
        self.assertIn(("credential-literal", 2), audit.scan_bytes(source, []))
        self.assertEqual(audit.scan_bytes(b"// ordinary public source\nlet count = 2\n", []), [])

    def test_idat_email_and_home_bytes_are_not_prose(self):
        # Assemble rather than publish a real contact or home directory fixture.
        text = b"fixture@" + b"invalid.test /Users/" + b"fixture-owner"
        image = png(pixels=text)
        self.assertIn(text, image)
        self.assertEqual(categories(image), set())

    def test_exact_private_pattern_still_matches_original_idat(self):
        value = b"synthetic-idat-private-value"
        self.assertEqual(categories(png(pixels=value), [value]), {"known-private-value"})

    def test_uncompressed_text_email_is_detected(self):
        email = b"fixture@" + b"invalid.test"
        self.assertEqual(categories(png(chunk(b"tEXt", b"Author\0" + email))), {"email-address"})

    def test_ztxt_is_inflated_before_heuristic_and_exact_matching(self):
        email = b"fixture@" + b"invalid.test"
        image = png(chunk(b"zTXt", b"Comment\0\0" + zlib.compress(email)))
        self.assertNotIn(email, image)
        self.assertEqual(categories(image, [email]), {"email-address", "known-private-value"})

    def test_itxt_compressed_and_uncompressed_are_inspected(self):
        email = b"fixture@" + b"invalid.test"
        for compressed in (False, True):
            with self.subTest(compressed=compressed):
                text = zlib.compress(email) if compressed else email
                payload = b"Comment\0" + bytes([int(compressed), 0]) + b"en\0Comment\0" + text
                self.assertEqual(categories(png(chunk(b"iTXt", payload))), {"email-address"})

    def test_iccp_metadata_is_inflated_without_scanning_compressed_bytes(self):
        text = b"Synthetic profile: fixture@" + b"invalid.test"
        self.assertEqual(categories(png(chunk(b"iCCP", b"Profile\0\0" + zlib.compress(text)))), {"email-address"})

    def test_unknown_ancillary_metadata_and_appended_data_remain_visible(self):
        email = b"fixture@" + b"invalid.test"
        self.assertIn("email-address", categories(png(chunk(b"prIv", email))))
        self.assertEqual(categories(png() + email), {"email-address", "png-appended-data-review"})

    def test_content_credentials_metadata_is_not_blanket_ignored(self):
        email = b"fixture@" + b"invalid.test"
        self.assertEqual(categories(png(chunk(b"caBX", email))), {"email-address"})

    def test_bad_crc_is_reviewed_without_hiding_metadata(self):
        email = b"fixture@" + b"invalid.test"
        metadata = chunk(b"tEXt", b"Author\0" + email)
        damaged = metadata[:-1] + bytes([metadata[-1] ^ 1])
        self.assertEqual(categories(png(damaged)), {"email-address", "png-structure-review"})

    def test_truncation_and_invalid_signature_require_review(self):
        image = png(chunk(b"tEXt", b"Author\0public fixture"))
        for length in range(4, len(image)):
            with self.subTest(length=length):
                self.assertIn("png-structure-review", categories(image[:length], path="fixture.png"))
        self.assertIn("png-structure-review", categories(b"broken PNG", path="fixture.png"))

    def test_malformed_compressed_and_international_text_require_review(self):
        for kind, payload in [(b"zTXt", b"Comment\0\0not-zlib"),
                              (b"zTXt", b"Comment\0\1" + zlib.compress(b"text")),
                              (b"iTXt", b"Comment\0\1\0en\0Comment\0broken"),
                              (b"iTXt", b"Comment\0\0\0en\0Comment\0\xff"),
                              (b"tEXt", b"missing-null-separator")]:
            with self.subTest(kind=kind, payload=payload):
                self.assertIn("png-metadata-review", categories(png(chunk(kind, payload))))

    def test_oversized_or_trailing_zlib_metadata_requires_review(self):
        for compressed in [zlib.compress(b"a" * (audit.PNG_METADATA_LIMIT + 1)),
                           zlib.compress(b"text")[:-1],
                           zlib.compress(b"text") + b"trailing"]:
            with self.subTest(bytes=len(compressed)):
                self.assertIn("png-metadata-review", categories(png(chunk(b"zTXt", b"Comment\0\0" + compressed))))

    def test_exact_match_survives_malformed_png(self):
        value = b"synthetic-private-png-marker"
        found = categories(audit.PNG_SIGNATURE + b"broken " + value, [value])
        self.assertIn("known-private-value", found)
        self.assertIn("png-structure-review", found)


if __name__ == "__main__":
    unittest.main()
