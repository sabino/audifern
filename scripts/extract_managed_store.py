#!/usr/bin/env python3
"""Extract .NET Android v3 assembly stores without loading target code.

Format references (upstream dotnet/android):
  Documentation/project-docs/AssemblyStores.md
  Documentation/project-docs/ApkSharedLibraries.md
Supports this investigation's little-endian ELF64 carrier and raw LZ4 XALZ
blocks. Output is proprietary analysis material: use an ignored private path.
"""

import argparse
import hashlib
import json
import pathlib
import struct
import zipfile

MAX_IMAGE = 128 * 1024 * 1024


def read_at(data, offset, length):
    if offset < 0 or length < 0 or offset + length > len(data):
        raise ValueError(f"Out-of-bounds range {offset}:{offset + length}")
    return data[offset:offset + length]


def payload_from_elf(data):
    if data[:6] != b"\x7fELF\x02\x01":
        raise ValueError("Expected little-endian ELF64 carrier")
    section_offset = struct.unpack_from("<Q", data, 40)[0]
    entry_size, count, names_index = struct.unpack_from("<3H", data, 58)
    if entry_size != 64 or not 0 < count <= 1024 or names_index >= count:
        raise ValueError("Unsupported ELF section table")
    sections = [struct.unpack("<IIQQQQIIQQ", read_at(data, section_offset + i * entry_size, 64))
                for i in range(count)]
    name_section = sections[names_index]
    names = read_at(data, name_section[4], name_section[5])
    matches = [section for section in sections
               if read_at(names, section[0], len(names) - section[0]).split(b"\0", 1)[0] == b"payload"]
    if len(matches) != 1:
        raise ValueError("Expected exactly one payload section")
    section = matches[0]
    return read_at(data, section[4], section[5]), section[4]


def decode_lz4_block(data, expected):
    """Bounded raw LZ4 decoder, no native dependency or target execution."""
    if not 0 < expected <= MAX_IMAGE:
        raise ValueError("Unreasonable decompressed image size")
    result = bytearray()
    cursor = 0

    def length(initial):
        nonlocal cursor
        value = initial
        if initial == 15:
            while True:
                extra = read_at(data, cursor, 1)[0]
                cursor += 1
                value += extra
                if extra != 255:
                    break
        return value

    while cursor < len(data):
        token = data[cursor]
        cursor += 1
        literal_count = length(token >> 4)
        if len(result) + literal_count > expected:
            raise ValueError("LZ4 literal exceeds declared output")
        result.extend(read_at(data, cursor, literal_count))
        cursor += literal_count
        if cursor == len(data):
            break
        distance = struct.unpack("<H", read_at(data, cursor, 2))[0]
        cursor += 2
        match_count = length(token & 15) + 4
        if distance == 0 or distance > len(result) or len(result) + match_count > expected:
            raise ValueError("Invalid LZ4 back reference")
        # LZ4 permits overlap; copying the growing buffer preserves its semantics.
        for _ in range(match_count):
            result.append(result[-distance])
    if len(result) != expected:
        raise ValueError(f"LZ4 length mismatch: {len(result)} != {expected}")
    return bytes(result)


def extract(carrier, output):
    payload, payload_offset = payload_from_elf(carrier)
    magic, version, count, index_count, index_size = struct.unpack("<5I", read_at(payload, 0, 20))
    if magic != 0x41424158 or version & 0xffff != 3:
        raise ValueError("Expected XABA store format v3")
    if not 0 < count <= 10000 or index_count > count * 2 or index_size > count * 32:
        raise ValueError("Unreasonable assembly store header")
    descriptor_offset = 20 + index_size
    descriptors = [struct.unpack("<7I", read_at(payload, descriptor_offset + i * 28, 28))
                   for i in range(count)]
    cursor = descriptor_offset + count * 28
    names = []
    for _ in range(count):
        size = struct.unpack("<I", read_at(payload, cursor, 4))[0]
        cursor += 4
        name = read_at(payload, cursor, size).rstrip(b"\0").decode("utf-8")
        cursor += size
        path = pathlib.PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or "\\" in name or not name.endswith(".dll"):
            raise ValueError(f"Unsafe assembly name: {name!r}")
        names.append(name)
    if len(set(names)) != count:
        raise ValueError("Duplicate assembly names")
    if output.exists() and any(output.iterdir()):
        raise ValueError("Output directory must be new or empty")
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    manifest = {"carrier_sha256": hashlib.sha256(carrier).hexdigest(),
                "payload_file_offset": payload_offset, "version": f"0x{version:08x}",
                "entry_count": count, "assemblies": []}
    for name, descriptor in zip(names, descriptors):
        mapping_index, offset, size, *_ = descriptor
        packed = read_at(payload, offset, size)
        compressed = packed.startswith(b"XALZ")
        if compressed:
            _, compressed_index, expected = struct.unpack("<3I", read_at(packed, 0, 12))
            image = decode_lz4_block(packed[12:], expected)
        else:
            compressed_index = None
            image = packed
        if not image.startswith(b"MZ"):
            raise ValueError(f"Not a PE image: {name}")
        path = output / name
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        path.write_bytes(image)
        manifest["assemblies"].append({"name": name, "mapping_index": mapping_index,
            "data_offset": offset, "packed_size": size, "compressed": compressed,
            "compressed_index": compressed_index, "image_size": len(image),
            "sha256": hashlib.sha256(image).hexdigest()})
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=pathlib.Path, help="APK or extracted libassembly-store.so")
    parser.add_argument("output", type=pathlib.Path, help="New or empty private output directory")
    parser.add_argument("--member", default="lib/arm64-v8a/libassembly-store.so")
    args = parser.parse_args()
    if zipfile.is_zipfile(args.input):
        with zipfile.ZipFile(args.input) as archive:
            carrier = archive.read(args.member)
    else:
        carrier = args.input.read_bytes()
    manifest = extract(carrier, args.output)
    print(f"Extracted {manifest['entry_count']} assemblies; carrier SHA-256 {manifest['carrier_sha256']}")


if __name__ == "__main__":
    main()
