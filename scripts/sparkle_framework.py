#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Embed and vet the pinned Sparkle framework without broadening the app payload."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RELATIVE = Path('Contents/Frameworks/Sparkle.framework')
ARTIFACT = Path('.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework')
BUNDLES = ['Versions/B/XPCServices/Downloader.xpc', 'Versions/B/XPCServices/Installer.xpc',
           'Versions/B/Updater.app', 'Versions/B/Autoupdate']
EXECUTABLES = ['Versions/B/Sparkle', 'Versions/B/Autoupdate',
               'Versions/B/Updater.app/Contents/MacOS/Updater',
               'Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader',
               'Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer']


def verify_payload(framework: Path, project: Path = ROOT, *, manifest: dict | None = None) -> None:
    if framework.is_symlink() or not framework.is_dir():
        raise ValueError('The pinned Sparkle framework is missing.')
    if manifest is None:
        manifest = json.loads((project / 'scripts/sparkle-payload.json').read_text())
    files = {}; links = {}
    for path in framework.rglob('*'):
        name = path.relative_to(framework).as_posix()
        if path.is_symlink():
            links[name] = str(path.readlink())
            if not path.resolve().is_relative_to(framework.resolve()) or not path.exists():
                raise ValueError('An updater framework symlink leaves its bundle or is broken.')
        elif path.is_file():
            files[name] = path
    if set(files) != set(manifest['files']) or links != manifest['symlinks']:
        raise ValueError('The updater framework contains missing or unreviewed files.')
    for name, expected in manifest['files'].items():
        path = files[name]
        if bool(path.stat().st_mode & 0o100) != expected['executable']:
            raise ValueError('The updater payload executable permissions changed.')
        if 'sha256' in expected and hashlib.sha256(path.read_bytes()).hexdigest() != expected['sha256']:
            raise ValueError('A pinned updater resource changed.')
    info = plistlib.loads((framework / 'Resources/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != manifest['bundleIdentifier'] or info.get('CFBundleShortVersionString') != manifest['version']:
        raise ValueError('The embedded updater differs from the pinned version.')


def verify_signatures(app: Path, team: str | None) -> None:
    framework = app / RELATIVE
    for relative in [*BUNDLES, '.']:
        bundle = framework / relative
        subprocess.run(['codesign', '--verify', '--strict', '--all-architectures', str(bundle)], check=True)
        details = subprocess.run(['codesign', '-d', '--verbose=4', str(bundle)], check=True, capture_output=True, text=True).stderr
        if team and (f'TeamIdentifier={team}\n' not in details or 'Authority=Developer ID Application:' not in details
                     or '(runtime)' not in details or 'Timestamp=' not in details):
            raise ValueError('An updater component lacks the expected Developer ID, runtime or timestamp.')
    for relative in EXECUTABLES:
        architectures = subprocess.check_output(['lipo', '-archs', str(framework / relative)], text=True).split()
        if set(architectures) != {'arm64', 'x86_64'}:
            raise ValueError('Every updater component must support Apple Silicon and Intel.')


def embed(app: Path) -> None:
    source = ROOT / ARTIFACT
    verify_payload(source)
    target = app / RELATIVE
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        raise ValueError('Refusing to merge an updater into an existing framework.')
    subprocess.run(['ditto', str(source), str(target)], check=True)
    verify_payload(target)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    args = parser.parse_args()
    embed(args.app)
