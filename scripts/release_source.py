#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Resolve a maintainer-signed tag on main before a job can receive Apple secrets."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

import release_metadata as metadata

ROOT = Path(__file__).resolve().parents[1]
SIGNER = "46AAE436358867E6A27E6C751BC0E4A3537E0BB8"


def output(repo: Path, *args: str, env: dict | None = None) -> str:
    result = subprocess.run(["git", *args], cwd=repo, env=env, capture_output=True, text=True)
    if result.returncode:
        raise ValueError("Release source validation failed: " + args[0])
    return result.stdout.strip()


def verify_tag(repo: Path, tag: str, public_key: Path, fingerprint: str = SIGNER) -> dict:
    if not metadata.TAG.fullmatch(tag):
        raise ValueError("Expected a semantic version tag.")
    if not re.fullmatch(r"[A-F0-9]{40,64}", fingerprint):
        raise ValueError("Invalid maintainer signing fingerprint.")
    ref = "refs/tags/" + tag
    if output(repo, "cat-file", "-t", ref) != "tag":
        raise ValueError("Release tags must be annotated and GPG-signed by the maintainer.")
    commit = output(repo, "rev-parse", ref + "^{commit}")
    tag_object = output(repo, "rev-parse", ref)
    if not re.fullmatch(r"[0-9a-f]{40,64}", commit):
        raise ValueError("Invalid release commit.")
    output(repo, "merge-base", "--is-ancestor", commit, "refs/remotes/origin/main")
    info = plistlib.loads(subprocess.check_output(["git", "show", commit + ":Resources/Info.plist"], cwd=repo))
    if info.get("CFBundleIdentifier") != "org.audifern.app":
        raise ValueError("The tagged app identity differs from Audifern.")
    version = metadata.release_version(info["CFBundleShortVersionString"], tag)
    with tempfile.TemporaryDirectory(prefix="audifern-tag-") as folder:
        os.chmod(folder, 0o700)
        env = dict(os.environ, GNUPGHOME=folder)
        imported = subprocess.run(["gpg", "--batch", "--import", str(public_key.resolve())],
                                  capture_output=True, env=env)
        if imported.returncode:
            raise ValueError("The maintainer public key could not be imported.")
        try:
            verified = subprocess.run(["git", "-c", "gpg.format=openpgp", "-c", "gpg.program=gpg",
                                       "verify-tag", "--raw", ref], cwd=repo, capture_output=True, text=True, env=env)
            signatures = [line.split() for line in verified.stderr.splitlines() if line.startswith("[GNUPG:] VALIDSIG ")]
            if verified.returncode or len(signatures) != 1 or fingerprint not in {signatures[0][2], signatures[0][-1]}:
                raise ValueError("The tag does not have a valid signature from the approved maintainer key.")
        finally:
            subprocess.run(["gpgconf", "--kill", "gpg-agent"], env=env, capture_output=True)
    return {"tag": tag, "commit": commit, "tagObject": tag_object, "version": version}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--public-key", type=Path, default=ROOT / ".github/release-signing-key.asc")
    parser.add_argument("--github-output", action="store_true")
    args = parser.parse_args()
    try:
        data = verify_tag(args.repo.resolve(), args.tag, args.public_key)
        if args.github_output:
            with open(os.environ["GITHUB_OUTPUT"], "a") as destination:
                destination.writelines(key + "=" + value + "\n" for key, value in data.items())
        print(json.dumps(data, sort_keys=True))
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit("Release source validation failed. " + (str(error) if isinstance(error, ValueError) else "Check the tag, public key and main ancestry.")) from None
