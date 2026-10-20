#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Read-only privacy checks for the working tree and every stored Git object.

Reports categories and locations, never matching values. This is a release
check, not proof that arbitrary personal data or secrets have been identified.
Local exact-value checks can be supplied in an ignored JSON file:
  [{"text": "private value"}, {"hex": "private bytes in hexadecimal"}]
Never commit that input file. No files or Git refs are changed by this script.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import zlib


EMAIL = re.compile(rb"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}", re.I)
HOME = re.compile(rb"(?:/Users/|/home/)(?!example(?:/|\b)|username(?:/|\b)|USER(?:/|\b))[A-Za-z0-9._-]+")
PRIVATE_KEY = re.compile(rb"-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----")
ASSIGNMENT = re.compile(
    rb"(?:password|api[_-]?key|auth[_-]?token|client[_-]?secret)\s*[:=]\s*[\"'][^\"'\r\n]{8,}[\"']", re.I
)
REMOTE_URL_AUTH = re.compile(rb"https?://[^\s/@:]+:[^\s/@]+@", re.I)
PRIVATE_DIRS = {"private", "artifacts", "decompiled", ".build", "build"}
PRIVATE_EXTENSIONS = {".apk", ".aab", ".dll", ".exe", ".so", ".p12", ".pfx", ".key", ".pem", ".mobileprovision"}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PNG_METADATA_LIMIT = 4 * 1024 * 1024


def git(root: Path, *args: str) -> bytes:
    return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.PIPE)


def safe_location(value: str, known: list[bytes]) -> str:
    """A filename can itself contain a private value."""
    encoded = value.encode()
    for pattern in known:
        encoded = encoded.replace(pattern, b"[redacted-private]")
    value = EMAIL.sub(b"[redacted-email]", encoded).decode(errors="replace")
    value = HOME.sub(b"[redacted-home]", value.encode()).decode(errors="replace")
    return re.sub(r"(?<![A-Za-z0-9])[0-9]{7,12}(?![A-Za-z0-9])", "[redacted-number]", value)


def private_patterns(path: Path | None) -> list[bytes]:
    if path is None:
        return []
    try:
        entries = json.loads(path.read_text())
        if not isinstance(entries, list):
            raise ValueError
        values = []
        for entry in entries:
            if not isinstance(entry, dict) or len(entry) != 1:
                raise ValueError
            if "text" in entry and isinstance(entry["text"], str):
                value = entry["text"].encode()
            elif "hex" in entry and isinstance(entry["hex"], str):
                value = bytes.fromhex(entry["hex"])
            else:
                raise ValueError
            if len(value) < 4:
                raise ValueError
            values.append(value)
        return list(dict.fromkeys(values))
    except (OSError, ValueError, TypeError):
        # A JSON exception can quote an input value; intentionally omit it.
        raise SystemExit("Invalid private-pattern input; expected a JSON list of text/hex objects, each at least four bytes.")


def scan_plain_bytes(data: bytes, known: list[bytes]) -> list[tuple[str, int]]:
    found = []
    for category, pattern in [("personal-home-path", HOME), ("private-key", PRIVATE_KEY),
                              ("credential-literal", ASSIGNMENT), ("credential-in-url", REMOTE_URL_AUTH)]:
        for match in pattern.finditer(data):
            found.append((category, data.count(b"\n", 0, match.start()) + 1))
    for match in EMAIL.finditer(data):
        domain = match.group().rsplit(b"@", 1)[1].lower()
        if domain not in {b"example.com", b"example.org", b"example.invalid", b"test.invalid"}:
            found.append(("email-address", data.count(b"\n", 0, match.start()) + 1))
    for value in known:
        offset = data.find(value)
        if offset >= 0:
            found.append(("known-private-value", data.count(b"\n", 0, offset) + 1))
    return sorted(set(found))


def inflate_png_metadata(data: bytes, limit: int) -> bytes:
    """Bound decompression and reject truncated/concatenated zlib streams."""
    decoder = zlib.decompressobj()
    result = decoder.decompress(data, limit + 1)
    if len(result) > limit or decoder.unconsumed_tail or not decoder.eof or decoder.unused_data:
        raise ValueError("Incomplete or oversized compressed PNG metadata")
    return result


