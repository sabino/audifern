# Third-party materials and project identity

Audifern is an independent implementation. It is not an Oticon or Demant
product and is not affiliated with, certified by or endorsed by those companies.
Vendor and product names identify the hardware and software investigated; their
names and marks remain with their respective owners. The Audifern name and
project-specific branding are separate from the vendor's Companion app.

This file records provenance boundaries. It is not a trademark clearance or a
legal opinion. The original project implementation is licensed under
**GNU GPL version 3 only** (`GPL-3.0-only`); the complete license is in
[LICENSE](LICENSE). No later-version option is granted by that identifier.

## Included implementation

The Swift package uses macOS frameworks supplied by the operating system,
including SwiftUI, AppKit, CoreBluetooth, CryptoKit and UserNotifications. It
does not vendor those frameworks or depend on external Swift packages. Python
utilities use the standard library.

System symbols and interface typography are rendered through Apple's platform
APIs. Application branding, maintained vector artwork and generated design
explorations are project assets; they are not copies of the hearing-aid vendor's
logo or product photography. Asset-generation provenance should accompany the
source artwork when it is included in a release.

Protocol identifiers, layouts and behavioral findings are documented with
artifact hashes and bounded evidence. The source contains an independent
implementation and synthetic tests, rather than redistributed SDK assemblies
or decompiled vendor classes.

## Research material excluded from distribution

The following are private research inputs, not public-source dependencies or
licensed project assets:

- Oticon Companion APKs, extracted libraries, decompiled code and decoded
  packaged resources.
- Authentication secrets, real device identifiers, captures and clinical data.
- Noah/Genie installers, fitting modules, firmware packages and vendor artwork.
- The HIMSA Audiogram 502 schema used for an optional local validation check.

The public app does not include or automatically fetch these materials.
Advanced UTL functionality depends on a compatible authentication credential
supplied separately by the owner; the source distribution does not grant or
provide that credential. The project's GPL license does not relicense those
excluded inputs.

HIMSA XML export is an independently implemented interchange writer. The schema
must be obtained separately for its optional validation test. Noah import and
clinical fitting are not established by a passing schema check.

## Contributions

Add provenance and applicable notices when introducing a dependency or asset.
Contribute original implementations and synthetic fixtures; do not copy vendor
code or bundle material merely because it was accessible during analysis. See
[CONTRIBUTING.md](CONTRIBUTING.md) and the
[public-source audit](docs/public-release-audit.md).

## Sparkle

Sparkle 2.10.0 provides signed application updates. Copyright Sparkle Project.
Distributed under its MIT license and the notices in [Sparkle license](docs/licenses/Sparkle.txt).
Source: https://github.com/sparkle-project/Sparkle/tree/2.10.0.
