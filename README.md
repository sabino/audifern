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

The native app provides simultaneous Left/Right connections, live battery and volume, per-aid and paired volume/mute buttons, available-program selection, refresh, discovery and an optional GATT inspector. Remote controls use only the direct service's reported volume range and available programs; setting changes are initiated explicitly in the UI. A write acknowledgment is followed by readback. The user confirmed that volume and mute produce the expected audible changes on the tested Intent 3 pair. Program switching beyond its single configured program remains untested.

The program IDs in the direct Oticon service and the standard Bluetooth Hearing Access service use different numbering on the tested pair. The UI must not mix them. Only one Oticon program was reported on this pair; additional programs cannot be invented by the app.

## Local checks

```sh
swift test --jobs 2
python3 -m unittest discover -s Tests -p 'test_*.py'
```

Local validation at this revision: **28 Swift tests and 6 Python tests passed**, the app bundle built and passed ad hoc signature verification, and the user confirmed real volume/mute effects. Both aid connections were rechecked after the final rebuild.

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
- [Actual hardware checks and their limits](docs/hardware-verification.md)

The installed app is .NET MAUI. Its ARM64 split contains a Mono assembly store; the independent offline extractor recovered 477 managed assemblies without executing target code. Packaged configuration supplies additional UTL contracts for battery, volume, programs, equalizers and other features. Those contracts are research findings, not a claim that all features work in this app.

The pure Swift UTL codec is an optional foundation for further investigation. The running app does not open a UTL channel or include the vendor's embedded secret. Audio streaming remains with macOS's hearing-device support. Clinical fitting, firmware updates and generic memory/settings writes are outside the implemented app.

This is an independent project. Proprietary APKs, extracted libraries/code, decoded resources, device identifiers and captures remain in ignored `private/`. No proprietary implementation, credentials or private device data belong in Git. The parent Leapmotor project is separate and unchanged.
