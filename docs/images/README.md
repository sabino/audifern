# Screenshots

The current screenshots show **Audifern 0.8.4 (20)** with synthetic sample
hearing aids. The app's original device artwork and canonical
[`branding/mark.svg`](../../branding/mark.svg) are preserved.

## Compact app window

The following are native macOS window captures at **1120 × 860 pixels**, taken
on 2026-10-22 from a separate documentation build running in demo mode:

| Image | View |
| --- | --- |
| [Light](audifern-light.png) | Sound, grouped volume and three-band EQ |
| [Dark](audifern-dark.png) | The same Sound workspace in dark appearance |
| [Separate](audifern-sound-separate.png) | Independent left and right controls |
| [Eight bands](audifern-eq-eight-bands.png) | Independent eight-band EQ in dark appearance |
| [Settings](audifern-settings-es.png) | General settings in Español |
| [Help](audifern-help.png) | Battery search with a direct Battery alerts action |
| [Device details](audifern-device-details.png) | Synthetic model and software values; identifiers hidden |
| [Hearing profile](hearing-profile-light.png) | Local records and fitting plans |
| [About](audifern-about.png) | Version, maintainer and optional contributions |

Each window was revealed, sized and checked to fit the display before capture.
The user's focus was restored after each bounded capture. The temporary app was
closed and existing preview preferences restored afterward.

## Menu-bar panel

[English](audifern-menu-bar.png) and
[Português (Brasil)](audifern-program-menu.png) show the compact menu panel,
with its optional Mac audio card hidden. These are direct SwiftUI/AppKit renders
of the same native panel at 382 points wide and 2× scale, using sample devices.
They do not include window chrome or establish native popover interaction.

## Privacy and interpretation

Demo mode never creates a Bluetooth central, changes hearing aids or reads the
normal exam library. No real device identifiers, credentials or audiograms were
used. Nonessential PNG metadata is removed; pixel data and color profiles are
preserved. Preview controls are intentionally disabled where they would normally
send device commands.

Screenshots illustrate the interface. They do not establish physical device
compatibility, audio routing or clinical fitting support. Native Help, widget
and Control Center checks are recorded in the [validation ledger](../quick-access-validation.md).

## Earlier supporting images

Files outside the current set above are retained as historical supporting
images. Generic quick-access and settings captures date from 0.8.1;
`audifern-sound-clarity.png` shows the 0.8.2 revision, and
`audifern-program-shortcuts.png` is a headless 0.8.3 Sound render. The
fitting-plan light/dark images and `consumer-eq-eight-bands.png` show the earlier
0.7.0 demo app. Their marks may predate the canonical export.

The [design provenance](../design/prompts.md) describes the original artwork.
Generated [quick-access concepts](../design/quick-access-prompts.md) remain
labeled as concepts rather than app screenshots.