def png_metadata(data: bytes) -> tuple[list[tuple[bytes, int]], list[tuple[str, int]]]:
    """Return non-pixel byte segments and review flags, anchored in the PNG.

    This inspects chunk structure and textual metadata, not decoded image
    pixels. Exact private-value matching is performed separately on the entire
    original file. Segment offsets anchor decoded text to its original chunk.
    PNG layout: https://www.w3.org/TR/png-3/#11textinfo
    """
    segments: list[tuple[bytes, int]] = []
    reviews: list[tuple[str, int]] = []
    if not data.startswith(PNG_SIGNATURE):
        return [(data, 0)], [("png-structure-review", 0)]
    offset, chunks, remaining = len(PNG_SIGNATURE), 0, PNG_METADATA_LIMIT
    saw_header = saw_pixels = saw_end = past_pixels = False
    while offset < len(data):
        chunks += 1
        if chunks > 10_000 or len(data) - offset < 12:
            reviews.append(("png-structure-review", offset))
            segments.append((data[offset:], offset))
            break
        size = int.from_bytes(data[offset:offset + 4], "big")
        kind = data[offset + 4:offset + 8]
        end = offset + 12 + size
        if size > 0x7FFFFFFF or end > len(data):
            reviews.append(("png-structure-review", offset))
            segments.append((data[offset:], offset))
            break
        payload = data[offset + 8:end - 4]
        expected_crc = int.from_bytes(data[end - 4:end], "big")
        if (not re.fullmatch(rb"[A-Za-z]{4}", kind) or kind[2] & 0x20
                or zlib.crc32(kind + payload) != expected_crc):
            reviews.append(("png-structure-review", offset))
        if chunks == 1 and kind != b"IHDR":
            reviews.append(("png-structure-review", offset))
        if kind == b"IHDR":
            if saw_header or chunks != 1 or len(payload) != 13:
                reviews.append(("png-structure-review", offset))
            elif (not int.from_bytes(payload[:4], "big") or not int.from_bytes(payload[4:8], "big")
                  or payload[8] not in {0: (1, 2, 4, 8, 16), 2: (8, 16), 3: (1, 2, 4, 8),
                                       4: (8, 16), 6: (8, 16)}.get(payload[9], ())
                  or payload[10:12] != b"\0\0" or payload[12] not in (0, 1)):
                reviews.append(("png-structure-review", offset))
            saw_header = True
        if kind == b"IDAT":
            if not saw_header or past_pixels:
                reviews.append(("png-structure-review", offset))
            saw_pixels = True
            # Compressed image samples are not prose. Do not inflate or run
            # heuristics for email addresses, home directories or credentials here.
        elif kind == b"fdAT":
            if len(payload) < 4 or not saw_pixels:
                reviews.append(("png-structure-review", offset))
            # APNG frame data is also compressed pixel content. Its sequence
            # number remains covered by the whole-file exact-value check.
        else:
            if saw_pixels:
                past_pixels = True
            if kind in {b"zTXt", b"iTXt", b"iCCP", b"tEXt"}:
                try:
                    keyword, separator, rest = payload.partition(b"\0")
                    if (not separator or not 1 <= len(keyword) <= 79 or keyword.startswith(b" ")
                            or keyword.endswith(b" ") or b"  " in keyword
                            or any(not (32 <= byte <= 126 or 161 <= byte <= 255) for byte in keyword)):
                        raise ValueError("Invalid PNG metadata keyword")
                    segments.append((keyword, offset))
                    if kind == b"tEXt":
                        if b"\0" in rest:
                            reviews.append(("png-metadata-review", offset))
                        segments.append((rest, offset))
                    elif kind in {b"zTXt", b"iCCP"}:
                        if not rest or rest[0] != 0:
                            raise ValueError("Unsupported PNG metadata compression")
                        decoded = inflate_png_metadata(rest[1:], remaining)
                        remaining -= len(decoded)
                        segments.append((decoded, offset))
                    else:
                        if len(rest) < 2 or rest[0] not in (0, 1) or rest[1] != 0:
                            raise ValueError("Unsupported PNG text compression")
                        language, translated, text = rest[2:].split(b"\0", 2)
                        segments.extend([(language, offset), (translated, offset)])
                        if rest[0]:
                            text = inflate_png_metadata(text, remaining)
                            remaining -= len(text)
                        segments.append((text, offset))
                        language.decode("ascii")
                        translated.decode("utf-8")
                        text.decode("utf-8")
                except (ValueError, UnicodeError, zlib.error):
                    # Preserve a review flag even if malformed compressed
                    # content cannot be read; inspect its remaining raw bytes.
                    reviews.append(("png-metadata-review", offset))
                    segments.append((payload, offset))
            else:
                # EXIF, private ancillary chunks and other non-pixel content
                # can carry identifying strings even without a text chunk.
                segments.append((payload, offset))
                if kind not in {b"IHDR", b"PLTE", b"IEND"} and not kind[0] & 0x20:
                    reviews.append(("png-structure-review", offset))
        if kind == b"IEND":
            saw_end = True
            if payload or not saw_header or not saw_pixels:
                reviews.append(("png-structure-review", offset))
            if end < len(data):
                segments.append((data[end:], end))
                reviews.append(("png-appended-data-review", end))
            break
        offset = end
    if not saw_end:
        reviews.append(("png-structure-review", min(offset, len(data))))
    return segments, reviews


