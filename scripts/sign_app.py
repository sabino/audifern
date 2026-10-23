#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Sign the widget first, then its host, using one Team-ID-prefixed app group.

No provisioning profile or exported credential is placed in either bundle.
Ad-hoc builds deliberately have no shared container and cannot send actions.
"""
from __future__ import annotations

from pathlib import Path
import argparse
import plistlib
import re
import subprocess
import tempfile
import sparkle_framework

WIDGET = Path("Contents/PlugIns/AudifernWidgets.appex")


def team_identifier(bundle: Path) -> str:
    result = subprocess.run(["codesign", "-d", "--verbose=4", str(bundle)],
                            capture_output=True, text=True, check=True)
    match = re.search(r"^TeamIdentifier=([A-Z0-9]{10})$", result.stderr, re.M)
    return match[1] if match else ""


def entitlements(team: str, *, widget: bool) -> dict:
    if team and not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("Invalid signing team.")
    result = {"com.apple.security.app-sandbox": True} if widget else {}
    if team:
        result["com.apple.security.application-groups"] = [team + ".org.audifern.shared"]
    return result


def sign(app: Path, identity: str, *, hardened: bool) -> None:
    widget = app / WIDGET
    if not widget.is_dir() or widget.is_symlink():
        raise ValueError("The reviewed widget extension must be embedded before signing.")
    options = ["--options", "runtime", "--timestamp"] if hardened and identity != "-" else []

    def codesign(bundle: Path, entitlement_file: Path | None = None) -> None:
        args = ["codesign", "--force", "--sign", identity, *options]
        if entitlement_file is not None:
            args += ["--entitlements", str(entitlement_file), "--generate-entitlement-der"]
        subprocess.run([*args, str(bundle)], check=True)

    # Resolve the team from the selected identity's actual signature, not a
    # hardcoded maintainer ID or caller-controlled group name.
    codesign(widget)
    team = team_identifier(widget)
    if identity != "-" and not team:
        raise ValueError("The selected certificate has no Apple developer team.")
    group = team + ".org.audifern.shared" if team else ""
    for bundle in [widget, app]:
        info_path = bundle / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["AudifernAppGroupIdentifier"] = group
        info_path.write_bytes(plistlib.dumps(info))
    with tempfile.TemporaryDirectory(prefix="audifern-entitlements-") as folder:
        framework = app / sparkle_framework.RELATIVE
        if framework.exists():
            sparkle_framework.verify_payload(framework)
            for relative in sparkle_framework.BUNDLES:
                bundle = framework / relative
                # Preserve Sparkle's reviewed helper entitlements when signing
                # its nested code with the selected app identity.
                existing = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(bundle)],
                                          capture_output=True, check=True).stdout
                path = Path(folder) / 'sparkle.plist'
                path.write_bytes(plistlib.dumps(plistlib.loads(existing) if existing else {}))
                codesign(bundle, path)
            codesign(framework)
        for bundle, is_widget in [(widget, True), (app, False)]:
            path = Path(folder) / ("widget.plist" if is_widget else "app.plist")
            path.write_bytes(plistlib.dumps(entitlements(team, widget=is_widget)))
            codesign(bundle, path)
    for bundle in [widget, app]:
        subprocess.run(["codesign", "--verify", "--strict", "--all-architectures", str(bundle)], check=True)
        if team_identifier(bundle) != team:
            raise ValueError("The host and widget must be signed by the same team.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--identity", required=True)
    parser.add_argument("--hardened", action="store_true")
    args = parser.parse_args()
    sign(args.app, args.identity, hardened=args.hardened)
