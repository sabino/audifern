#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Prepare a verified CI app and an isolated signing Keychain. Never print secrets."""
from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import shutil
import stat
import subprocess
import tempfile
import uuid


def command(label: str, args: list[str]) -> str:
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        # security may include its arguments in errors. Never forward raw output.
        raise ValueError(label + " failed; no credential values have been logged.")
    return result.stdout


def trusted_context() -> None:
    if (os.environ.get("GITHUB_REPOSITORY") != "sabino/audifern"
            or os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch"
            or os.environ.get("GITHUB_REF") != "refs/heads/main"):
        raise ValueError("Apple signing is allowed only for the trusted main workflow.")


def credentials(environment: dict) -> tuple[bytes, str, str]:
    required = ["AUDIFERN_CERTIFICATE_P12", "AUDIFERN_CERTIFICATE_PASSWORD", "AUDIFERN_NOTARY_KEY",
                "AUDIFERN_NOTARY_KEY_ID", "AUDIFERN_NOTARY_ISSUER", "AUDIFERN_SIGN_IDENTITY", "AUDIFERN_TEAM_ID"]
    if any(not environment.get(key) for key in required):
        raise ValueError("Apple CI secrets are incomplete. Configure the apple-notarization environment.")
    try:
        certificate = base64.b64decode("".join(environment["AUDIFERN_CERTIFICATE_P12"].split()), validate=True)
    except (ValueError, binascii.Error):
        raise ValueError("The signing certificate must be base64-encoded PKCS#12.") from None
    if not certificate or not re.fullmatch(r"[A-F0-9]{40}", environment["AUDIFERN_SIGN_IDENTITY"]):
        raise ValueError("The signing identity must be a certificate SHA-1 fingerprint.")
    if not re.fullmatch(r"[A-Z0-9]{10}", environment["AUDIFERN_TEAM_ID"]):
        raise ValueError("The Apple developer team ID is invalid.")
    if not re.fullmatch(r"[A-Z0-9]{10,32}", environment["AUDIFERN_NOTARY_KEY_ID"]):
        raise ValueError("The notarization API key ID is invalid.")
    try:
        uuid.UUID(environment["AUDIFERN_NOTARY_ISSUER"])
    except ValueError:
        raise ValueError("A Team API key issuer UUID is required.") from None
    key = environment["AUDIFERN_NOTARY_KEY"].strip() + "\n"
    boundary = "PRIVATE KEY"
    if not key.startswith("-----BEGIN " + boundary + "-----\n") or not key.endswith("-----END " + boundary + "-----\n"):
        raise ValueError("Use the downloaded App Store Connect Team API key in PEM format.")
    return certificate, key, environment["AUDIFERN_SIGN_IDENTITY"]


def setup(state_file: Path) -> None:
    trusted_context()
    certificate, key, identity = credentials(os.environ)
    runner_temp = Path(os.environ["RUNNER_TEMP"]).resolve()
    if state_file.resolve().parent != runner_temp:
        raise ValueError("Signing state must stay directly under RUNNER_TEMP.")
    if state_file.exists():
        raise ValueError("Signing state already exists; clean up the previous Keychain first.")
    os.umask(0o077)
    folder = Path(tempfile.mkdtemp(prefix="audifern-signing-", dir=runner_temp))
    keychain = folder / "signing.keychain-db"
    previous = shlex.split(command("Reading the runner Keychain list", ["security", "list-keychains", "-d", "user"]))
    state_file.write_text(json.dumps({"folder": str(folder), "keychain": str(keychain), "previousKeychains": previous}) + "\n")
    state_file.chmod(0o600)
    password = base64.urlsafe_b64encode(os.urandom(32)).decode()
    p12 = folder / "identity.p12"
    p8 = folder / "notary-key.p8"
    try:
        p12.write_bytes(certificate)
        p8.write_text(key)
        command("Checking the notarization key", ["openssl", "pkey", "-in", str(p8), "-noout", "-check"])
        command("Creating the temporary Keychain", ["security", "create-keychain", "-p", password, str(keychain)])
        command("Configuring the temporary Keychain", ["security", "set-keychain-settings", "-lut", "7200", str(keychain)])
        command("Unlocking the temporary Keychain", ["security", "unlock-keychain", "-p", password, str(keychain)])
        command("Importing the signing identity", ["security", "import", str(p12), "-k", str(keychain), "-P",
                os.environ["AUDIFERN_CERTIFICATE_PASSWORD"], "-f", "pkcs12", "-T", "/usr/bin/codesign"])
        p12.unlink()
        command("Allowing Apple signing tools", ["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
                "-s", "-k", password, str(keychain)])
        found = command("Checking the imported identity", ["security", "find-identity", "-v", "-p", "codesigning", str(keychain)])
        matches = re.findall(r'\b([A-F0-9]{40}) "([^"]+)"', found)
        if len(matches) != 1 or matches[0][0] != identity or not matches[0][1].startswith("Developer ID Application:") \
                or not matches[0][1].endswith("(" + os.environ["AUDIFERN_TEAM_ID"] + ")"):
            raise ValueError("The imported identity does not match the configured Developer ID certificate and team.")
        command("Selecting the temporary Keychain", ["security", "list-keychains", "-d", "user", "-s", str(keychain), *previous])
        with open(os.environ["GITHUB_OUTPUT"], "a") as output:
            output.write("identity=" + identity + "\nkeyPath=" + str(p8) + "\n")
    except BaseException:
        cleanup(state_file)
        raise
    print("Imported the expected Developer ID identity into an isolated temporary Keychain.")


