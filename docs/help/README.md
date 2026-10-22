# Shared Help content

These files export the same feature guidance and translations used by Audifern's
offline Help. Websites can render this content as their own documentation pages
instead of presenting the repository README as a manual.

- [English](en.json)
- [Português (Brasil)](pt-BR.json)
- [Español](es.json)

Each file contains a schema version, app version, language and a `topics` array.
Each topic has a stable `id`, translated `title`, navigation `path`, `summary`,
`guidance`, search `keywords` and an `appURL`. The app URL only opens a known
Help destination; it never executes a hearing-aid command.

For example, the current English source is available at
`https://raw.githubusercontent.com/sabino/audifern/main/docs/help/en.json`.
Change the language filename for the other catalogs. Prefer a cached build-time
import or a cached server request, with a local fallback, to downloading all
languages on every page visit. Keep the website's documentation navigable without
launching the app; offer app links as an optional secondary action.

Regenerate after changing Help guidance, translations or the app version:

```sh
python3 scripts/export-help.py
python3 scripts/export-help.py --check
```

The exporter reads `Sources/Audifern/HelpCatalog.swift` and the three localization
catalogs. It does not run Audifern or access Bluetooth, user preferences or private
data. CI checks that committed exports match these sources. The content is
licensed under GPL-3.0-only, like the project.
