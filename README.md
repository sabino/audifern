# Audifern

[![CI](https://github.com/sabino/audifern/actions/workflows/ci.yml/badge.svg)](https://github.com/sabino/audifern/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/sabino/audifern)](https://github.com/sabino/audifern/releases/latest)

<img src="branding/mark.svg" width="76" alt="Audifern fern and listening mark">

**A quiet place to control your hearing aids on the Mac.**

Audifern is an independent native macOS app for compatible Oticon hearing aids.
Keep everyday listening controls close, then open sound adjustments, device
information or protocol diagnostics when you need them. Built with SwiftUI and
CoreBluetooth; no account, cloud service or analytics.

This is an early project tested with one Intent 3 pair. Volume and mute have
been physically confirmed; consumer EQ writes have matched aid readback.
Other models, fresh pairing and long-term reliability need further testing.
Audifern is not affiliated with or endorsed by Oticon or Demant.

![Audifern in light mode, using synthetic preview devices](docs/images/audifern-light.png)

[Dark mode in Português (Brasil)](docs/images/audifern-dark.png) ·
[Settings in Español](docs/images/audifern-settings-es.png) ·
[Design concept, artwork and prompts](docs/design/prompts.md)

## Around the app

One window keeps the essentials separate from the details:

| Page | What you can do |
| --- | --- |
| **Listen** | Check both connections and batteries; adjust volume and mute, separately or together. |
| **Sound** | Edit microphone and streaming EQ, load supported SpeechBooster and source controls. |
| **Programs** | Inspect fitted programs and save local sound presets. |
| **Devices** | Read model, software, firmware and available device diagnostics. Identifiers are hidden by default. |
| **Audiogram** | Record an existing exam, plot it, and import or export it. |
| **Settings** | Choose System, Light or Dark appearance; language; battery alerts; privacy preferences. |
| **Developer** | Expand service information, the GATT inventory and local session diagnostics. |

The initial languages are **English, Português (Brasil) and Español**, with
system-language selection. Appearance follows macOS unless you choose an
override. Closing the window leaves connections and battery monitoring in the
menu bar; **Quit Audifern** ends them.

## Download and install

[Download the latest release](https://github.com/sabino/audifern/releases/latest)
for **macOS 14 or later**, on Apple Silicon or Intel. Open the universal DMG and
drag Audifern to Applications; a ZIP is also available. Downloads include
checksums, build information, the license and exact source links.

The initial downloads are **ad hoc signed, not Apple-notarized**. Read the
[installation and release guide](docs/distribution.md) for macOS's per-app
Open Anyway flow, continuous-build artifacts and tag-triggered releases.
Advanced credentials are provisioned locally and are excluded from downloads.

## Build and try it

Requires **macOS 14 or later**, a **Swift 6** toolchain from Xcode or its command
line tools, and Python 3 for the optional audits/extractor tests. The Swift
package has no external package dependencies.

```sh
./scripts/build-app.sh
open "build/Audifern.app"
```

The build script signs locally with an ad hoc identity by default. You do not
need an Apple Developer account to build it. For repeated development builds,
set `AUDIFERN_SIGN_IDENTITY` to a stable local signing identity to help preserve
macOS Bluetooth permissions. `AUDIFERN_BUILD_JOBS` defaults to two.

To explore the interface without connecting hearing aids:

```sh
open -n "build/Audifern.app" --args --demo
```

Demo mode uses synthetic devices and isolated data. It does not open Bluetooth
connections or read the regular audiogram library.

For real devices, grant Bluetooth access when macOS asks. The tested aids were
already paired through **System Settings → Accessibility → Hearing Devices**.
Discovery can also recover an existing macOS connection when an aid is not
advertising. A complete first-time pairing flow is not established.

## Controls and their limits

| Capability | Current scope |
| --- | --- |
| Volume and mute | Direct BLE controls, per aid or linked, using reported limits and readback. |
| Program selection | Existing fitted programs only; more than one program has not been physically tested. |
| Consumer EQ | Three bands for microphone and streaming; advanced authentication required for supported UTL controls. |
| SpeechBooster | Available only when the current program reports support and its controls can be loaded. |
| Tinnitus relief | Separate source volume/mute for an already fitted tinnitus program; unavailable when unsupported. |
| Streaming-source volume | Separate from EQ and Mac media volume; restricted to supported streamer programs. |
| Battery | Per-ear percentage, optional estimated time left and local milestone alerts. An estimate requires valid telemetry. |
| Consumer program export | Readable program metadata and current consumer adjustments, not a clinical fitting backup. |
| Audiograms | Local exam records and JSON/HIMSA XML export; no tones, diagnosis or prescription calculation. |

Edits to EQ are drafts until **Apply**. Linked actions check both aids and
confirm each write; a failure can leave an earlier write applied, and the app
reports that partial result. Restore actions reset consumer adjustments after
confirmation, preserving clinical fitting and tinnitus therapy settings.

A **local sound preset** recalls adjustments to an existing program. It does
not create a fitted program inside the hearing aids. The consumer protocol
research has not established an add/create/clone-program operation. See
[program data and fitting boundaries](docs/program-data.md).

Audio streaming remains with macOS. Clinical fitting, audiogram-to-gain
conversion and firmware updates are not implemented. A complete readout of
installed firmware has not been established. Tinnitus controls cannot enable
an unfitted therapy; use the program's fitted level and daily-use limits.

### Advanced authentication

Basic direct BLE volume/mute does not require a cloud login or a bundled secret.
Advanced UTL features require a compatible authentication key supplied locally
by the device owner. **The key, vendor APK and SDK are not included.**

If you already have the inspected private SDK reconstruction, the offline
provisioning helper can read its key without printing or embedding it:

```sh
python3 scripts/provision-utl-key.py /path/to/private/UtlChallengeAuthentication.cs
```

This helper is specific to the researched SDK format. It is not a download or
a general key-acquisition service. Without compatible local authentication,
advanced features remain unavailable. See [advanced controls](docs/advanced-controls.md).

## Privacy

Your presets, exams, preferences and authentication material stay on your Mac.
There is no automatic log upload. Explicit exports and developer probes can
contain sensitive information; review them before sharing. Public screenshots
must use demo data. See [the privacy guide](PRIVACY.md) and
[public-source audit](docs/public-release-audit.md).

## Development

```sh
swift test --jobs 2
python3 -m unittest discover -s Tests -p 'test_*.py'
python3 scripts/audit-localization.py --strict
python3 scripts/audit-public-source.py \
  --allow-identity "$(git show -s --format='%an <%ae>' HEAD)"
```

Review the contributor identity before allowing it. The privacy checker flags
embedded signatures for review; see [public-history verification](docs/public-release-audit.md#public-distribution)
for the owner's intentionally signed commits.

The optional HIMSA schema check needs a locally acquired `Audiogram-1-502.xsd`:
set `HIMSA_AUDIOGRAM_SCHEMA` to its path when running Swift tests. The schema is
not distributed. CI tests synthetic protocol/data cases, audits translations,
tests both CPU architectures, packages downloadable universal DMG/ZIP artifacts
and verifies signatures; it cannot establish physical aid behavior. [Hardware verification](docs/hardware-verification.md) distinguishes
audible confirmation, device readback, synthetic tests and remaining gaps.

Contributions are welcome: start with [CONTRIBUTING.md](CONTRIBUTING.md), and
use [SECURITY.md](SECURITY.md) for a private security report.

## License and identity

The project's original implementation is licensed under **GNU GPL version 3
only** (`GPL-3.0-only`); see [LICENSE](LICENSE). This does not grant a license to
vendor SDKs, authentication material, firmware or other excluded research inputs.
[Third-party notices](THIRD_PARTY_NOTICES.md) describe those boundaries.

Audifern is a project-specific name and brand, separate from the vendor's
Companion app. No trademark clearance or vendor endorsement is implied.

## Research

The implementation grew from inspection of an installed Android application
and bounded checks on the owner's hearing aids. Protocol findings are tied to
artifact identities and retained evidence, with unsupported operations kept
separate from implemented controls.

- [Direct BLE controls](docs/legacy-protocol.md) and [UTL transport/authentication](docs/managed-protocol.md)
- [Consumer EQ and presets](docs/advanced-controls.md), [SpeechBooster](docs/speech-booster.md), [source controls](docs/tinnitus-controls.md)
- [Program data](docs/program-data.md), [audiograms](docs/audiogram.md), [Noah/fitting research](docs/noah-investigation.md)
- [Battery telemetry](docs/battery-telemetry.md), [identification](docs/device-identification.md), [device metadata](docs/device-metadata.md)
- [Firmware investigation and unresolved readout](docs/device-research.md), [hardware evidence](docs/hardware-verification.md)
