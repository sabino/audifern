# Quick access and Help

Settings → Quick access controls the menu-bar item, its battery text, compact or
expanded layout, device images, runtime and optional sound/program/audio sections.
Closing the main window leaves the app running. Hiding the item does not quit it;
reopen the window from the Dock. Quit ends app-owned connections.

## Together and Separate

Each sound section uses the same **Together / Separate** selector. The centered
selector above the faders groups volume and mute; the purple SpeechBooster
selector affects only SpeechBooster. Programs, microphone EQ, streaming and
tinnitus controls keep their own selection. These preferences are shared with
the matching menu-bar controls. Existing grouping preferences are migrated once,
and later section choices stay independent. Switching modes sends no device
command and copies no settings.
Grouped volume preserves the difference between the current left/right levels;
it stops at either ear's reported limit. Program changes require matching fitted
program IDs and names. Unsupported controls stay unavailable.

Sound includes connection actions and per-ear device details; Find hearing aids
opens nearby discovery in the existing attached sheet. The separate Devices
sidebar destination is no longer needed. Legacy feature links still open discovery.

The main sound card keeps each device and its centered mode selector in place
while faders merge into a central control. The filled vertical faders use native
AppKit tracking and accessibility over Liquid Glass on macOS 26+, with a solid
fallback on older systems or when Reduce Transparency is enabled. Reduced Motion disables that animation. Level values, mute switches,
runtime text, refresh indicators and action feedback have reserved space so
ordinary readback does not move neighboring controls.

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
