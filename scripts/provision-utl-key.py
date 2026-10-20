#!/usr/bin/env python3
"""Provision locally recovered Companion UTL authentication material.

Reads the owner's already-extracted SDK reconstruction. No key is embedded in
this script, returned on stdout, downloaded, or committed. Target code is not
executed. The source pattern is specific to the inspected Companion SDK build.
"""
import argparse
import json
import os
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='Private UtlChallengeAuthentication.cs reconstruction')
    parser.add_argument('--destination', type=Path, default=Path.home() / 'Library/Application Support/Audifern/utl-auth.json')
    args = parser.parse_args()
    matches = re.findall(r'sharedSecret\s*=\s*new byte\[16\]\s*\{([^}]+)\}', args.source.read_text())
    if len(matches) != 1:
        raise SystemExit('Expected exactly one SDK secret declaration; inspect this app version first.')
    parts = [part.strip() for part in matches[0].split(',') if part.strip()]
    if len(parts) != 16 or not all(re.fullmatch(r'[0-9]{1,3}', part) for part in parts):
        raise SystemExit('Unsupported SDK secret format; no output written.')
    values = [int(part) for part in parts]
    if not all(0 <= value <= 255 for value in values):
        raise SystemExit('Invalid SDK secret declaration; no output written.')
    material = {'key': bytes(values).hex()}
    args.destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(args.destination.parent, 0o700)
    if args.destination.exists():
        if json.loads(args.destination.read_text()) != material:
            raise SystemExit('Existing authentication file differs; refusing to replace it.')
        os.chmod(args.destination, 0o600)
        print('Existing local UTL authentication matches; private permissions verified.')
        return
    descriptor = os.open(args.destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w') as output:
        json.dump(material, output)
        output.write('\n')
    print('Local UTL authentication provisioned with mode 0600; no key was printed.')


if __name__ == '__main__':
    main()
