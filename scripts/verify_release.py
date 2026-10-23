#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Verify notarized release downloads independently, including their extracted apps."""
from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
from pathlib import Path
import re
import subprocess
import tempfile

import apple_tickets
import release_metadata as metadata
import sparkle_appcast


def verify_downloads(directory: Path, tag: str = "") -> dict:
    version = metadata.release_version(metadata.version(), tag)
    prefix = f"Audifern-{version}-macos-universal"
    expected = {prefix + ".dmg", prefix + ".zip", "build-info.json", "SHA256SUMS"}
    if (directory / 'appcast.xml').exists(): expected.add('appcast.xml')
    paths = list(directory.iterdir())
    if {path.name for path in paths} != expected or any(not path.is_file() or path.is_symlink() for path in paths):
        raise ValueError("Release downloads must contain exactly a regular DMG, ZIP, manifest and checksums.")
    checksums = {}
    for line in (directory / "SHA256SUMS").read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9._-]+)", line)
        if not match or match[2] in checksums:
            raise ValueError("Invalid or duplicate release checksum entry.")
        checksums[match[2]] = match[1]
    if checksums.keys() != expected - {"SHA256SUMS"}:
        raise ValueError("The checksums do not cover exactly the release assets.")
    for name, expected_hash in checksums.items():
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != expected_hash:
            raise ValueError("A downloaded release asset failed its checksum.")
    data = json.loads((directory / "build-info.json").read_text())
    required = {"application": "Audifern", "version": metadata.version(), "releaseVersion": version,
                "sourceCommit": metadata.source_commit(), "sourceRepository": metadata.REPOSITORY,
                "minimumMacOS": "14.0", "architectures": ["arm64", "x86_64"],
                "signing": "developer-id", "notarized": True, "hardenedRuntime": True, "secureTimestamp": True}
    if not required["sourceCommit"]:
        raise ValueError("Verify official releases from a checkout of their exact source commit.")
    if any(data.get(key) != value for key, value in required.items()):
        raise ValueError("Release provenance, architecture or notarization metadata does not match this checkout.")
    if not re.fullmatch(r"[A-Z0-9]{10}", data.get("teamID", "")):
        raise ValueError("The signing team is missing.")
    return data


def verify_release(directory: Path, tag: str, team: str, *, require_feed: bool = False) -> dict:
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("Provide the expected public Apple developer team ID.")
    data = verify_downloads(directory, tag)
    if data["teamID"] != team:
        raise ValueError("The release manifest identifies a different signing team.")
    if require_feed and plistlib.loads((metadata.ROOT / 'Resources/Info.plist').read_bytes()).get('SUPublicEDKey'):
        sparkle_appcast.verify(directory, metadata.ROOT)
    prefix = f"Audifern-{data['releaseVersion']}-macos-universal"
    dmg = directory / (prefix + ".dmg")
    subprocess.run(["hdiutil", "verify", "-quiet", str(dmg)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(dmg)], check=True)
    apple_tickets.run("validate", dmg, "dmg")
    subprocess.run(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4", str(dmg)], check=True)
    with tempfile.TemporaryDirectory(prefix="audifern-verify-") as folder:
        staging = Path(folder)
        mounted = staging / "mounted"
        mounted.mkdir()
        attached = False
        try:
            subprocess.run(["hdiutil", "attach", "-quiet", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", str(mounted), str(dmg)], check=True)
            attached = True
            if (mounted / "Applications").readlink() != Path("/Applications"):
                raise ValueError("The DMG installation link differs from /Applications.")
            _verify_app(mounted / "Audifern.app", team)
        finally:
            if attached:
                subprocess.run(["hdiutil", "detach", "-quiet", str(mounted)], check=True)
        extracted = staging / "unzipped"
        subprocess.run(["ditto", "-x", "-k", str(directory / (prefix + ".zip")), str(extracted)], check=True)
        _verify_app(extracted / "Audifern.app", team)
    print("Verified all release hashes, Developer ID signatures, stapled Apple tickets and Gatekeeper acceptance.", flush=True)
    return data


def _verify_app(app: Path, team: str) -> None:
    metadata.verify_app(app, "universal")
    metadata.verify_notarization(app, team)
    executable = app / "Contents/MacOS/Audifern"
    for architecture in ["arm64", "x86_64"]:
        commands = subprocess.check_output(["otool", "-arch", architecture, "-l", str(executable)], text=True)
        if re.findall(r"^\s*minos (\S+)", commands, re.MULTILINE) != ["14.0"]:
            raise ValueError("A Mach-O slice requires a different macOS version.")
    commit = metadata.source_commit()
    source = (app / "Contents/Resources/SOURCE.txt").read_text()
    if "Exact source: " + metadata.REPOSITORY + "/tree/" + str(commit) not in source:
        raise ValueError("The app's bundled source notice differs from the release commit.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--project", type=Path, default=metadata.ROOT,
                        help="Validated application source checkout whose provenance must match.")
    parser.add_argument("--tag", default="")
    parser.add_argument("--team", required=True, help="Expected public Apple developer team ID.")
    args = parser.parse_args()
    metadata.ROOT = args.project.resolve()
    verify_release(args.directory.resolve(), args.tag, args.team, require_feed=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from None
