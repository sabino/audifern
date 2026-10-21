#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Version gates and payload validation for public macOS downloads."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
VERSION = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
TAG = re.compile(r"v(?P<version>" + VERSION + r")(?:-(?P<pre>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?")
REPOSITORY = "https://github.com/sabino/audifern"
SIGNATURE_FILES = {"CodeResources", "CodeDirectory", "CodeRequirements", "CodeSignature"}
RESOURCES = {"BrandMark.png", "HearingAid.png", "en.lproj/Localizable.strings",
             "pt-BR.lproj/Localizable.strings", "es.lproj/Localizable.strings"}


def version() -> str:
    value = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
    if not isinstance(value, str) or not re.fullmatch(VERSION, value):
        raise ValueError("The application version must be MAJOR.MINOR.PATCH.")
    return value


def release_version(app_version: str, tag: str = "") -> str:
    if not re.fullmatch(VERSION, app_version):
        raise ValueError("Invalid application version.")
    if not tag:
        return app_version
    match = TAG.fullmatch(tag)
    if not match or match["version"] != app_version:
        raise ValueError("The tag must be vMAJOR.MINOR.PATCH and match Info.plist (an optional prerelease suffix is allowed).")
    if match["pre"] and any(part.isdecimal() and len(part) > 1 and part[0] == "0" for part in match["pre"].split(".")):
        raise ValueError("Numeric prerelease identifiers cannot contain leading zeroes.")
    return tag[1:]


def source_commit() -> str | None:
    try:
        top = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], cwd=ROOT, stderr=subprocess.DEVNULL).decode().strip()
        if Path(top).resolve() != ROOT:
            return None
        commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip()
        return commit if re.fullmatch(r"[0-9a-f]{40,64}", commit) else None
    except subprocess.CalledProcessError:
        return None


def expected_architectures(selection: str) -> set[str]:
    if selection == "native": selection = platform.machine()
    if selection == "universal": return {"arm64", "x86_64"}
    if selection in {"arm64", "x86_64"}: return {selection}
    raise ValueError("Unsupported build architecture.")


def vet_payload(app: Path) -> None:
    fixed = {"Contents/Info.plist", "Contents/MacOS/Audifern", "Contents/Resources/Audifern.icns",
             "Contents/Resources/LICENSE.txt", "Contents/Resources/THIRD_PARTY_NOTICES.md", "Contents/Resources/SOURCE.txt"}
    bundle = "Contents/Resources/Audifern_Audifern.bundle/"
    # SwiftPM's native and Xcode build systems use flat and Contents layouts.
    if (app / bundle / "Contents").is_dir():
        bundle += "Contents/"
        resources = bundle + "Resources/"
    else:
        resources = bundle
    names = set(RESOURCES)
    if "pt-BR.lproj" not in {path.name for path in (app / resources).glob("*.lproj")}:
        names.remove("pt-BR.lproj/Localizable.strings")
        names.add("pt-br.lproj/Localizable.strings")
    required = fixed | {bundle + "Info.plist"} | {resources + name for name in names}
    allowed = set(required)
    for prefix in ["Contents/_CodeSignature/", bundle + "_CodeSignature/"]:
        allowed.update(prefix + name for name in SIGNATURE_FILES)
    if app.is_symlink() or not app.is_dir(): raise ValueError("Expected a regular app bundle.")
    present = set()
    for path in app.rglob("*"):
        if path.is_symlink(): raise ValueError("Unexpected symlink in the application payload.")
        if path.is_file():
            name = path.relative_to(app).as_posix()
            if name not in allowed: raise ValueError("Unexpected file in the application payload; review packaging inputs.")
            present.add(name)
    if not required <= present: raise ValueError("The app is missing artwork, localizations, license or source notices.")


def verify_app(app: Path, architecture: str) -> dict:
    vet_payload(app)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if (info.get("CFBundleIdentifier") != "org.audifern.app" or info.get("CFBundleExecutable") != "Audifern"
            or info.get("CFBundleShortVersionString") != version() or info.get("LSMinimumSystemVersion") != "14.0"):
        raise ValueError("Application identity, version or deployment target does not match this source.")
    executable = app / "Contents/MacOS/Audifern"
    architectures = set(subprocess.check_output(["lipo", "-archs", str(executable)], text=True).split())
    if architectures != expected_architectures(architecture): raise ValueError("The executable does not contain the requested architecture slices.")
    subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
    return {"version": version(), "architectures": sorted(architectures), "minimumMacOS": "14.0"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    versions = commands.add_parser("version"); versions.add_argument("--tag", default="")
    commands.add_parser("source-notice")
    verify = commands.add_parser("verify-app"); verify.add_argument("app", type=Path); verify.add_argument("--architecture", default="native")
    manifest = commands.add_parser("manifest"); manifest.add_argument("app", type=Path)
    manifest.add_argument("--architecture", default="universal"); manifest.add_argument("--tag", default="")
    args = parser.parse_args()
    if args.command == "version": print(release_version(version(), args.tag))
    elif args.command == "source-notice":
        commit = source_commit()
        print("Audifern is free software under GNU GPL version 3 only.\n")
        print("Corresponding source, build instructions and license:\n" + REPOSITORY)
        print("Exact source: " + REPOSITORY + ("/tree/" + commit if commit else "/releases/tag/v" + version()))
        print("\nSee LICENSE.txt and THIRD_PARTY_NOTICES.md in this directory.")
    else:
        data = verify_app(args.app, args.architecture)
        if args.command == "manifest":
            details = subprocess.run(["codesign", "-d", "--verbose=4", str(args.app)], capture_output=True, text=True, check=True)
            data.update({"application": "Audifern", "releaseVersion": release_version(version(), args.tag),
                         "sourceCommit": source_commit(), "sourceRepository": REPOSITORY,
                         "signing": "ad-hoc" if "Signature=adhoc" in details.stderr else "certificate",
                         "notarized": False, "generatedAt": datetime.now(timezone.utc).isoformat()})
        print(json.dumps(data, indent=2, sort_keys=True))


if __name__ == "__main__":
    try: main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error: raise SystemExit(str(error)) from None
