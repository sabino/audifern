#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Generate a signed update feed and verify it using only the embedded public key."""
from __future__ import annotations

import argparse
import base64
from contextlib import contextmanager
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
NAMESPACE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def validate_feed(data: bytes, info: dict, manifest: dict, archive_size: int) -> str:
    if len(data) > 2_000_000 or b'<!DOCTYPE' in data or b'<!ENTITY' in data:
        raise ValueError('Unexpected update-feed size or XML declaration.')
    root = ET.fromstring(data)
    items = root.findall('./channel/item')
    if root.tag != 'rss' or len(items) != 1:
        raise ValueError('The update feed must contain exactly this release.')
    item = items[0]
    if (item.findtext(NAMESPACE + 'version') != info['CFBundleVersion']
            or item.findtext(NAMESPACE + 'shortVersionString') != manifest['releaseVersion']
            or item.findtext(NAMESPACE + 'minimumSystemVersion') != '14.0'):
        raise ValueError('The update feed version or minimum macOS differs from the app.')
    enclosures = item.findall('enclosure')
    version = manifest['releaseVersion']
    url = f'https://github.com/sabino/audifern/releases/download/v{version}/Audifern-{version}-macos-universal.zip'
    if len(enclosures) != 1 or enclosures[0].get('url') != url or enclosures[0].get('length') != str(archive_size):
        raise ValueError('The update feed points to a different archive or length.')
    signature = enclosures[0].get(NAMESPACE + 'edSignature', '')
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('The update archive has no valid Ed25519 signature.')
    return signature


def verify(directory: Path, project: Path = ROOT) -> None:
    info = plistlib.loads((project / 'Resources/Info.plist').read_bytes())
    manifest = json.loads((directory / 'build-info.json').read_text())
    archive = directory / f"Audifern-{manifest['releaseVersion']}-macos-universal.zip"
    feed = directory / 'appcast.xml'
    signature = validate_feed(feed.read_bytes(), info, manifest, archive.stat().st_size)
    public = info['SUPublicEDKey']
    # No signing key, Apple credentials or framework execution is needed on
    # the independent verifier's fresh Mac.
    tool = ROOT / 'scripts/verify-update-signature.swift'
    for mode, path, extra in [('feed', feed, []), ('archive', archive, [signature])]:
        subprocess.run(['swift', str(tool), mode, public, str(path), *extra], check=True)


@contextmanager
def tools(project: Path):
    pinned = json.loads((project / 'scripts/sparkle-payload.json').read_text())
    local = project / '.build/artifacts/sparkle/Sparkle/bin'
    names = pinned['tools']
    if all((local / name).is_file() and hashlib.sha256((local / name).read_bytes()).hexdigest() == digest
           for name, digest in names.items()):
        yield local
        return
    with tempfile.TemporaryDirectory(prefix='audifern-sparkle-tools-') as temporary:
        directory = Path(temporary)
        with urllib.request.urlopen(pinned['archiveURL'], timeout=45) as response:
            data = response.read(32_000_001)
        if len(data) > 32_000_000 or hashlib.sha256(data).hexdigest() != pinned['archiveSHA256']:
            raise ValueError('The updater tools did not match the pinned archive checksum.')
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            for name, digest in names.items():
                matches = [entry for entry in archive.infolist() if entry.filename.endswith('/bin/' + name) or entry.filename == 'bin/' + name]
                if len(matches) != 1 or matches[0].file_size > 32_000_000:
                    raise ValueError('Unexpected updater tool archive layout.')
                contents = archive.read(matches[0])
                if hashlib.sha256(contents).hexdigest() != digest:
                    raise ValueError('An updater signing tool differs from its pinned hash.')
                path = directory / name; path.write_bytes(contents); path.chmod(0o700)
        yield directory


def create(directory: Path, project: Path = ROOT) -> None:
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        expected = {'GITHUB_REPOSITORY': 'sabino/audifern', 'GITHUB_EVENT_NAME': 'workflow_dispatch', 'GITHUB_REF': 'refs/heads/main'}
        if any(os.environ.get(key) != value for key, value in expected.items()):
            raise ValueError('Update signing is restricted to the trusted main release workflow.')
    key = os.environ.pop('AUDIFERN_UPDATE_PRIVATE_KEY', '').strip()
    if len(base64.b64decode(key, validate=True)) != 32:
        raise ValueError('Configure the dedicated update-signing key in the protected release environment.')
    manifest = json.loads((directory / 'build-info.json').read_text())
    version = manifest['releaseVersion']
    if manifest.get('notarized') is not True or manifest.get('signing') != 'developer-id':
        raise ValueError('Only a notarized Developer ID release can receive a published update feed.')
    archive = directory / f'Audifern-{version}-macos-universal.zip'
    notes = project / f'docs/releases/{version}.md'
    if not notes.is_file():
        raise ValueError('Release notes must be present before generating an update feed.')
    with tools(project) as bin_directory, tempfile.TemporaryDirectory(prefix='audifern-feed-') as temporary:
        staging = Path(temporary)
        shutil.copyfile(archive, staging / archive.name)
        shutil.copyfile(notes, staging / (archive.stem + '.md'))
        result = subprocess.run([str(bin_directory / 'generate_appcast'), '--ed-key-file', '-', '--maximum-deltas', '0',
                                 '--maximum-versions', '1', '--embed-release-notes', '--download-url-prefix',
                                 f'https://github.com/sabino/audifern/releases/download/v{version}/',
                                 '-o', str(staging / 'appcast.xml'), str(staging)],
                                input=key + '\n', text=True, capture_output=True, timeout=180)
        if result.returncode:
            raise ValueError('Sparkle could not generate the signed feed; no update was published.')
        shutil.copyfile(staging / 'appcast.xml', directory / 'appcast.xml')
    verify(directory, project)
    files = sorted(path for path in directory.iterdir() if path.name != 'SHA256SUMS')
    (directory / 'SHA256SUMS').write_text(''.join(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.name + '\n' for path in files))
    print('Generated and independently verified the signed update feed and archive.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['create', 'verify'])
    parser.add_argument('directory', type=Path)
    parser.add_argument('--project', type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        (create if args.command == 'create' else verify)(args.directory.resolve(), args.project.resolve())
    except (ValueError, KeyError, OSError, ET.ParseError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from None
