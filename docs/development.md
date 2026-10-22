# Building and developing Audifern

Use macOS 14 or later, Swift 6, Python 3 and Xcode with a macOS 26 SDK or newer
for the packaged widget extension. The Swift package has no external package
dependencies.

```sh
./scripts/build-app.sh
open build/Audifern.app
```

The build uses two jobs and ad hoc signing by default. An Apple Developer account
is not required for the app UI. Interactive widgets need a stable Apple signing
identity. Set `AUDIFERN_SIGN_IDENTITY` to your own identity when needed; a stable
identity also helps preserve Bluetooth permission across development builds.

To explore the interface with synthetic devices and isolated data:

```sh
open -n build/Audifern.app --args --demo
```

Demo mode never connects to hearing aids or reads the regular audiogram library.

## Checks

```sh
swift test --jobs 2
python3 -m unittest discover -s Tests -p 'test_*.py'
python3 scripts/audit-localization.py --strict
python3 scripts/generate-brand-assets.py --check
python3 scripts/export-help.py --check
```

CI separates the two native Sound layout tests from the remaining Swift suite
so layout measurement cannot occupy the main actor during synthetic transport
deadlines. Both processes are required, on Apple Silicon and Intel, followed by
universal DMG/ZIP packaging.

The optional HIMSA schema check uses a locally acquired `Audiogram-1-502.xsd`.
Set `HIMSA_AUDIOGRAM_SCHEMA` to its path; the schema is not redistributed.

## Resources and documentation

The app, widgets and Dock icon use exports of the canonical
[`branding/mark.svg`](../branding/mark.svg). See
[asset regeneration](design/prompts.md#canonical-brand-mark).

User-visible strings belong in the English, Brazilian Portuguese and Spanish
catalogs. [Shared Help exports](help/README.md) use the same feature guidance and
translations as the app, with a CI freshness check.

Protocol and device evidence belongs in the [research reference](research.md).
See [Contributing](../CONTRIBUTING.md) for evidence, privacy and review expectations,
and [distribution](distribution.md) for release signing and notarization.
