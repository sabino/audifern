# Screenshot provenance

The About screenshot was refreshed for the local 0.8.0 development build. It
shows the compact layout and centered footer without an inner scroll area.
`audifern-settings-about.png` shows the same view inside Settings;
`audifern-connections.png` shows the opt-in reconnect controls. These native
window captures use only the separately launched `--demo` app described below.

The remaining 0.7.0 screenshots were captured on macOS on 2026-10-21 from a separately
launched, packaged Audifern app with `--demo`. This uses synthetic devices,
battery values, programs and fitting plans. Demo mode never creates a Bluetooth
central or changes a hearing aid; it stores preview preferences separately.

- `audifern-light.png`: Sound, English, light appearance.
- `audifern-dark.png`: Sound, Brazilian Portuguese, dark appearance.
- `audifern-settings-es.png`: the native Settings sheet, Spanish.
- `consumer-eq-eight-bands.png`: the native EQ sheet, English, eight-band view.
- `hearing-profile-light.png`: Hearing profile, English.
- `fitting-plan-light.png`: the native guided plan sheet, English.
- `fitting-plan-dark.png`: the native guided plan sheet, Brazilian Portuguese.
- `audifern-about.png`: the native About sheet, including the maintainer's
  intentionally public contribution link and locally generated QR code.

Window captures were checked visually, and nonessential PNG metadata was
removed while preserving image/color data. The normal app, local exams,
hearing-aid identifiers, private backups and authentication material were not
used for the screenshots. Real-device captures remain outside the repository.

The earlier `fitting-plan-history-light.png` and `fitting-plan-history-dark.png`
are isolated SwiftUI/AppKit view renders with synthetic revision history.
Original branding and the generic hearing-aid illustration are described in
[the design provenance](../design/prompts.md). Preview screenshots demonstrate
the interface, not physical interoperability or complete clinical fitting.

The 0.8.0 quick-access captures use synthetic demo services, either in the
isolated `--demo` application or in a direct SwiftUI/AppKit render as noted:

- `audifern-sound-together.png` and `audifern-sound-separate.png`: fixed central
  volume selector, filled glass-style faders, original device illustrations and
  aligned per-section controls. SpeechBooster and programs can remain Separate
  while volume is Together.
- `audifern-menu-bar.png`: the compact menu panel rendered directly with
  SwiftUI/AppKit at its native fitting height; see the build 16 note below.
- `audifern-help.png`: searching Battery in the attached Help sheet.

The native Help menu search was also checked through AppKit accessibility: it
returned Settings → Battery alerts and Devices → Battery time remaining. Opening
Battery alerts from Help reached that exact settings pane. The desktop gallery
listed three battery sizes and two sound-control sizes. These gallery checks do
not establish physical hearing-aid behavior for every widget/control action.

The Sound captures were refreshed for **0.8.0 (12)**, together with
`audifern-settings-battery.png` and `audifern-settings-privacy.png`. The two
settings captures followed real pointer clicks on the blank right-hand area of
each sidebar row, rather than accessibility presses on its text. All settings
categories and connection/quick-access tabs were additionally rendered in
English, Brazilian Portuguese and Spanish at the minimum 1020 × 637 content
size. No settings scroll view is used. Native sheet transitions were checked at
1060 × 740 and 1240 × 960 main-window sizes without frame changes.

Device and runtime Help topics now route to Sound, where their controls and
device-detail buttons live. The earlier Help-search capture described above
predates that navigation consolidation.

The Sound captures were refreshed again for **0.8.0 (13)**: the compact device
strip gives most of the workspace to the inline EQ. `audifern-eq-eight-bands.png`
shows both eight-band editors at once. `audifern-device-details.png` shows the
fixed device-information panel's Diagnostics tab. These are native captures of
the isolated demo app. No actual device information or sound commands were used.

The two Sound overview captures were subsequently refreshed for **0.8.0 (14)**,
using the horizontal daily-volume layout. The device-information capture
continues to show the same tabbed panel introduced in build 13. EQ controls
remain vertical and both source grouping modes are shown in the overview shots.

The Sound overview captures now show **0.8.0 (15)**. Device images and summaries
stay in fixed outer columns, with a wider horizontal control between them.
Mute, Details and program buttons share one aligned action row, and SpeechBooster
is in the header. Both images are native captures of the isolated demo app at
the same window size. Device/action frames were measured unchanged across modes.

The menu-panel capture was refreshed for **0.8.0 (16)** with the Volume heading
removed and the two mode selectors centered. It is a direct NSHostingView render
of the real menu panel, using only synthetic devices, rather than a screenshot
of an onscreen popover. Twelve menu renders cover the three languages, both
grouping modes and compact/expanded layouts. Non-pixel PNG metadata was removed.
