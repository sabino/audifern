#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Sign, notarize and staple universal macOS downloads. Credentials stay local."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import uuid

import release_metadata as metadata
import verify_release as verification

ROOT = Path(__file__).resolve().parents[1]


def authentication(profile: str, key: str = "", key_id: str = "", issuer: str = "") -> list[str]:
    if profile:
        if key or key_id or issuer: raise ValueError("Choose a Keychain profile or an API key.")
        return ["--keychain-profile", profile]
    if not key or not key_id: raise ValueError("Set AUDIFERN_NOTARY_PROFILE or the notarization API key path and ID.")
    args = ["--key", key, "--key-id", key_id]
    if issuer: args += ["--issuer", str(uuid.UUID(issuer))]
    return args


def submission_status(data: dict, expected_id: str | None = None) -> tuple[str, str]:
    identifier = str(uuid.UUID(data["id"]))
    if expected_id and identifier != expected_id: raise ValueError("Apple returned a different submission ID.")
    status = data["status"]
    if status not in {"Accepted", "In Progress", "Invalid", "Rejected"}: raise ValueError("Unknown Apple notarization status.")
    return identifier, status


def run(*args: str, **kwargs) -> None:
    subprocess.run(list(args), check=True, **kwargs)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def archive_app(app: Path, logs: Path) -> Path:
    archive = logs / "app-submission.zip"
    stamp = logs / "app-archive.json"
    contents = hashlib.sha256()
    for path in sorted(app.rglob("*")):
        if path.is_file():
            contents.update(path.relative_to(app).as_posix().encode() + b"\0")
            contents.update(bytes.fromhex(digest(path)))
    fingerprint = contents.hexdigest()
    previous = json.loads(stamp.read_text()) if stamp.exists() else {}
    if previous.get("appSHA256") != fingerprint or not archive.exists() or previous.get("zipSHA256") != digest(archive):
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive))
        stamp.write_text(json.dumps({"appSHA256": fingerprint, "zipSHA256": digest(archive)}) + "\n")
    return archive


