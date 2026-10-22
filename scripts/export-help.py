#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Export the app's literal Help catalog and translations for documentation sites."""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = {"en": "English", "pt-BR": "Português (Brasil)", "es": "Español"}
STRING = r'"(?:\\.|[^"\\])*"'


def topic_pattern() -> re.Pattern:
    fields = []
    for field in ("id", "title", "path", "symbol", "summary", "guidance", "keywords"):
        value = r'\[[^\]]*\]' if field == "path" else STRING
        fields.append(rf'{field}:\s*(?P<{field}>{value})')
    return re.compile(r'\.init\(\s*' + r',\s*'.join(fields) + r',\s*destination:')


def export() -> dict[str, str]:
    spec = importlib.util.spec_from_file_location("localization_audit", ROOT / "scripts/audit-localization.py")
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    source = (ROOT / "Sources/Audifern/HelpCatalog.swift").read_text()
    matches = list(topic_pattern().finditer(source))
    if not matches or len(matches) != len(re.findall(r'\.init\(\s*id:', source)):
        raise ValueError("Help entries must retain their complete literal field layout; review the exporter if the catalog changes.")
    topics = []
    for match in matches:
        def literal(value: str) -> str:
            if r'\(' in value:
                raise ValueError("Help exports cannot contain interpolated or private runtime values.")
            return audit.decode_swift(value[1:-1], 0)
        topic = {field: literal(match[field]) for field in ("id", "title", "symbol", "summary", "guidance", "keywords")}
        topic["path"] = [literal(value) for value in re.findall(STRING, match["path"])]
        if not re.fullmatch(r'[a-z][a-z0-9-]*', topic["id"]) or not topic["path"]:
            raise ValueError("Invalid Help topic identity or path.")
        topics.append(topic)
    if len({topic["id"] for topic in topics}) != len(topics):
        raise ValueError("Help topic IDs must be unique.")
    version = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
    results = {}
    for language, name in LANGUAGES.items():
        catalog, errors = audit.read_strings(ROOT / f"Sources/Audifern/Resources/{language}.lproj/Localizable.strings")
        if errors:
            raise ValueError("\n".join(errors))
        def translated(value: str) -> str:
            if value not in catalog:
                raise ValueError(f"Missing {language} Help translation: {value!r}")
            return catalog[value]
        localized = []
        for topic in topics:
            localized.append({"id": topic["id"], "title": translated(topic["title"]),
                              "path": [translated(value) for value in topic["path"]],
                              "summary": translated(topic["summary"]), "guidance": translated(topic["guidance"]),
                              "keywords": topic["keywords"], "appURL": f"audifern://feature/{topic['id']}"})
        data = {"schemaVersion": 1, "application": "Audifern", "appVersion": version,
                "language": language, "languageName": name, "license": "GPL-3.0-only",
                "source": "Sources/Audifern/HelpCatalog.swift", "topics": localized}
        results[language] = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail when the committed exports are missing or stale.")
    args = parser.parse_args()
    for language, text in export().items():
        path = ROOT / f"docs/help/{language}.json"
        if args.check:
            if not path.is_file() or path.read_text() != text:
                raise SystemExit(f"Stale Help export: {path.relative_to(ROOT)}. Run python3 scripts/export-help.py.")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        print(f"{language}: {len(json.loads(text)['topics'])} Help topics {'verified' if args.check else 'exported'}")


if __name__ == "__main__":
    main()
