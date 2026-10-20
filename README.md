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

The two ear drawings stay visible, with actual Left/Right sides in fixed columns.
The links **between** the columns independently join **volume/mute, program,
SpeechBooster, microphone EQ and streaming EQ**. Switching a link leaves device
settings unchanged. Linked volume uses one shared control bar; linked +/−
preserves the current left/right balance; each action checks both aids and their
reported limits, then confirms each write. If one side fails, the app reports
the partial outcome rather than claiming both changed.

**SpeechBooster** uses the installed SDK's consumer control path and each aid's
reported adjustment limits. Load the device features to read its state; the
toggle is available only for a program that reports SpeechBooster support.
Its own link lets either side's toggle change both aids. Each aid confirms its
own change, and a failed second-side request is reported as a partial result.

Each side shows its current **Program** name, read from the aid; the tested pair reports **Geral**. Linked program selection requires the same reported program ID and name on both aids. **Microphone EQ** and **Streaming EQ** each provide **Lows, Mids and Highs** side by side. Use **Load advanced controls** to authenticate a free consumer UTL channel and read the available EQs. Sliders edit a draft; **Apply** explicitly sends it and checks readback. With an EQ link on, editing either side updates the shared draft and **Apply to both** converts the requested dB values using each aid's own scale and limits. Loading controls performs no EQ or clinical-fitting write.

Each ear's **Restore…** menu can reset volume/mute, either EQ, SpeechBooster or
all those sound controls. Each EQ also has **Reset EQ…**, and **Restore both
ears…** resets the pair. A confirmation describes the selected target and
settings. Defaults mean volume **0**, unmuted, EQ **0 dB**, and SpeechBooster
off in supported programs. Controls must be loaded and their limits must allow
these values. This restores consumer sound adjustments, preserving fitted
programs, clinical fitting, tinnitus settings and saved audiograms.

**Sound presets on this Mac** saves the current program, volume, mute and loaded equalizers under a name. Selecting a preset leaves the aids unchanged; **Apply** restores it after checking both sides against the current program, ranges and EQ scale. These local presets adjust an existing fitted program. They do not add a program to the hearing aids' firmware.

Use the toolbar **Audiogram** button to enter, plot, save, update, import or export exam results. Air/bone conduction, masked results and no-response marks are recorded separately. Saving an exam makes its reference available to a local sound preset. The optional **HIMSA XML** export follows Audiogram 502; Noah-side import remains untested. Exam thresholds are stored as dB HL and are not converted into EQ gain. See [audiogram details](docs/audiogram.md).

Remote controls use reported ranges and available programs; a write acknowledgment is followed by readback. Paired preset application is serial, not atomic: a failure may leave earlier confirmed settings applied, and the app reports that outcome.

### Battery and device information

Both cards display independent battery percentages, estimated time left when
valid charge/current telemetry is available, and manufacturer/model/firmware/
serial-number fields. **Read device details** loads Oticon's own identification
record when the standard Bluetooth serial field is absent, as on the tested
Intent 3 pair. **Estimated time left** follows Companion's reported
charge-to-current calculation; it is not a percentage-to-hours conversion or a
guaranteed duration. Charging or invalid/unknown telemetry suppresses the estimate.
An explicitly loaded consumer session can refresh telemetry every five minutes;
standard battery notifications continue without that channel.

Use the toolbar **Battery alerts** button or **Settings** to enable local macOS
notifications and select **50%, 30%, 20%, and below 10%** independently, for either
ear. macOS permission is requested only when you enable alerts. Monitoring stays
active while the app runs, including with its main window closed. Reconnects do
not erase each aid's alert history; a measured recharge re-arms milestones.
The Settings window includes a user-initiated test alert.

### Menu bar

The ear icon in the macOS menu bar shows connection and per-ear battery status.
Closing the main window keeps both Bluetooth connections and battery monitoring
running. Choose **Open Companion** from the icon to reopen the window; audiograms
and battery alerts are available there too. **Quit Open Companion** explicitly
ends the app and monitoring.

The program IDs in the direct Oticon service and the standard Bluetooth Hearing Access service use different numbering on the tested pair. The UI must not mix them. Only one Oticon program was reported on this pair; additional programs cannot be invented by the app.

## Local checks

```sh
swift test --jobs 2
python3 -m unittest discover -s Tests -p 'test_*.py'
```

For the optional HIMSA schema check, set `HIMSA_AUDIOGRAM_SCHEMA` to a locally acquired `Audiogram-1-502.xsd` when running `swift test`. The schema is not redistributed. [Hardware verification](docs/hardware-verification.md) separates physical tests, aid readback, synthetic protocol tests and untested features.

Current validation: **122 Swift tests and six Python tests passed**. The signed
0.4.0 app connected to both Intent 3 aids and displayed independent central
links and restore controls. Closing and reopening through its menu bar retained
both connections in the same process. A linked streaming-EQ operation during
the GUI session reported two confirmed changes. Audible SpeechBooster effects,
restore-default operations on hardware and native notification delivery still
need the user's check. See the hardware ledger for evidence boundaries.

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
- [Battery telemetry and remaining-time calculation](docs/battery-telemetry.md)
- [Local notification thresholds and permissions](docs/battery-alerts.md)
- [Per-aid identification and serial numbers](docs/device-identification.md)
- [SpeechBooster and linked controls](docs/speech-booster.md)
- [Actual hardware checks and their limits](docs/hardware-verification.md)

The installed app is .NET MAUI. Its ARM64 split contains a Mono assembly store; the independent offline extractor recovered 477 managed assemblies without executing target code. Packaged configuration supplies additional UTL contracts for battery, volume, programs, equalizers and other features. Those contracts are research findings, not a claim that all features work in this app.

Advanced consumer EQ uses the recovered UTL framing, mutual challenge authentication, an Interactive session and COMMAND transactions. It never opens an exclusive session, takes over another client's channel or exposes generic RAM/NVRAM operations. The required key stays in a private local configuration, outside the app bundle and Git. To provision it from the owner's privately acquired SDK decompilation:

```sh
python3 scripts/provision-utl-key.py /path/to/private/UtlChallengeAuthentication.cs
```

Audio streaming remains with macOS's hearing-device support. Clinical fitting and firmware updates are not implemented. The supplied Noah installer was extracted and examined without execution: it supplies the database/module host and audiogram formats, rather than Oticon's model-specific fitting module. Creating or changing a fitted program from an audiogram needs further investigation of Genie 2 and its device programming path.

This is an independent project. Proprietary APKs, extracted libraries/code, decoded resources, device identifiers and captures remain in ignored `private/`. No proprietary implementation, credentials or private device data belong in Git. The parent Leapmotor project is separate and unchanged.
