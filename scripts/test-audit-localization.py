#!/usr/bin/env python3
"""Small parser regressions; no Swift build, Bluetooth, or network access."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("localization_audit", Path(__file__).with_name("audit-localization.py"))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class AuditTests(unittest.TestCase):
    def test_positional_arguments_preserve_identity_not_text_order(self):
        self.assertEqual(audit.signature("%ld %@ %.1f"), audit.signature("%2$@ %3$.1f %1$ld"))
        self.assertNotEqual(audit.signature("%ld"), audit.signature("%d"))
        for value in ("%n", "%s", "%l@", "%llf", "%*d", "%1$@ %@", "%2$@"):
            self.assertIsNone(audit.signature(value))

    def test_interpolation_keeps_bindings_and_escapes_literal_percent(self):
        values = audit.swift_literals('Text("Battery \\(level)%")')
        self.assertEqual(values[0]["key"], "Battery %@%%")
        self.assertEqual(values[0]["expressions"], ["level"])
        self.assertTrue(values[0]["visible"])

    def test_nested_strings_comments_and_symbols(self):
        source = '// Text("Ignored")\nText(L("Connect"))\nLabel("Ready", systemImage: "ear")\n'
        values = audit.swift_literals(source)
        self.assertEqual([value["key"] for value in values], ["Connect", "Ready", "ear"])
        self.assertTrue(values[0]["wrapped"])
        self.assertFalse(values[2]["visible"])
        nested = audit.swift_literals('Text("State \\(name ?? "Unknown")")')
        self.assertEqual({value["key"] for value in nested}, {"Unknown", "State %@"})

    def test_raw_strings_only_decode_hash_escaped_sequences(self):
        values = audit.swift_literals(r'Text(#"Literal \n and \#(name)"#)')
        self.assertEqual(values[0]["key"], r"Literal \n and %@")
        self.assertEqual(values[0]["expressions"], ["name"])

    def test_strings_parser_preserves_urls_and_reports_duplicates(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Localizable.strings"
            path.write_text('/* Header */\n"URL" = "https://example.test";\n"URL" = "Again";\n')
            values, errors = audit.read_strings(path)
            self.assertEqual(values, {"URL": "Again"})
            self.assertEqual(len(errors), 1)
            self.assertIn("Duplicate key", errors[0])


if __name__ == "__main__":
    unittest.main()
