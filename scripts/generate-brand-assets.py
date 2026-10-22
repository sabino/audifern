#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Export the canonical SVG; checking committed exports needs only Python."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = "branding/mark.svg"
RASTER = "Sources/Audifern/Resources/BrandMark.png"
MONO = "branding/mark-mono.svg"
MANIFEST = "branding/derived-assets.json"
PIXELS = 2048
NS = "{http://www.w3.org/2000/svg}"


def digest(path: str) -> str:
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def check() -> None:
    data = json.loads((ROOT / MANIFEST).read_text())
    if (data["formatVersion"] != 1 or data["source"] != SOURCE
            or data["sourceSHA256"] != digest(SOURCE) or data["rasterPixels"] != PIXELS
            or set(data["outputs"]) != {RASTER, MONO}
            or any(data["outputs"][path] != digest(path) for path in [RASTER, MONO])):
        raise ValueError("Stale brand export")
    png = (ROOT / RASTER).read_bytes()
    if (png[:8] != b"\x89PNG\r\n\x1a\n" or png[12:16] != b"IHDR"
            or int.from_bytes(png[16:20], "big") != PIXELS
            or int.from_bytes(png[20:24], "big") != PIXELS or png[25] != 6):
        raise ValueError("Expected a transparent RGBA brand export")
    original, mono = (ET.parse(ROOT / path).getroot() for path in [SOURCE, MONO])
    if (original.attrib["viewBox"] != mono.attrib["viewBox"]
            or [path.attrib["d"] for path in original.iter(NS + "path")]
            != [path.attrib["d"] for path in mono.iter(NS + "path")]):
        raise ValueError("Monochrome geometry differs from the canonical mark")
    print("Brand assets match the canonical branding/mark.svg export.")


def generate() -> None:
    renderer = shutil.which("rsvg-convert")
    if renderer is None:
        raise ValueError("Install librsvg's rsvg-convert to regenerate brand assets")
    with tempfile.TemporaryDirectory(prefix="audifern-brand-") as folder:
        rendered = Path(folder) / "mark.png"
        subprocess.run([renderer, "--format=png", f"--width={PIXELS}", f"--height={PIXELS}",
                        "--output", str(rendered), str(ROOT / SOURCE)], check=True)
        (ROOT / RASTER).write_bytes(rendered.read_bytes())
    ET.register_namespace("", NS[1:-1])
    mono = ET.parse(ROOT / SOURCE)
    root = mono.getroot()
    for child in list(root):
        if child.tag == NS + "defs":
            root.remove(child)
    for element in root.iter():
        for attribute in ["fill", "stroke"]:
            if attribute in element.attrib and element.attrib[attribute] != "none":
                element.set(attribute, "currentColor")
        if element.tag == NS + "desc":
            element.text = "Monochrome derivative of the canonical Audifern mark."
    ET.indent(mono, space="  ")
    (ROOT / MONO).write_text(ET.tostring(root, encoding="unicode") + "\n")
    version = subprocess.check_output([renderer, "--version"], text=True).splitlines()[0]
    data = {"formatVersion": 1, "source": SOURCE, "sourceSHA256": digest(SOURCE),
            "rasterPixels": PIXELS, "renderer": version,
            "outputs": {path: digest(path) for path in [RASTER, MONO]}}
    (ROOT / MANIFEST).write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    check()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate committed exports without a renderer")
    args = parser.parse_args()
    try:
        check() if args.check else generate()
    except (OSError, KeyError, ValueError, ET.ParseError, subprocess.CalledProcessError) as error:
        raise SystemExit("Brand asset check failed. Run python3 scripts/generate-brand-assets.py after editing branding/mark.svg. " + str(error)) from None
