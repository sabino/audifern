# Screenshot provenance

The 0.7.0 screenshots were captured on macOS on 2026-10-21 from a separately
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
