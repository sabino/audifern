# Audifern user guide

Audifern keeps everyday hearing-aid controls on your Mac. Your settings,
presets and hearing-test records stay local; there is no Audifern account.

## Install

Use macOS 14 or later on an Apple Silicon or Intel Mac. Download the latest
[notarized release](https://github.com/sabino/audifern/releases/latest), open
the DMG, and drag Audifern to Applications.

For package-manager installation, use
`mt install --cask sabino/tap/audifern` or
`brew install --cask sabino/tap/audifern`.

## Connect your hearing aids

1. Keep the hearing aids awake and near your Mac.
2. Open Audifern and allow Bluetooth access when macOS asks.
3. In **Sound**, choose **Find hearing aids**, scan, and select your aids.
4. Wait for each device's available controls to load before making adjustments.

The tested Intent 3 pair was already paired through **System Settings →
Accessibility → Hearing Devices**. First-time pairing and other models are
not yet verified.

Volume and mute use direct Bluetooth controls. EQ, SpeechBooster, runtime
telemetry and other advanced controls need a compatible local authentication
credential. It is not included in the download. Without it, unavailable controls
remain disabled; see [advanced authentication](advanced-controls.md).

## Everyday controls

### Volume, mute and grouping

Use the horizontal slider or its **− / +** buttons. The level is a device step,
not a percentage or calibrated gain in dB. The scale shows the aid's reported
limits and its zero point. **Mute** preserves the level for when you unmute.

Choose **Together** above the devices to group all sound sections, including
EQ. Grouped volume preserves the difference between the ears. Choose
**Separate** for individual controls. A section's own selector can override
the master; **Mixed modes** means the sections currently differ.

### Programs and SpeechBooster

Colored shortcuts choose programs already fitted to both hearing aids. Expand
the hearing-aid card to choose which shortcuts appear, keeping at least one.
With one choice, the current program is shown without a switcher. **Library →
Programs** keeps the individual-ear program controls available.

SpeechBooster reads automatically after connecting or changing programs when
supported. Its microphone button opens the controls. If a read fails, use
**Retry SpeechBooster**. Audifern cannot create a new clinical program.

### Equalizers and presets

In **Sound → Equalizers**, choose **Microphone** or **Streaming**. Use three
tone controls or switch to **8 bands**. Together shows one editor; Separate
shows both ears side by side. Hover over the status symbol for each ear's read
result, or use its refresh button to retry.

EQ edits remain drafts until **Apply**. **Reset EQ** offers a neutral consumer
EQ; **Restore sound defaults** offers broader consumer resets after confirmation.
Neither is a clinical fitting restore. If only part of a grouped change
succeeds, Audifern reports which device needs attention.

**Save sound** stores a local preset for an existing program. Review and reuse
it in **Library**. A preset does not add a program to the hearing aids.

Source volume is separate from EQ and only available for supported streamer
programs. Tinnitus controls require an already fitted, supported therapy program.

## Batteries and quick access

Each ear shows its battery percentage. When valid runtime telemetry is
available, time left counts down from a timestamped reading and refreshes
about hourly while connected. Hover over it to see when it was read.

In **Settings → Battery alerts**, enable the notifications and thresholds you
want. macOS notification permission is required.

In **Settings → Quick access**, customize the menu-bar panel and shared widget
controls. Add desktop widgets through macOS's widget gallery. On macOS 26 or
later, add controls through **Control Center → Edit Controls**. Audifern must
remain running with readable, connected aids for sound actions.

Closing the main window keeps Audifern running. **Quit Audifern** ends its
connections and monitoring.

## Automatic connection and audio

Automatic reconnection starts off. In **Settings → Connections**, remember
your chosen aids, then enable nearby retries or wake/unlock attempts if wanted.
Pause persists until you resume or reconnect manually. A signal threshold can
favor closer devices; Bluetooth signal strength does not measure exact distance,
rooms or floors.

A control connection does not mean Mac audio is using the hearing aids. Check
**Control Center → Sound → Output** for audio routing. Mac/Android handoff is
not automatic or verified, and pausing Audifern may leave the system's audio
connection active. See [connection and audio details](connections.md).

## Hearing profile

Keep your hearing-test results in **Hearing profile → Audiograms**. Local
fitting plans organize results, devices and listening goals for discussion.
Readable checkpoints can be saved and compared privately.

These records do not calculate a prescription, program a clinical fitting,
restore a complete fitting or install firmware.

## If something is unavailable

- **No aids found:** check Bluetooth permission and whether the aids are awake,
  nearby and already paired with macOS.
- **Connected, but no audio:** check the Mac's audio output separately.
- **EQ or SpeechBooster disabled:** wait for feature reads, check local advanced
  authentication and whether the current program supports the control.
- **Read error:** use the affected control's retry action. Details are available
  in **Settings → Diagnostics**.
- **Need another setting:** search in **Help → Audifern Help**. The Mac Help
  menu also accepts feature names in English, Português (Brasil) and Español.

Review diagnostics and exports before sharing them. Audifern never uploads
logs automatically. See [Privacy](../PRIVACY.md) or [report an issue](https://github.com/sabino/audifern/issues).
