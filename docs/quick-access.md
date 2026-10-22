# Quick access and Help

Settings → Quick access controls the menu-bar item, its battery text, compact or
expanded layout, device images, runtime and optional sound/program/audio sections.
Closing the main window leaves the app running. Hiding the item does not quit it;
reopen the window from the Dock. Quit ends app-owned connections.

## Together and Separate

The selector above the volume controls is the **master control**: choose Together or
Separate to set volume/mute, SpeechBooster, fitted-program controls, microphone
EQ, streaming controls and tinnitus controls at once. Pressing Together again
reapplies it even if volume was already grouped. Each section can override its
own choice afterward; the master then shows **Mixed modes**. Hover over that
label for an explanation: some sections use Together and others use Separate.
The purple
selector affects only SpeechBooster. Menu-bar section controls keep the matching
section preference. Switching grouping sends no device command and copies no
values or unapplied EQ drafts.

In the menu-bar panel, the green volume/mute selector sits centered above its
controls, aligned with the purple SpeechBooster selector. The redundant Volume
heading has been removed; the selector retains its volume/mute accessibility
label. It still changes only that section's grouping.

Sound is a bounded workspace without an outer scroll view. In its default
layout, a compact device strip keeps the original artwork, batteries, volume,
mute and device/program buttons usable above the equalizers. Expand volume
controls folds EQ into a short summary; Edit equalizers restores the compact
strip. EQ drafts survive either change. SpeechBooster opens an anchored popover
with its matching purple Together/Separate selector and per-ear or shared switch.
Device details uses Overview, Software components and Diagnostics tabs in the
existing attached sheet; it does not stack those sections into a scrolling page.

Equalizers live directly in Sound, replacing the large program card.
Microphone, Streaming and Tinnitus relief have their own source tabs. Tone
controls use vertical Lows/Mids/Highs faders; the detailed view uses eight
vertical faders. Separate shows both ears simultaneously, while Together shows
one shared set. Together has one centered status and refresh below its selector;
hover or click the status for each ear's result. Separate uses the same status
disclosure beside each ear, with independent refresh buttons.
No left/right editor tab is needed. Both aids load independently,
and the Apply action uses each ear's own current/draft vector. A differing value
is marked **≠**, with both readings available in the tooltip. Program names stay
beside the device details and link to Library. Source volume has its own tab,
and restore actions sit below the editors.

## Quick programs and SpeechBooster

Colored program shortcuts sit above the master Together/Separate selector in
Sound, and below the connection count in the menu-bar panel. They select a fitted
program on both aids, independently of volume/EQ grouping. Only matching,
device-reported slot IDs and names are offered for a pair. Names are never
invented or translated; a newly fitted program appears when both aids report it.

Expand the hearing-aid section to choose the **Quick programs** shown on both
surfaces. Choices are stored locally per device pair and cannot be reduced to
zero. With one included program there is no quick switcher: the active program
is shown as a label, including when it differs from the included shortcut.
A single available fitted program has no customization controls. The complete
Library → Programs controls remain available for individual-ear selection.
Settings → Quick access can hide the menu-bar program row.

SpeechBooster is read automatically after connection and program changes, and
when opening a replacement consumer channel clears its previous state. These
reads wait for metadata, EQ and other owned operations, and coalesce repeated
notifications. They never enable SpeechBooster or change a listening setting.
The main popover and menu bar expose the same state without requiring a manual
load. If an automatic read fails, **Retry SpeechBooster** is available there.
Unsupported programs stay disabled; errors are not retried continuously.

Grouped volume preserves the difference between the current left/right levels;
it stops at either ear's reported limit. Program changes require matching fitted
program IDs and names. Unsupported controls stay unavailable.

Sound includes connection actions and per-ear device details; Find hearing aids
opens nearby discovery in the existing attached sheet. The separate Devices
sidebar destination is no longer needed. Legacy feature links still open discovery.

The main sound card anchors each device image, name and battery information in
a fixed outer column. Grouping only changes the middle lane: Together has one
wide horizontal volume control, while Separate splits it into equal left/right
controls. Each has its level above and minus/plus buttons at the ends. The mute
switches sit directly beneath their controls, on the same action row as Details
and the current program buttons. SpeechBooster lives in the card header. The
device and action columns do not move when switching grouping.