def cleanup(state_file: Path) -> None:
    if not state_file.exists():
        return
    runner_temp = Path(os.environ["RUNNER_TEMP"]).resolve()
    if state_file.resolve().parent != runner_temp:
        raise ValueError("Refusing cleanup outside RUNNER_TEMP.")
    state = json.loads(state_file.read_text())
    folder = Path(state["folder"])
    keychain = Path(state["keychain"])
    if folder.is_symlink() or folder.parent.resolve() != runner_temp or not folder.name.startswith("audifern-signing-") \
            or keychain != folder / "signing.keychain-db":
        raise ValueError("Unexpected signing cleanup paths.")
    errors = []
    for label, args in [
        ("Restoring the runner Keychain list", ["security", "list-keychains", "-d", "user", "-s", *state["previousKeychains"]]),
        ("Deleting the temporary Keychain", ["security", "delete-keychain", str(keychain)]),
    ]:
        try:
            if "delete-keychain" not in args or keychain.exists():
                command(label, args)
        except ValueError:
            errors.append(label)
    shutil.rmtree(folder, ignore_errors=False)
    state_file.unlink()
    if errors:
        raise ValueError("Signing cleanup failed: " + ", ".join(errors))
    print("Deleted temporary signing credentials and restored the runner Keychain list.")


def validate_unsigned(directory: Path, tag: str, commit: str) -> dict:
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?", tag) or not re.fullmatch(r"[0-9a-f]{40,64}", commit):
        raise ValueError("Invalid release tag or source commit.")
    version = tag[1:]
    prefix = "Audifern-" + version + "-macos-universal"
    expected = {prefix + ".dmg", prefix + ".zip", "SHA256SUMS", "build-info.json"}
    paths = list(directory.iterdir())
    if {path.name for path in paths} != expected or any(path.is_symlink() or not path.is_file() for path in paths):
        raise ValueError("Unexpected unsigned release artifacts.")
    entries = {}
    for line in (directory / "SHA256SUMS").read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9._-]+)", line)
        if not match or match[2] in entries:
            raise ValueError("Malformed release checksums.")
        entries[match[2]] = match[1]
    if entries.keys() != expected - {"SHA256SUMS"}:
        raise ValueError("The unsigned checksums do not cover the expected assets.")
    if any(hashlib.sha256((directory / name).read_bytes()).hexdigest() != checksum for name, checksum in entries.items()):
        raise ValueError("Unsigned release checksum mismatch.")
    data = json.loads((directory / "build-info.json").read_text())
    required = {"application": "Audifern", "releaseVersion": version, "version": version.split("-", 1)[0],
                "sourceCommit": commit, "sourceRepository": "https://github.com/sabino/audifern",
                "architectures": ["arm64", "x86_64"], "minimumMacOS": "14.0", "signing": "ad-hoc", "notarized": False}
    if any(data.get(key) != value for key, value in required.items()):
        raise ValueError("The unsigned build does not match the validated release source.")
    return data


def prepare(project: Path, directory: Path, tag: str, commit: str, tag_object: str) -> None:
    trusted_context()
    if not re.fullmatch(r"[0-9a-f]{40,64}", tag_object):
        raise ValueError("Invalid signed tag object.")
    data = validate_unsigned(directory, tag, commit)
    head = command("Checking the checked-out commit", ["git", "-C", str(project), "rev-parse", "HEAD"]).strip()
    remote = command("Checking the remote signed tag", ["git", "-C", str(project), "ls-remote", "origin", "refs/tags/" + tag]).split()
    if head != commit or remote != [tag_object, "refs/tags/" + tag]:
        raise ValueError("The release tag changed after source validation.")
    import zipfile
    archive = directory / ("Audifern-" + data["releaseVersion"] + "-macos-universal.zip")
    with zipfile.ZipFile(archive) as zipped:
        for entry in zipped.infolist():
            path = PurePosixPath(entry.filename)
            if not path.parts or entry.filename.startswith("/") or ".." in path.parts or "\\" in entry.filename \
                    or path.parts[0] not in {"Audifern.app", "__MACOSX"} or stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError("Unsafe path in the unsigned application ZIP.")
    command("Extracting the verified app", ["ditto", "-x", "-k", str(archive), str(project / "build")])
    command("Validating the unsigned application", ["python3", str(project / "scripts/release_metadata.py"),
            "verify-app", str(project / "build/Audifern.app"), "--architecture", "universal"])
    print("Verified the build's source, checksums, tag identity and app payload before loading Apple secrets.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "setup", "cleanup"])
    parser.add_argument("--state", type=Path)
    parser.add_argument("--project", type=Path)
    parser.add_argument("--directory", type=Path)
    parser.add_argument("--tag", default="")
    parser.add_argument("--commit", default="")
    parser.add_argument("--tag-object", default="")
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            if not args.project or not args.directory:
                raise ValueError("Prepare requires the project and unsigned artifact directory.")
            prepare(args.project.resolve(), args.directory.resolve(), args.tag, args.commit, args.tag_object)
        else:
            if not args.state:
                raise ValueError("Provide the temporary signing state path.")
            {"setup": setup, "cleanup": cleanup}[args.command](args.state)
    except ValueError as error:
        raise SystemExit(str(error)) from None
    except (KeyError, OSError):
        # Never include subprocess arguments, environment contents or credential data.
        raise SystemExit("CI signing preparation or cleanup failed. Check required secrets, source validation and signing configuration.") from None
