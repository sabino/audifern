#!/usr/bin/env python3
"""Select an installed macOS 26+ SDK for CI without changing xcode-select."""
from pathlib import Path
import os
import re
import subprocess

candidates = []
selected = subprocess.run(['xcode-select', '--print-path'], capture_output=True, text=True)
if selected.returncode == 0:
    candidates.append(Path(selected.stdout.strip()))
candidates.extend(sorted(Path('/Applications').glob('Xcode*.app/Contents/Developer')))
for developer in dict.fromkeys(candidates):
    environment = dict(os.environ, DEVELOPER_DIR=str(developer))
    result = subprocess.run(['xcrun', '--sdk', 'macosx', '--show-sdk-version'], env=environment, capture_output=True, text=True)
    sdk = result.stdout.strip()
    if result.returncode == 0 and re.fullmatch(r'\d+(?:\.\d+)*', sdk) and int(sdk.split('.')[0]) >= 26:
        if os.environ.get('GITHUB_ENV'):
            with open(os.environ['GITHUB_ENV'], 'a') as output:
                output.write('DEVELOPER_DIR=' + str(developer) + '\n')
        print('Selected Xcode SDK macOS ' + sdk)
        break
else:
    raise SystemExit('Install Xcode with a macOS 26 SDK or newer to build Audifern widgets and system controls.')