Sliders preview while dragging and send only the final value on release.
Battery/runtime, feedback and level text have reserved space so readback does
not move adjacent controls. EQ bands remain vertical. Reduced Motion disables
layout animation.

## Desktop widgets and system controls

Add Audifern in the desktop's **Edit Widgets** gallery:

- Hearing-aid batteries: small, medium and large.
- Quick sound controls: medium and large, with volume and mute; large adds
  SpeechBooster, app connection and available Mac audio switching.

Choose both ears, left or right in widget configuration. On **macOS 26 or later**,
use **Edit Controls** in Control Center for separate volume up/down, mute,
SpeechBooster, app connection and Mac audio controls. Ear-specific controls can
target either ear or both. macOS owns placement and supported control sizes,
including its controls in the menu bar. The public ControlWidget API provides
buttons and toggles; continuous sliders are in Audifern's expanded panel.

Audifern must be running with connected, readable aids for sound actions. The
extension does not open a second BLE connection. It sends an expiring request to
the host, which validates the current session and executes the existing consumer
control path with readback. A stale request is discarded, never replayed after
reconnecting. Clicking a widget's background only navigates to its feature.

Settings → Quick access → Widgets and Control Center can stop sharing. The
shared snapshot contains battery, timestamped runtime and supported control
values; it excludes serial numbers, Bluetooth UUIDs, credentials, audiograms and
diagnostic logs. The host writes local heartbeats without polling the radio.
Widget refresh timing remains managed by macOS and may lag behind the app.

## Battery runtime

After connection, a compatible provisioned consumer session reads runtime
telemetry. Audifern caches its timestamp and counts down locally. It refreshes
about hourly while connected; the refresh button reads only battery telemetry.
Charge/current information comes from the aid. Percentage is never converted to
an invented duration. Charging stops the countdown. Invalid all-zero telemetry
does not replace the last valid sample or renew its timestamp. Cached samples
expire after two hours and are marked as cached when reused. Hover over runtime
for the device reading's date and time.

## Connection and audio are separate

**App controls → Pause/Reconnect** operates Audifern's BLE control connection.
An explicit reconnect works even if automatic reconnection is off. Automatic
nearby/unlock reconnection remains opt-in under Settings → Connections.

**Mac audio** chooses the preferred or other available output configured in
Connections → Audio. This uses public CoreAudio output selection. It does not
force the system to disconnect MFi/LE Audio or make an Android host acquire the
stream. Cross-host Android/Mac audio handoff remains unverified; the operating
systems may keep an audio link after the app's control link is closed.

## Searchable native Help

Help → Audifern Help opens local, translated feature guidance inside the app.
The search field in the native macOS Help menu also indexes the feature catalog
through `NSUserInterfaceItemSearching`. Search **battery**, **bateria**,
**notificações**, **volume** or **agrupar**, then choose a feature to navigate to
its page or exact settings tab. No network help service or search telemetry is
used. `audifern://feature/<known-topic>` supports navigation only; arbitrary
URLs cannot trigger sound changes.

## Building the extension

`scripts/build-app.sh` builds the SwiftPM host, then the native Xcode widget
extension with the same version, deployment target and architectures. Building
the extension requires Xcode with a macOS 26 SDK or newer; the app and desktop
widgets still run on macOS 14, with ControlWidget features guarded at runtime.

Both bundles are signed with the selected identity. The actual signing team
determines `<TEAM>.org.audifern.shared`; no maintainer certificate or team is
hardcoded in the source. This macOS app-group format does not require a
provisioning profile. Ad-hoc builds have no shared container, so their app UI
works but interactive widgets require a stable Apple signing identity.

The notarization script signs the extension before the host with matching
Developer ID, hardened runtime and secure timestamps. Payload validation keeps
an explicit file allowlist for both bundles. Existing protected CI credentials
remain confined to the notarization environment; no new secret is needed.

References: [Apple app groups](https://developer.apple.com/documentation/xcode/accessing-app-group-containers),
[system controls](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system),
[native Help search](https://developer.apple.com/documentation/appkit/nsuserinterfaceitemsearching).
