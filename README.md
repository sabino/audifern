# Open Companion

A native macOS companion for Oticon hearing aids, built with SwiftUI and CoreBluetooth. This project began by inspecting the owner's installed Oticon Companion Android app with **reverse-engineer-anything (REA)** and testing an independent Mac connection to the owner's Intent 3 pair.

The Mac has successfully read both aids' model, battery, firmware, current volume, volume range and program over BLE while the Android Companion app retained its own connections. The initial app uses the direct Oticon remote-control GATT service. It does not need a cloud login or an embedded UTL authentication secret for that connection path.

## Build and run

Requires Xcode command-line tools / Swift 6 and macOS 14 or later. Physical verification so far is on this development Mac and one Intent 3 pair.

```sh
./scripts/build-app.sh
open "build/Open Companion.app"
```

Allow Bluetooth access if macOS asks. The hearing aids used here were already paired in **System Settings → Accessibility → Hearing Devices**. Open Companion can find them through macOS's existing connection even when they are not advertising. Fresh-device pairing has not been tested.

Builds use ad hoc signing by default. For repeated development builds, set `OPEN_COMPANION_SIGN_IDENTITY` to your local Apple Development identity when running the build script. A stable signing identity avoids treating each changed executable as a different Bluetooth permission requester. Switching identity may require granting the app Bluetooth permission again.

The native app provides simultaneous Left/Right connections, live battery and volume, per-aid and paired volume/mute buttons, available-program selection, refresh, discovery and an optional GATT inspector. The user confirmed that volume and mute produce the expected audible changes on the tested Intent 3 pair. Program switching beyond its single configured program remains untested.

### Sound controls

Each aid card shows its current **Program** name, read from the aid; the tested pair reports **Geral**. Below it, **Equalizer → Microphone / Streaming** provides **Lows, Mids and Highs**. Use **Load advanced controls** to authenticate a free consumer UTL channel and read the available EQs. Sliders edit a draft; **Apply equalizer** explicitly sends it and checks readback. Loading controls performs no EQ or clinical-fitting write.

**Sound presets on this Mac** saves the current program, volume, mute and loaded equalizers under a name. Selecting a preset leaves the aids unchanged; **Apply** restores it after checking both sides against the current program, ranges and EQ scale. These local presets adjust an existing fitted program. They do not add a program to the hearing aids' firmware.

Use the toolbar **Audiogram** button to enter, plot, save, update, import or export exam results. Air/bone conduction, masked results and no-response marks are recorded separately. Saving an exam makes its reference available to a local sound preset. The optional **HIMSA XML** export follows Audiogram 502; Noah-side import remains untested. Exam thresholds are stored as dB HL and are not converted into EQ gain. See [audiogram details](docs/audiogram.md).

Remote controls use reported ranges and available programs; a write acknowledgment is followed by readback. Paired preset application is serial, not atomic: a failure may leave earlier confirmed settings applied, and the app reports that outcome.

The program IDs in the direct Oticon service and the standard Bluetooth Hearing Access service use different numbering on the tested pair. The UI must not mix them. Only one Oticon program was reported on this pair; additional programs cannot be invented by the app.

## Local checks

```sh
swift test --jobs 2
python3 -m unittest discover -s Tests -p 'test_*.py'
```

For the optional HIMSA schema check, set `HIMSA_AUDIOGRAM_SCHEMA` to a locally acquired `Audiogram-1-502.xsd` when running `swift test`. The schema is not redistributed. [Hardware verification](docs/hardware-verification.md) separates physical tests, aid readback, synthetic protocol tests and untested features.

For a bounded discovery-only hardware probe that creates no main window:

```sh
mkdir -p private
"build/Open Companion.app/Contents/MacOS/OpenCompanion" \
  --probe-seconds 18 \
  --probe-output "$PWD/private/mac-scan-new.jsonl"
```

Add `--probe-connect EXACT_COREBLUETOOTH_UUID` to connect only to an explicitly selected recovered/discovered aid and read the status allowlist. Probe output files must be new; they are created with mode 0600. Probe mode never issues remote-control setting writes. Logs contain local device identifiers; keep them private.

## Research and limits

- [Investigation questions and artifact identity](docs/investigation-plan.md)
- [Direct remote-control protocol](docs/legacy-protocol.md)
- [Managed code, UTL framing and authentication](docs/managed-protocol.md)
- [Packaged configuration, platform support and feature contracts](docs/resource-findings.md)
- [Equalizers, ordinary UTL transactions and local presets](docs/advanced-controls.md)
- [Local audiograms and HIMSA XML export](docs/audiogram.md)
- [Noah installer, fitting architecture and Genie 2](docs/noah-investigation.md)
- [Actual hardware checks and their limits](docs/hardware-verification.md)

The installed app is .NET MAUI. Its ARM64 split contains a Mono assembly store; the independent offline extractor recovered 477 managed assemblies without executing target code. Packaged configuration supplies additional UTL contracts for battery, volume, programs, equalizers and other features. Those contracts are research findings, not a claim that all features work in this app.

Advanced consumer EQ uses the recovered UTL framing, mutual challenge authentication, an Interactive session and COMMAND transactions. It never opens an exclusive session, takes over another client's channel or exposes generic RAM/NVRAM operations. The required key stays in a private local configuration, outside the app bundle and Git. To provision it from the owner's privately acquired SDK decompilation:

```sh
python3 scripts/provision-utl-key.py /path/to/private/UtlChallengeAuthentication.cs
```

Audio streaming remains with macOS's hearing-device support. Clinical fitting and firmware updates are not implemented. The supplied Noah installer was extracted and examined without execution: it supplies the database/module host and audiogram formats, rather than Oticon's model-specific fitting module. Creating or changing a fitted program from an audiogram needs further investigation of Genie 2 and its device programming path.

This is an independent project. Proprietary APKs, extracted libraries/code, decoded resources, device identifiers and captures remain in ignored `private/`. No proprietary implementation, credentials or private device data belong in Git. The parent Leapmotor project is separate and unchanged.