def scan_bytes(data: bytes, known: list[bytes], *, path: str | None = None) -> list[tuple[str, int]]:
    png = data.startswith(PNG_SIGNATURE[:4]) or path is not None and Path(path).suffix.lower() == ".png"
    if not png:
        return scan_plain_bytes(data, known)
    found = []
    # Exact supplied patterns always apply to the original complete binary,
    # including IDAT/fdAT, chunk headers, checksums and malformed/trailing data.
    for value in known:
        offset = data.find(value)
        if offset >= 0:
            found.append(("known-private-value", data.count(b"\n", 0, offset) + 1))
    segments, reviews = png_metadata(data)
    for segment, offset in segments:
        for category, _ in scan_plain_bytes(segment, known):
            found.append((category, data.count(b"\n", 0, offset) + 1))
    for category, offset in reviews:
        found.append((category, data.count(b"\n", 0, offset) + 1))
    return sorted(set(found))


def sensitive_path(path: str) -> bool:
    parts = PurePosixPath(path).parts
    return bool(parts and (parts[0] in PRIVATE_DIRS
                           or any(part == ".env" or part.startswith(".env.") for part in parts)
                           or PurePosixPath(path).suffix.lower() in PRIVATE_EXTENSIONS))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--private-pattern-file", type=Path)
    parser.add_argument("--allow-identity", action="append", default=[], metavar="NAME <EMAIL>",
                        help="Explicitly approved public author/committer/tagger identity; repeat as needed.")
    parser.add_argument("--json", action="store_true", help="Emit the redacted report as JSON.")
    args = parser.parse_args()
    root = args.root.resolve()
    known = private_patterns(args.private_pattern_file)
    allowed = {value.encode() for value in args.allow_identity}
    findings: set[tuple[str, str, int | None, str | None]] = set()
    counts: Counter[str] = Counter()

    def add(category: str, location: str, line: int | None = None, oid: str | None = None):
        findings.add((category, safe_location(location, known), line, oid))

    # Read working files, including new non-ignored files not yet staged.
    for raw in git(root, "ls-files", "--cached", "--others", "--exclude-standard", "-z").split(b"\0"):
        if not raw:
            continue
        path = raw.decode(errors="replace")
        full = root / path
        if sensitive_path(path):
            add("private-or-vendor-file", path)
        if full.is_symlink():
            add("symlink-review", path)
            continue
        if not full.is_file():
            continue
        counts["working_files"] += 1
        for category, line in scan_bytes(full.read_bytes(), known, path=path):
            add(category, path, line)

    # Path attribution covers all refs, including remote/backup refs and tags.
    object_paths: dict[str, set[str]] = defaultdict(set)
    commits = git(root, "rev-list", "--all").decode().splitlines()
    counts["reachable_commits"] = len(commits)
    for commit in commits:
        for record in git(root, "ls-tree", "-rz", "--full-tree", commit).split(b"\0"):
            if not record:
                continue
            meta, raw = record.split(b"\t", 1)
            _, kind, oid = meta.split()
            if kind == b"blob":
                path = raw.decode(errors="replace")
                object_paths[oid.decode()].add(path)
                if sensitive_path(path):
                    add("historical-private-or-vendor-file", path, oid=oid.decode())

    # Unlike rev-list alone, this also checks dangling objects and old objects
    # retained after a rewrite. Reflog expiry/garbage collection is a separate,
    # deliberate operation and is never performed here.
    objects = git(root, "cat-file", "--batch-all-objects", "--batch-check=%(objectname) %(objecttype)")
    for record in objects.decode().splitlines():
        oid, kind = record.split()
        counts[f"stored_{kind}_objects"] += 1
        if kind not in {"blob", "commit", "tag"}:
            continue
        data = git(root, "cat-file", kind, oid)
        if kind == "blob":
            locations = sorted(object_paths.get(oid, {"<unreachable-or-unattributed-blob>"}))
            hint = next((location for location in locations if Path(location).suffix.lower() == ".png"), None)
            for category, line in scan_bytes(data, known, path=hint):
                for location in locations:
                    add(category, location, line, oid)
            continue
        location = f"<{kind}-metadata>"
        # Names and email addresses can exist in signatures even after editing
        # the author fields. All commit/tag signatures receive a separate flag.
        if (b"gpgsig " in data or b"-----BEGIN PGP SIGNATURE-----" in data
                or b"-----BEGIN SSH SIGNATURE-----" in data):
            add("embedded-signature", location, oid=oid)
        for match in re.finditer(rb"^(?:author|committer|tagger) (.+?) [0-9]+ [+-][0-9]{4}$", data, re.M):
            if match.group(1) not in allowed:
                add("unapproved-contributor-identity", location, oid=oid)
        for category, line in scan_bytes(data, known):
            # An allowed, intentionally public contributor email need not be
            # independently flagged by this otherwise identity-agnostic check.
            if category == "email-address" and any(value in data.splitlines()[line - 1] for value in allowed):
                continue
            add(category, location, line, oid)

    # A local credential in a Git remote is not a committed blob but can leak
    # with a copied .git directory, so inspect configuration without printing it.
    for line in git(root, "config", "--get-regexp", r"^remote\..*\.url$").splitlines() if git(root, "remote").strip() else []:
        if REMOTE_URL_AUTH.search(line):
            add("credential-in-remote-url", "<local-git-config>")

    ordered = sorted(findings, key=lambda item: (item[0], item[1], item[2] or 0, item[3] or ""))
    report = {"counts": dict(sorted(counts.items())), "private_patterns_loaded": len(known),
              "findings": [{"category": category, "location": location,
                            **({"line": line} if line is not None else {}),
                            **({"object": oid} if oid else {})}
                           for category, location, line, oid in ordered]}
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print("Public-source privacy audit (read only; matching values suppressed)")
        for key, value in report["counts"].items():
            print(f"  {key}: {value}")
        print(f"  private_patterns_loaded: {len(known)}")
        for item in report["findings"]:
            suffix = f":{item['line']}" if "line" in item else ""
            obj = f" [{item['object'][:12]}]" if "object" in item else ""
            print(f"  {item['category']}: {item['location']}{suffix}{obj}")
        print(f"Findings requiring review: {len(ordered)}")
    return 1 if findings else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError:
        # stderr and command arguments can contain a credential-bearing remote.
        print("Git inspection failed; no repository changes were made.", file=sys.stderr)
        raise SystemExit(2)
