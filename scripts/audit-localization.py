#!/usr/bin/env python3
"""Audit locale key/printf parity and report likely untranslated Swift UI text.

The Swift scanner is intentionally lexical, not a replacement for SwiftSyntax.
It skips comments and SF-symbol/identifier contexts, understands interpolated
strings, and reports review candidates instead of claiming semantic coverage.
No source files are modified. --strict also fails on unwrapped UI candidates.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

PRINTF = re.compile(r"%(?:(\d+)\$)?[-+ #0']*(\d*)(?:\.(\d*))?(hh|ll|[hljzt])?([@diuoxXcCfFeEgGaA%])")
STRING_ENTRY = re.compile(r'(?P<comment>//[^\n]*|/\*[\s\S]*?\*/)|"(?P<key>(?:\\.|[^"\\])*)"\s*=\s*"(?P<value>(?:\\.|[^"\\])*)"\s*;')
UI_CALL = re.compile(r"\b(?:Text|Label|Button|Toggle|Picker|GroupBox|LabeledContent|Section|TextField|SecureField|ContentUnavailableView|Window|MenuBarExtra|Menu|NavigationLink)\s*\([^;{}]*$", re.S)
UI_MODIFIER = re.compile(r"\.(?:help|navigationTitle|accessibilityLabel|accessibilityHint|accessibilityValue|alert|confirmationDialog)\s*\([^;{}]*$", re.S)
NONVISIBLE = re.compile(r"(?:\b(?:systemName|systemImage|id|identifier|forKey|forInfoDictionaryKey|suiteName|withExtension|ofType|characteristicUUID|serviceUUID|symbol|icon)\s*:|\.(?:accessibilityIdentifier|keyboardShortcut|id|appendingPathComponent|appendingPathExtension)\s*\(|\b(?:Image|Color|NSImage)\s*\()\s*$")


def signature(text: str) -> dict[int, str] | None:
    result: dict[int, str] = {}
    index, argument, positional = 0, 1, None
    while index < len(text):
        if text[index] != "%":
            index += 1
            continue
        match = PRINTF.match(text, index)
        if not match:
            return None
        position, width, precision, length, spec = match.groups()
        index = match.end()
        if spec == "%":
            if match.group() != "%%":
                return None
            continue
        if positional is not None and positional != bool(position):
            return None
        positional = bool(position)
        slot = int(position) if position else argument
        if not position:
            argument += 1
        if not 1 <= slot <= 64 or int(width or "0") > 1000 or int(precision or "0") > 12:
            return None
        length = length or ""
        if spec == "@" and length or spec in "fFeEgGaA" and length not in ("", "l") or spec in "cC" and length:
            return None
        conversion = length + spec
        if slot in result and result[slot] != conversion:
            return None
        result[slot] = conversion
    if result and set(result) != set(range(1, max(result) + 1)):
        return None
    return result


def read_strings(path: Path) -> tuple[dict[str, str], list[str]]:
    if not path.exists():
        return {}, [f"Missing catalog: {path}"]
    source, result, errors, previous = path.read_text(), {}, [], 0
    for match in STRING_ENTRY.finditer(source):
        if source[previous:match.start()].strip():
            errors.append(f"Invalid catalog syntax near offset {previous}: {path}")
        previous = match.end()
        if match.group("comment"):
            continue
        try:
            key = json.loads('"' + match.group("key") + '"')
            value = json.loads('"' + match.group("value") + '"')
        except ValueError as error:
            errors.append(f"Invalid catalog escaping: {path}: {error}")
            continue
        if key in result:
            errors.append(f"Duplicate key: {path}: {key!r}")
        result[key] = value
    if source[previous:].strip():
        errors.append(f"Invalid trailing catalog syntax: {path}")
    return result, errors


def decode_swift(text: str, raw: int) -> str:
    marker = "\\" + "#" * raw
    if raw:
        text = text.replace("\\", "\ue001").replace("\ue001" + "#" * raw, "\\")
    text = re.sub(r"\\u\{([0-9A-Fa-f]{1,8})\}", lambda match: chr(int(match[1], 16)), text)
    replacements = {"n": "\n", "r": "\r", "t": "\t", "0": "\0", '"': '"', "\\": "\\"}
    return re.sub(r"\\(.)", lambda match: replacements.get(match[1], match.group()), text).replace("\ue001", "\\")


def swift_literals(source: str) -> list[dict]:
    tokens: list[dict] = []

    def skip_comment(index: int) -> int:
        if source.startswith("//", index):
            end = source.find("\n", index)
            return len(source) if end < 0 else end
        if source.startswith("/*", index):
            depth, index = 1, index + 2
            while index < len(source) and depth:
                if source.startswith("/*", index):
                    depth += 1; index += 2
                elif source.startswith("*/", index):
                    depth -= 1; index += 2
                else:
                    index += 1
            return index
        return index

    def string_at(index: int) -> int | None:
        start, raw = index, 0
        while index < len(source) and source[index] == "#":
            raw += 1; index += 1
        if index >= len(source) or source[index] != '"':
            return None
        delimiter = '"""' if source.startswith('"""', index) else '"'
        close, marker = delimiter + "#" * raw, "\\" + "#" * raw
        index += len(delimiter)
        literal_start, parts, expressions = index, [], []
        while index < len(source):
            if source.startswith(close, index):
                tail = decode_swift(source[literal_start:index], raw)
                parts.append(tail.replace("%", "%%") if expressions else tail)
                text = "".join(parts)
                if expressions:
                    text = text.replace("\x01", "%@")
                context = source[max(0, start - 300):start]
                wrapped = bool(re.search(r"\bL\(\s*$", context) or re.search(r"\bLP\(\s*$", context)
                    or re.search(r'\bLP\(\s*"(?:\\.|[^"\\])*"\s*,\s*$', context))
                visible = bool(UI_CALL.search(context) or UI_MODIFIER.search(context)) and not NONVISIBLE.search(context)
                tokens.append({"offset": start, "end": index + len(close), "line": source.count("\n", 0, start) + 1,
                    "key": text, "expressions": expressions, "wrapped": wrapped,
                    "visible": visible, "context": context[-100:].strip()})
                return index + len(close)
            if source.startswith(marker + "(", index):
                piece = decode_swift(source[literal_start:index], raw).replace("%", "%%")
                parts.append(piece + "\x01")
                expression_start, depth = index + len(marker) + 1, 1
                cursor = expression_start
                while cursor < len(source) and depth:
                    comment = skip_comment(cursor)
                    if comment != cursor:
                        cursor = comment; continue
                    nested = string_at(cursor) if source[cursor] in '#"' else None
                    if nested is not None:
                        cursor = nested; continue
                    if source[cursor] == "(": depth += 1
                    if source[cursor] == ")": depth -= 1
                    cursor += 1
                expressions.append(source[expression_start:cursor - 1])
                index = literal_start = cursor
                continue
            if source.startswith(marker, index):
                index += len(marker) + 1
            else:
                index += 1
        return len(source)

    index = 0
    while index < len(source):
        comment = skip_comment(index)
        if comment != index:
            index = comment; continue
        end = string_at(index) if source[index] in '#"' else None
        index = end if end is not None else index + 1
    return sorted(tokens, key=lambda token: token["offset"])


def human_text(text: str) -> bool:
    if not text.strip() or text in ("Audifern", "Open Companion", "BrandMark", "HearingAid", "Hz", "NR", "↓ NR", "YYYY-MM-DD") or "\0" in text:
        return False
    if re.fullmatch(r"[0-9A-Fa-f-]{8,}", text) or re.match(r"^(?:https?://|file://|/Users/|[a-z-]+\.[a-z-]+$)", text):
        return False
    return bool(re.search(r"[A-Za-zÀ-ÿ]{2}", text)) and (" " in text or text[0].isupper())


def audit(root: Path) -> dict:
    candidates = sorted((root / "Sources").glob("*/Resources/en.lproj/Localizable.strings"))
    resources = candidates[0].parent.parent if candidates else root / "Sources/Resources"
    languages = sorted({path.name.removesuffix(".lproj") for path in resources.glob("*.lproj")} | {"en"})
    catalogs, errors = {}, []
    if len(candidates) != 1:
        errors.append("Expected exactly one app resource directory containing en.lproj/Localizable.strings")
    for language in languages:
        catalog, issues = read_strings(resources / f"{language}.lproj/Localizable.strings")
        catalogs[language] = catalog; errors.extend(issues)
    english = catalogs["en"]
    for language, catalog in catalogs.items():
        for key in english.keys() - catalog.keys(): errors.append(f"{language}: missing key {key!r}")
        for key in catalog.keys() - english.keys(): errors.append(f"{language}: extra key {key!r}")
        for key, value in catalog.items():
            if not value: errors.append(f"{language}: empty translation for {key!r}")
            if key in english and signature(english[key]) != signature(value):
                errors.append(f"{language}: printf arguments differ for {key!r}")
    inventory, hardcoded = [], []
    for path in sorted((root / "Sources").rglob("*.swift")):
        source = path.read_text()
        for token in swift_literals(source):
            token["file"] = str(path.relative_to(root))
            if token["wrapped"]:
                if token["expressions"]: errors.append(f"{token['file']}:{token['line']}: interpolated L key; use a format and arguments")
                elif token["key"] not in english: errors.append(f"{token['file']}:{token['line']}: missing L key {token['key']!r}")
            if human_text(token["key"]) or token["wrapped"]:
                inventory.append(token)
                if token["visible"] and not token["wrapped"]: hardcoded.append(token)
    return {"languages": {language: len(catalog) for language, catalog in catalogs.items()},
            "errors": sorted(set(errors)), "hardcoded_ui_candidates": hardcoded, "inventory": inventory}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--inventory", type=Path, help="Write source-string inventory and audit details as JSON")
    parser.add_argument("--strict", action="store_true", help="Also fail on likely hardcoded SwiftUI text")
    options = parser.parse_args()
    report = audit(options.root.resolve())
    if options.inventory:
        options.inventory.parent.mkdir(parents=True, exist_ok=True)
        options.inventory.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print("Catalog keys: " + ", ".join(f"{language}={count}" for language, count in report["languages"].items()))
    print(f"Catalog/reference errors: {len(report['errors'])}; likely hardcoded UI strings: {len(report['hardcoded_ui_candidates'])}")
    for issue in report["errors"][:40]: print(issue, file=sys.stderr)
    if options.strict:
        for token in report["hardcoded_ui_candidates"][:40]:
            print(f"{token['file']}:{token['line']}: review {token['key']!r}", file=sys.stderr)
    return int(bool(report["errors"] or options.strict and report["hardcoded_ui_candidates"]))


if __name__ == "__main__":
    raise SystemExit(main())
