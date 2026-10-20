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

## Linked controls, SpeechBooster, identification and battery (0.3.0)

The native dashboard now offers a persistent **Link ears** switch. Linked mode
renders one volume/mute bar; separate mode renders the individual controls.
Changing modes performs no hearing-aid write. The live GUI exposes the controls
with both aids connected. A bounded GUI check enabled linked mode and verified
exactly one shared control bar, with both separate volume/mute bars hidden,
then restored the user's previous mode. It pressed no sound-changing control.
Private UI evidence is `gui-030-linked-mode-ax.txt` / `.png`.
New linked operations use fresh reads, whole-pair
range preflight and sequential confirmed writes; physical linked operation
and audible SpeechBooster effects remain pending the user's test.

Both aids returned SpeechBooster state using the recovered consumer protocol.
Each active program reports whether it supports the toggle. All automated
hardware checks in this feature pass were reads; the agent did not toggle
SpeechBooster or change volume/mute. User tests are separate from these checks.

The standard Device Information serial characteristic `2A25` is absent from
both earlier 93-characteristic inventories. Oticon Companion instead reads
the per-aid serial from HIID entry 2003. The new read-only `detect_info`
`get_hiid` path populated **two distinct serial numbers** in the native cards.
Manufacturer, model and firmware remain separate per-connection fields.
Actual identifiers and full identification data are excluded from this report
and event logs.

The actual battery 2.0 operation returned 16 bytes. The declared schema consumes
13; the captured trailing three bytes were nonzero. Inspection of the shipped
decoder established that it returns the mapped fields without requiring end
of input. The implementation therefore accepts the minimal 13-byte form and
the observed 16-byte form specifically for contract 2.0, while rejecting other
lengths. Those three bytes remain uninterpreted; they are not described as
zero padding or extra Boolean fields.

With that correction, both aids supplied valid remaining charge/current
telemetry and the dashboard displayed **independent estimated times left**.
Estimates follow the SDK's charge/current calculation, are suppressed while
charging or invalid, and expire after ten minutes without a successful update.
No duration is derived from the battery percentage. Standard percentage
notifications and existing authenticated-session polling supply later updates.

Private evidence includes `gui-030-left-telemetry-events-ax.txt`,
`gui-030-left-final-features-ax.txt`, `gui-030-both-final-features-ax.txt`, and
`gui-030-final-dashboard.png`. These contain private device identifiers and
measurements and remain ignored. Source fixtures use synthetic values.
The final signed build was rechecked in `gui-030-stable-handoff-ax.txt`: both
connections, serials and estimates were populated. Routine command progress
was removed from the primary controls and retained only in the debug log.

The native Settings window was opened and captured. It showed independent
50%, 30%, 20% and strictly-below-10% switches, left/right selection, optional
sound and a test button. Its initial macOS permission state was not requested.
No automated permission request or real test notification was sent. Settings
snapshots are `gui-030-battery-settings-ax.txt` / `.png`. Fake-delivery tests
cover threshold crossings, delivery failures, reconnects, recharge hysteresis
and clearing live readings on disconnect while preserving history. Monitoring
is owned by the app lifetime, including while its main window is closed.

Validation: **111 Swift tests and six Python tests passed**, including HIMSA
schema validation. The 0.3.0 app built with the stable local development identity
and passed signature verification. Delivered notifications, physical paired
changes and audible SpeechBooster confirmation remain user checks.

## Central links and menu bar (0.4.0)

The running native app connected to both aids and displayed two ear drawings
with separate volume/mute, program, SpeechBooster, microphone-EQ and streaming-EQ
links in the middle. Its columns use the standard reported physical side, not
connection or discovery order. Both EQ sources are visible together. Each ear
has a consumer restore menu, with individual EQ reset buttons and a pair-wide
restore action. Reset actions ask for confirmation and describe their targets.

During the GUI session, streaming EQ was linked and the app reported **All 2
sound changes confirmed by the hearing aids**. This status requires each
requested EQ to complete its write and exact readback. The agent's automated
controls only connected and read the aids; it did not apply EQ, toggle booster,
adjust volume or confirm a reset. Perceived changes remain a user check.

A bounded native-window test closed the main window, verified the process
remained running and its menu bar still reported two connected aids, then
reopened through that menu's **Open Companion** action. The same process and
both live connections survived; both ear portraits, program names, five links
and loaded controls were still present. The window was returned to its original
workspace and the user's focus restored. Native AX returned an error for the
status-item press despite actually expanding its menu; the corrected harness
scopes the Open action to that status menu and verifies the observed window
state rather than treating the AX return alone as proof of failure.

The final signed build was inspected with both microphone and streaming EQs
loaded on each aid. The pair-wide reset stayed disabled until both sides were
ready. Its confirmation was then opened, checked for the exact target/defaults
and preservation of fitted programs, and cancelled without applying a reset.
The ear drawings and center links were captured at the top of the dashboard;
the previous scroll position and window focus were restored afterward.

Private evidence: `gui-040-ear-portraits.png`, `gui-040-final-visible.png`,
`gui-040-window-lifecycle.log`, `gui-040-after-menu-reopen-ax.txt`,
`gui-040-restore-confirmation-ax.txt`, and `gui-040-final-ax.txt`.
These files include personal identifiers and remain excluded from Git.

The additional synthetic tests cover distinct per-aid EQ scales and limits,
unsupported or unloaded defaults, single-setting scope, reported program
identity, changed program/capabilities during a request, preflight of both
targets, confirmation of every step, and explicit partial failure. They never
write to real hearing aids. Hardware execution of restore-default actions,
audible SpeechBooster changes and real notification banners remain untested.
