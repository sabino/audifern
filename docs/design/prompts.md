# Audifern visual design

Three original concepts were generated with OpenAI's built-in `image_gen` tool.
No manufacturer artwork, real device identifiers, clinical records or credentials
were supplied. The UI concept is design guidance; the implemented application is
native SwiftUI. Device illustrations are generic and do not identify a model.

## Interface concept

Saved as [audifern-concept.png](audifern-concept.png).

```text
Use case: ui-mockup
Create a production-quality macOS desktop UI concept board, landscape, about
1792 px wide: a large light-mode app window with a smaller dark-mode comparison.
The independent app is called Audifern and controls hearing aids locally by BLE.
Use polished Apple-level macOS precision without copying another brand. Native
sidebar about 210 px: Listen, Sound, Programs, Devices, Audiogram, with Settings
and Developer at the bottom. Listen is selected. Warm near-white surfaces,
sea-green accent, precise typography, generous spacing, restrained borders.
Main heading: Your hearing. Status: 2 connected. Two closely spaced, inward-facing
generic hearing-aid illustrations marked LEFT and RIGHT, fictional battery values
76% and 68%, estimated time remaining. Current program Geral. Large minus/plus
volume controls and Mute, a center link control and a separate-ear mode. Include
a compact SpeechBooster area and local sound presets, with Advanced sound
collapsed. Use the name Audifern verbatim and readable labels. No serials,
credentials, manufacturer/Apple logos, browser chrome, marketing copy or
excessive glass effects.
```

## Canonical brand mark

[branding/mark.svg](../../branding/mark.svg) is the source of truth for the
Audifern mark. It is the original editable vector redraw of the generated
concept. From 0.8.1, every current app surface uses exports of this exact SVG;
the earlier generated PNG is retained only in private design history.

[BrandMark.png](../../Sources/Audifern/Resources/BrandMark.png) is a transparent
2048-pixel export. The [monochrome SVG](../../branding/mark-mono.svg) preserves
the same paths. The host, widgets and menu panel share the PNG; macOS uses its
alpha silhouette for the menu-bar template image. The Dock icon places the
same mark on the existing rounded tile.

Regenerate after editing the canonical SVG, using `rsvg-convert` from librsvg:

```sh
python3 scripts/generate-brand-assets.py
python3 scripts/generate-brand-assets.py --check
```

The [export manifest](../../branding/derived-assets.json) records the source,
renderer and output hashes. Local packaging and CI check the committed exports
without requiring a renderer. Update the SVG and regenerate rather than editing
the PNG or monochrome derivative independently.

The original concept was generated with this prompt:

```text
Use case: logo-brand
Create one final original symbol for Audifern on a genuinely transparent alpha
background. No wordmark and no app-icon tile. Combine an unfolding fern and an
ear/listening gesture in an abstract, precise, minimal form legible at 16 px.
Rounded paired leaf strokes, a curved stem and an open outer ear gesture.
Sea-green, mostly solid with a subtle second tone; vector-friendly geometry.
Centered square composition with transparent padding. No Apple, Oticon or other
vendor mark, medical cross, infinity, fingerprint, Wi-Fi or Bluetooth trademark,
text, watermark, outside shadow, opaque/checkerboard canvas, photography or
raster texture.
```

## Generic hearing-aid illustration

Saved as [HearingAid.png](../../Sources/Audifern/Resources/HearingAid.png).

```text
Use case: product-mockup
Create one original, unbranded contemporary receiver-in-canal behind-the-ear
hearing aid on an actual transparent alpha background. Warm-silver satin body,
thin transparent receiver wire and soft translucent silicone dome. Do not copy
any manufacturer's specific product. Three-quarter left unit, upright and
slightly leaning right; the wire arcs to the right and the dome ends at the
bottom right. Show the complete unit centered with generous margins. Suitable
for a refined 180 px native app illustration, mirrored natively for the other
ear. Soft internal three-dimensional shading, no external shadow. No words,
serial numbers, logos, humans, accessories, background or checkerboard.
```

Both PNG assets retain real alpha transparency. The menu-bar symbol uses a
monochrome template rendering. The app icon adds its own native rounded tile.
The working name has not undergone professional trademark clearance.

Nonessential `caBX` content-credentials metadata was removed from the original
generated PNG copies during privacy preparation, preserving their pixel, alpha
and color data. Unmodified originals stay in the private research workspace.
The current brand PNG is a fresh SVG export; the hearing-aid illustration
retains its original generated pixels. This document preserves the concept
provenance and prompt set.
