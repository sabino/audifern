# Contributing to Audifern

Small, reviewable changes are easiest to test. Describe the behavior you want
to improve, the devices or synthetic cases involved, and how the result can be
verified. The project is still establishing compatibility across hardware.

## Work locally

Use macOS 14 or later with Swift 6. Build with `./scripts/build-app.sh`; use
`build/Audifern.app/Contents/MacOS/Audifern --demo` to explore synthetic devices
without Bluetooth or the regular exam library.

Run the checks relevant to your change:

```sh
swift test --jobs 2
python3 -m unittest discover -s Tests -p 'test_*.py'
python3 scripts/audit-localization.py --strict
```

Keep builds bounded to two jobs on this project unless you deliberately choose
another limit. Protocol tests use synthetic peers, malformed inputs and
explicit failure paths. Add a test when it verifies a meaningful behavior;
avoid tests that merely reproduce a view's implementation.

## Interface and translations

Everyday controls belong in Sound; detailed adjustments and diagnostics
should remain discoverable without crowding that page. Keep feature navigation
in the main window, use system colors and controls, and preserve keyboard and
accessibility behavior. Check both light and dark appearance.

User-visible strings go through the localization helper and the English,
Brazilian Portuguese and Spanish catalogs. Preserve typed format placeholders;
do not build sentences by concatenating translated fragments. Device-reported
program names are user/device data and should not be translated. The catalog
audit checks key/argument parity; a human still needs to review meaning and fit.

## Device controls and evidence

Use device-reported capabilities, supported protocol versions and fresh state.
Unknown capabilities stay unavailable. Preserve unrelated bytes when a shared
characteristic carries more than one feature. Writes need an explicit action,
range checks, confirming readback and an honest partial-failure result.

Separate static research, synthetic protocol tests, device acknowledgment,
readback and audible confirmation in reports. A successful build or a plausible
opcode is not a hardware test. Do not add exploratory fitting, memory, reset,
firmware or guessed control writes to normal connection or discovery paths.

Consumer presets and clinical fitting are different data. An audiogram is an
exam record, not a gain curve. Proposed fitting or therapy features need their
own evidence and review rather than being inferred from consumer EQ.

## Keep contributions public-safe

Contribute your own implementation and synthetic fixtures. Do not attach vendor
APKs, decompiled code, decoded vendor resources, SDK keys, firmware images,
serials, device addresses, patient information or real audiograms. Use demo
mode for screenshots. Keep raw captures private and share only the smallest
reviewed, redacted facts needed to explain an issue.

Run the [public-source checker](docs/public-release-audit.md) before preparing a
release. Its exact-value input belongs in ignored private storage. An absence
of findings is a bounded check, not a substitute for reviewing the diff and
assets. Intentionally public contributor identities require explicit review;
never rewrite someone else's published history as part of an ordinary patch.

## Pull requests

Explain the problem, the resulting behavior and the checks performed. Include
hardware model/firmware only when relevant, with identifiers removed. Call out
anything that still needs a physical test. Preserve unrelated work, and avoid
bundling a protocol change with a large visual rewrite.

The original project is licensed under **GPL-3.0-only**. Contributions to that
implementation are accepted under the same license. Do not contribute material
you cannot license accordingly; this does not relicense third-party SDKs,
credentials or research inputs. Read [LICENSE](LICENSE), [PRIVACY.md](PRIVACY.md),
[SECURITY.md](SECURITY.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
before contributing data or research.

Release and download automation is documented in [the distribution guide](docs/distribution.md).
