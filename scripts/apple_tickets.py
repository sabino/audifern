# SPDX-License-Identifier: GPL-3.0-only
"""Bounded Apple ticket-service retries shared by signing and independent verification."""
from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import time


def run(operation: str, path: Path, label: str, logs: Path | None = None) -> None:
    # EX_NOHOST (68) includes unexpected ticket-service responses. Apple may
    # accept the submission before a particular retrieval succeeds. Never
    # retry invalid/revoked tickets or bypass the later ticket verification.
    if operation not in {"staple", "validate"}:
        raise ValueError("Unsupported Apple ticket operation.")
    output = ""
    for attempt, delay in enumerate([0, 15, 30, 60], 1):
        if delay:
            print(f"Apple ticket retrieval ({label}): retrying in {delay} seconds", flush=True)
            time.sleep(delay)
        try:
            result = subprocess.run(["xcrun", "stapler", operation, str(path)],
                                    capture_output=True, text=True, timeout=60)
            code = result.returncode
            output = result.stdout + result.stderr
        except subprocess.TimeoutExpired as error:
            code = None
            def decoded(value):
                return value.decode(errors="replace") if isinstance(value, bytes) else value or ""
            output = "Ticket retrieval timed out.\n" + decoded(error.stdout) + decoded(error.stderr)
        if logs is not None:
            (logs / f"{label}-{operation}-{attempt}.log").write_text(f"exitCode={code}\n" + output)
        if code == 0:
            return
        if code not in {68, None}:
            break
    # stapler receives no credentials. Preserve a bounded diagnostic in CI;
    # complete attempt logs remain outside the release artifact directory.
    print(output[-4000:], file=sys.stderr)
    action = "stapling" if operation == "staple" else "validation"
    raise ValueError(f"Apple ticket {action} failed ({label}); required verification did not pass. No package was published.")

