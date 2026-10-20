# Hardware verification

Local evidence, 2026-10-20. This is actual execution of our own native CoreBluetooth probe, not a claim inferred from the Android APK.

## Verified

- Bluetooth permission was available; macOS returned both already-connected hearing aids to our independent process.
- Each exact selected aid accepted a CoreBluetooth connection and full GATT discovery. Both report manufacturer Oticon and model Intent 3.
- Both expose the SDK's direct remote service and its main volume, range, active-program, available-program and side characteristics. The newer UTL service is also present.
- Both permitted all allowlisted reads; the direct-control values decode using the recovered SDK formats. Main volume range is −8 to +4 on this pair; the initial level was 0, unmuted, and a single program ID 0 was reported. This is an aid-reported step range, not a clinically calibrated decibel claim.
- Standard Battery, Device Information, VCS, HAS and UTL information reads also succeeded. Battery notifications were enabled successfully.
- The phone's `com.oticon.app` still had a GATT connection to each aid in the snapshot after both Mac probes. This demonstrates coexistence during these bounded checks; it is not a long-term reliability test.
- No remote setting, fitting, firmware, pairing/reset or audio-routing command was issued in these probes. Disconnecting the probe releases its CoreBluetooth client, not the macOS system's existing hearing-device connection.

## Private evidence references

The following full logs contain local identifiers and remain ignored:

- `mac-connect-first-001.jsonl`: SHA-256 `37f420073589028854737f8025d8877bea62ed4c31948d3515c2952c4aa6013e`, 1 connection, 93 inventoried characteristics, 16 successful values, 0 GATT errors.
- `mac-connect-second-001.jsonl`: SHA-256 `11576a2fd0187e144ed2804b2dd49c5a316c3222cdfebecf7f7e0af90883ebbf`, 1 connection, 93 inventoried characteristics, 16 successful values, 0 GATT errors.
- Post-probe phone state: `android-bluetooth-after-mac-probes.txt`, SHA-256 `03b029f38321469dd0d7b70e313aed8e1ae8ed5bd7f21e26eed01d3073d6f998`.

## Not yet established

- Program switching beyond the current single program; no alternative program is configured on the tested pair.
- Long-term simultaneous operation is untested; the native GUI did establish both application-level connections at once.
- Long-term reconnect behavior, sleep/wake, loss of one aid, or audio handoff.
- Every Companion feature. Later intentional UTL consumer EQ reads are described below; no extracted app secret is needed for the initial direct GATT reads above.

## Native dashboard and user confirmation

The running two-aid GUI was inspected through its own accessibility tree and an onscreen window capture. Both cards showed live Intent 3 data. Standard PACS Sink Audio Locations (`1850` / `2BCA`) independently identified Left and Right; the application does not guess sides from discovery order or the legacy ear byte. The UUID and bit assignments come from [Bluetooth SIG Assigned Numbers](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/index-en.html).

The user explicitly confirmed **“Volume and mute both work”** after lowering/restoring volume and trying mute/unmute in Open Companion. The GUI also showed “Unmute confirmed by hearing aid” for each side. This establishes physical/perceived control for the tested hardware as well as software readback. It does not validate every feature in Companion or every aid/firmware version.

The final source adds stale-state invalidation after ambiguous writes, disconnects and service changes. No fitting, firmware or persistent UTL setting operation was used.

After the final build and relaunch, the native dashboard again showed both Left/Right aids connected and unmuted. The private final accessibility snapshot and screenshot are `gui-final-ax.txt` and `mac-dashboard-final.png`. The source passes 28 Swift tests and six Python tests; bundle/signature checks also passed.

## Consumer equalizers, program names and audiograms

The 0.2.0 GUI read program metadata from both aids. Both reported the name
**Geral**. The metadata selector was restored to `0xff`; these queries do not
select a different listening program. Both aids still reported the same single
configured direct-service program.

Intentional **Load advanced controls** queries completed mutual UTL
authentication, transport negotiation, dynamic service discovery, an ordinary
nonexclusive Interactive session and type-5 COMMAND transactions. The actual
registry advertises session service 1.1 and equalizer service 1.2. Both aid
cards subsequently displayed **Advanced equalizers read from hearing aid**,
with populated microphone EQ controls; that status is set only after both
microphone and streaming EQ reads decode successfully. This establishes actual
read interoperability, rather than only a synthetic handshake.

The first prototype authenticated but omitted the consumer transaction wrapper
and received `0xD9`. A subsequent read exposed the older EQ contract's unused
range vectors. Both issues were resolved against the installed SDK's consumer
paths. Contract 1.x uses the SDK's fixed consumer limits and historical gain
scale; the UI identifies those limits rather than labeling them device-reported.
No exclusive/fitting state, semaphore takeover, RAM/NVRAM transaction or reset
was used. The agent's hardware checks issued no EQ change; user-visible
adjustments still require **Apply equalizer**. Physical/perceived EQ effects
remain pending user confirmation.

During the user's subsequent GUI test, the left aid displayed **Microphone EQ
confirmed by hearing aid**. That status requires the requested eight
coefficients to match the aid's UTL readback exactly. It establishes a real
microphone-EQ write/readback, while audible perception remains a separate user
check. Streaming-EQ writes and right-aid EQ writes have not yet been verified.
The additional private snapshot is `gui-eq-user-check-ax.txt`.

Private GUI evidence: `gui-consumer-connected-ax.txt`,
`gui-left-consumer-events-ax.txt`, `gui-left-rangefix-advanced-ax.txt`,
`gui-both-rangefix-recheck-ax.txt`. The last snapshot shows both aid cards
connected, both program names and both successful advanced-read statuses.
Snapshots contain local device data and remain ignored.

The native **Audiogram** window was opened and captured with an empty draft.
Its table, plot, measurement conditions and export controls were inspected;
no real exam values were entered or saved. `audiogram-blank.png` and
`audiogram-blank-ax.txt` are private UI evidence. Persistence and XML export were
tested using synthetic records, including actual validation against the
official HIMSA 502 XSD. Noah-side import and audiogram-based fitting are untested.

Local checks for this revision: **63 Swift tests and six Python tests passed**,
the native app built, and signature verification passed. Later builds support
an optional stable Apple Development signing identity. The latest running
bundle uses that identity and again has Bluetooth permission and both aid
connections. Fresh pairing, long-term sleep/reconnect behavior and compatibility
with other aid models remain untested.
