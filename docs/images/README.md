# Screenshot provenance

The original README screenshots show **Audifern 0.8.1 (17)**, captured on macOS
on 2026-10-21. They are native window and AppKit popover captures from a
separately packaged documentation app launched with `--demo`.

Demo mode uses synthetic devices, batteries, programs, exams and fitting plans.
It never creates a Bluetooth central, changes a hearing aid or reads the normal
exam library. The regular app and real-device information were not used. Preview
preferences, the existing preview window's layout and the user's focus were
restored after capture; the temporary documentation app was closed.

All current marks come from the unchanged canonical `branding/mark.svg`.
`audifern-app-icon.png` is extracted from the packaged ICNS; it is the same mark
on the existing native rounded tile, rather than a separate logo concept.

## Current captures

- `audifern-light.png` and `audifern-sound-together.png`: English Sound overview
  in light mode, with all sections Together and three tone controls.
- `audifern-dark.png`: Brazilian Portuguese Sound overview in dark mode, with
  all sections Separate and both eight-band editors visible.
- `audifern-sound-separate.png`: English Sound overview with separate controls.
- `audifern-eq-eight-bands.png`: English Sound with both eight-band EQ editors.
- `audifern-menu-bar.png`: the native AppKit popover, with centered green and
  purple mode selectors, device art, runtime and expanded volume controls.
- `audifern-quick-access.png`: menu-panel customization in the Settings sheet.
- `audifern-settings-es.png`: Spanish General settings in light mode.
- `audifern-settings-battery.png` and `audifern-settings-privacy.png`: Spanish
  battery-alert and privacy settings.
- `audifern-connections.png`: the opt-in connection preferences.
- `audifern-device-details.png`: the device panel's Overview tab, with synthetic
  model/software values and no serial number.
- `audifern-help.png`: searching Battery in the attached Help sheet, with its
  direct Battery alerts settings action.
- `hearing-profile-light.png`: the Hearing profile overview.
- `audifern-about.png` and `audifern-settings-about.png`: the compact About
  view, including the maintainer's intentionally public contribution link and
  locally generated QR code. The centered footer appears in the standalone view.

Captures were reviewed visually. Export removes nonessential PNG metadata
while preserving pixel/color data. Real-device captures, private backups and
credentials remain outside this repository. Screenshots establish the shown
interface, not physical interoperability or complete clinical fitting.

## Earlier supporting images

The historical fitting-plan light/dark captures and `consumer-eq-eight-bands.png`
show the native 0.7.0 demo app with the earlier generated mark. The latter predates the inline EQ editor now
shown in the README. Fitting-plan-history light/dark images are direct
SwiftUI/AppKit renders with synthetic revision history.

Original branding and the generic hearing-aid illustration are described in
[the design provenance](../design/prompts.md). The generated quick-access
concepts remain labeled as concepts in [their provenance](../design/quick-access-prompts.md).

Native Help-menu search, widget-gallery and Control Center registration checks
are recorded in [the validation ledger](../quick-access-validation.md).
Physical sound changes through every widget/control action remain unverified.

## Sound-control clarity — 0.8.2

`audifern-sound-clarity.png` is a native dark-mode Sound capture of the revised
controls, using synthetic devices with all sections Together. It was captured
on 2026-10-22 from implementation commit `1628ba8`, before the release-only
version metadata was incremented to 0.8.2 (18). It shows the same control
implementation released in 0.8.2, including centered grouping, the asymmetric
volume scale and the relocated reset/restore actions. Nonessential PNG metadata
was removed. The existing supporting screenshots remain from 0.8.1.