def notarize(path: Path, label: str, auth: list[str], timeout: int, logs: Path) -> str:
    def request(command: str, *arguments: str) -> dict:
        result = subprocess.run(["xcrun", "notarytool", command, *arguments, *auth, "--output-format", "json"], capture_output=True, text=True)
        (logs / (label + "-" + command + ".log")).write_text(result.stdout + result.stderr)
        if result.returncode: raise ValueError("Apple notarization request failed; details are in the private build/notarization logs.")
        return json.loads(result.stdout)

    stamp = logs / (label + "-submission.json")
    checksum = digest(path)
    previous = json.loads(stamp.read_text()) if stamp.exists() else {}
    if previous.get("sha256") == checksum:
        identifier = str(uuid.UUID(previous["id"]))
        print(f"Resuming Apple submission ({label}): {identifier}", flush=True)
    else:
        submitted = request("submit", str(path))
        identifier = str(uuid.UUID(submitted["id"]))
        stamp.write_text(json.dumps({"id": identifier, "sha256": checksum}, indent=2) + "\n")
    deadline = time.monotonic() + timeout
    last_status = ""
    while True:
        _, status = submission_status(request("info", identifier), identifier)
        if status != last_status:
            print(f"Apple notarization ({label}): {status}", flush=True)
            last_status = status
        if status == "Accepted":
            (logs / (label + "-accepted.json")).write_text(json.dumps({"id": identifier, "status": status}, indent=2) + "\n")
            return identifier
        if status != "In Progress":
            try: request("log", identifier)
            finally: raise ValueError("Apple rejected this submission; inspect the private notarization logs.")
        if time.monotonic() >= deadline:
            raise ValueError(f"Apple is still processing submission {identifier}; rerun this command to resume without resubmitting.")
        time.sleep(15)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "build/Audifern.app")
    parser.add_argument("--identity", default=os.environ.get("AUDIFERN_SIGN_IDENTITY", ""))
    parser.add_argument("--tag", default="")
    parser.add_argument("--profile", default=os.environ.get("AUDIFERN_NOTARY_PROFILE", ""))
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--rebuild-packages", action="store_true", help="Replace existing packages after an intentional packaging change.")
    args = parser.parse_args()
    if not args.identity or args.identity == "-": raise ValueError("A Developer ID Application signing identity is required.")
    if args.timeout < 1: raise ValueError("The notarization timeout must be positive.")
    version = metadata.release_version(metadata.version(), args.tag)
    auth = authentication(args.profile, os.environ.get("AUDIFERN_NOTARY_KEY_PATH", ""),
                          os.environ.get("AUDIFERN_NOTARY_KEY_ID", ""), os.environ.get("AUDIFERN_NOTARY_ISSUER", ""))
    app = args.app.resolve()
    metadata.verify_app(app, "universal")
    os.umask(0o077)
    logs = ROOT / "build/notarization"
    logs.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Keep an existing valid signature so retries retain their submission hash.
    current = metadata.signing_details(app)
    identity_matches = False
    if len(args.identity) == 40 and all(character in "0123456789abcdefABCDEF" for character in args.identity):
        identity_matches = subprocess.run(["codesign", "--verify", "--strict", "--all-architectures",
                                          '-R=certificate leaf = H"' + args.identity + '"', str(app)],
                                         capture_output=True).returncode == 0
    if not identity_matches or current["signing"] != "developer-id" or not current["hardenedRuntime"] or not current["secureTimestamp"]:
        run("codesign", "--force", "--options", "runtime", "--timestamp", "--sign", args.identity, "--identifier", "org.audifern.app", str(app))
    details = metadata.signing_details(app)
    if details["signing"] != "developer-id" or not all(details[key] for key in ["hardenedRuntime", "secureTimestamp", "teamID"]):
        raise ValueError("The supplied identity did not produce a timestamped, hardened Developer ID signature.")
    run("codesign", "--verify", "--strict", "--all-architectures", str(app))
    if subprocess.run(["xcrun", "stapler", "validate", "-q", str(app)], capture_output=True).returncode != 0:
        submitted_zip = archive_app(app, logs)
        notarize(submitted_zip, "app", auth, args.timeout, logs)
        run("xcrun", "stapler", "staple", "-q", str(app))
    metadata.verify_notarization(app)
    env = os.environ.copy()
    env.update({"AUDIFERN_PACKAGE_APP": str(app), "AUDIFERN_PACKAGE_NOTARIZED": "1",
                "AUDIFERN_SIGN_IDENTITY": args.identity, "AUDIFERN_BUILD_ARCH": "universal"})
    output = ROOT / "build/release"
    prefix = f"Audifern-{version}-macos-universal"
    if output.exists() and any(output.iterdir()) and not args.rebuild_packages:
        verification.verify_downloads(output, args.tag)
        print("Reusing verified packages; pending Apple submissions will resume.", flush=True)
    else:
        run(str(ROOT / "scripts/package-release.sh"), args.tag, cwd=ROOT, env=env)
    dmg = output / (prefix + ".dmg")
    notarize(dmg, "dmg", auth, args.timeout, logs)
    run("xcrun", "stapler", "staple", "-q", str(dmg))
    run("xcrun", "stapler", "validate", "-q", str(dmg))
    run("spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4", str(dmg))
    hashes = []
    for name in [prefix + ".dmg", prefix + ".zip", "build-info.json"]:
        hashes.append(hashlib.sha256((output / name).read_bytes()).hexdigest() + "  " + name)
    (output / "SHA256SUMS").write_text("\n".join(hashes) + "\n")
    verification.verify_release(output, args.tag, details["teamID"])
    print("Verified Developer ID signatures, Apple tickets and Gatekeeper acceptance for the app and DMG.", flush=True)


if __name__ == "__main__":
    try: main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error: raise SystemExit(str(error)) from None
