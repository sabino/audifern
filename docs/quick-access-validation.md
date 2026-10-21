# Quick-access validation — 2026-10-21

Local development build: **0.8.0 (11)**. This records the extent of verification;
it is not a claim that a new public release has been published.

- Swift: 161 app tests and 131 core tests passed; the XCTest suite ran 68 cases
  with one optional case skipped and no failures.
- Python: 64 tests passed, including strict extension payload checks and nested
  signing without unnecessary provisioning-profile entitlements.
- Localization: 1,957 matching keys in English, Brazilian Portuguese and Spanish;
  reference and format checks passed. All Help articles have translations.
- Universal release build: the host and extension both contain arm64 and x86_64
  slices with a macOS 14 minimum. Both signatures and matching app groups passed
  verification. CI now selects a macOS 26+ SDK explicitly.
- Synthetic UI: Together/Separate, compact/expanded menu panels, Help, quick
  settings and widget families were rendered in light/dark and translated
  layouts. Device art was checked at the final backing resolution.
- Native macOS: the menu-bar popover opens; the app remains responsive. Native
  Help-menu search returned Battery alerts and Battery time remaining. The Help
  sheet's Battery result opened the exact Battery alerts settings pane.
- Desktop gallery: three battery-widget sizes and two sound-control sizes were
  listed. Control Center's Audifern category listed all six controls: connection,
  Mac audio, mute, SpeechBooster, volume down and volume up.
- Live aids: both connected in the installed app and runtime telemetry loaded
  automatically. The shared mailbox acknowledged an explicit reconnect while
  already connected; both aids' volume/mute values stayed unchanged. Private
  identifiers and captures are excluded from this repository.

Physical sound changes through every new widget and system control still need
wearer confirmation. The existing consumer executors are covered by their
readback tests; gallery registration and a reconnect check are narrower evidence.
Android/Mac audio handoff remains unverified and is separate from app BLE
connection and CoreAudio output selection. No new Apple notarization submission
was made as part of this local UI task.

The source/privacy review found no new working-tree credential or personal-data
findings after removing non-pixel metadata from exported mockups. Historical
signed-commit metadata remains reviewable by the repository's audit tool; public
GPG signatures are retained as requested.
