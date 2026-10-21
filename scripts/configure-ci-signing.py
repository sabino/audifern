#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Upload selected signing credentials to a main-only GitHub environment, with explicit consent."""
from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "sabino/audifern"
ENVIRONMENT = "apple-notarization"


def run(label: str, args: list[str], *, input: bytes | None = None, env: dict | None = None) -> bytes:
    result = subprocess.run(args, input=input, env=env, capture_output=True)
    if result.returncode:
        # Credential-bearing subprocess arguments and output must never reach logs.
        raise ValueError(label + " failed. Credential values have not been printed.")
    return result.stdout


def verify_environment() -> None:
    data = json.loads(run("Reading the protected environment", ["gh", "api", f"repos/{REPOSITORY}/environments/{ENVIRONMENT}"]))
    if data.get("deployment_branch_policy") != {"protected_branches": False, "custom_branch_policies": True}:
        raise ValueError("The signing environment must use explicit deployment branch policies.")
    policies = json.loads(run("Reading deployment branch policies", ["gh", "api",
        f"repos/{REPOSITORY}/environments/{ENVIRONMENT}/deployment-branch-policies"]))["branch_policies"]
    if len(policies) != 1 or policies[0].get("name") != "main" or policies[0].get("type") != "branch":
        raise ValueError("The signing environment must allow only the main branch, with no tag policies.")


def set_secret(name: str, value: bytes) -> None:
    run("Uploading the encrypted environment secret " + name,
        ["gh", "secret", "set", name, "--repo", REPOSITORY, "--env", ENVIRONMENT], input=value)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", required=True, help="Developer ID Application certificate SHA-1.")
    parser.add_argument("--team", required=True)
    parser.add_argument("--key", type=Path, required=True, help="Locally downloaded Team API key.")
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer", required=True)
    parser.add_argument("--upload-credentials", action="store_true",
                        help="Consent to export this one identity and transfer it and the API key to encrypted GitHub environment secrets.")
    args = parser.parse_args()
    if not args.upload_credentials:
        raise ValueError("No credential transfer performed. Review the protected workflow and use --upload-credentials only after approving the transfer.")
    if not re.fullmatch(r"[A-F0-9]{40}", args.identity) or not re.fullmatch(r"[A-Z0-9]{10}", args.team) \
            or not re.fullmatch(r"[A-Z0-9]{10,32}", args.key_id):
        raise ValueError("Invalid signing fingerprint, team or API key ID.")
    issuer = str(uuid.UUID(args.issuer))
    if args.key.is_symlink() or not args.key.is_file():
        raise ValueError("Provide a regular local Team API key file.")
    key = args.key.resolve()
    verify_environment()
    # Validate this dedicated Team key before exporting any signing identity.
    run("Validating the notarization API key", ["xcrun", "notarytool", "history", "--key", str(key),
        "--key-id", args.key_id, "--issuer", issuer, "--output-format", "json"])
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="audifern-ci-setup-") as folder:
        work = Path(folder)
        exporter = work / "export-identity"
        run("Compiling the selected-identity exporter", ["xcrun", "swiftc", str(ROOT / "scripts/export-signing-identity.swift"), "-o", str(exporter)])
        password = secrets.token_urlsafe(48)
        certificate = work / "identity.p12"
        run("Exporting the selected Developer ID identity", [str(exporter), args.identity, str(certificate)],
            env=dict(os.environ, AUDIFERN_EXPORT_PASSWORD=password))
        # gh encrypts each value for GitHub. No credentials are written to Git or stdout.
        for name, value in {
            "AUDIFERN_CERTIFICATE_P12": base64.b64encode(certificate.read_bytes()),
            "AUDIFERN_CERTIFICATE_PASSWORD": password.encode(),
            "AUDIFERN_NOTARY_KEY": key.read_bytes(),
            "AUDIFERN_NOTARY_KEY_ID": args.key_id.encode(),
            "AUDIFERN_NOTARY_ISSUER": issuer.encode(),
        }.items():
            set_secret(name, value)
        for name, value in {"AUDIFERN_SIGN_IDENTITY": args.identity, "AUDIFERN_TEAM_ID": args.team}.items():
            run("Setting the public signing variable " + name,
                ["gh", "variable", "set", name, "--repo", REPOSITORY], input=value.encode())
    print("Configured encrypted Apple signing secrets in the main-only environment. Temporary exports were removed.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(str(error) if isinstance(error, ValueError) else "CI signing setup failed; no credential values were logged.") from None
