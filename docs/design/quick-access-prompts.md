# Quick access concepts

Generated with the built-in `image_gen` tool. These are visual concepts; the
shipping surfaces use native SwiftUI, WidgetKit and ControlWidget layouts. The
existing Audifern logo and generic hearing-aid PNG remain the implementation's
assets. No private device identifiers, hearing records or credentials were used.

## Menu-bar panel

Selected asset: [quick-access-menu-concept.png](quick-access-menu-concept.png).

Prompt brief:

```text
Use case: ui-mockup
Create a polished native macOS menu-bar concept for Audifern, a local hearing-aid
companion. Show a compact light panel and an expanded dark panel. Preserve the
existing ear/fern identity, teal accent and inward-facing silver RIC device art.
Use the clarity of a thoughtful macOS menu-bar utility without copying another
brand. Device images, separate batteries and estimated runtime lead. Include
volume minus/plus and Mute, a Together/Separate control, SpeechBooster, fitted
program, Mac audio output, app-controls Pause/Reconnect, Open Audifern and Help.
The expanded version adds volume sliders. Keep text readable and geometry calm.
Do not imply that closing the app BLE connection transfers audio to Android.
```

## Widgets and Control Center

Selected asset: [quick-access-widget-concept.png](quick-access-widget-concept.png).

Prompt brief and targeted correction:

```text
Use case: ui-mockup
Design native macOS Audifern desktop widgets and separate Control Center
controls using the existing identity and device art. Include a small square
battery widget, a wide medium widget for both devices and sound controls, and
individual Mute, SpeechBooster, app connection and Mac audio controls. Show
light/dark refinement, readable batteries and runtime, restrained teal accents.
Keep native widget-family proportions. Use supported buttons/toggles for system
controls; continuous sliders belong in the menu-bar panel.

Correction: make the medium widget landscape. Replace the proposed slider and
percentage-based volume with Level 0, minus/plus and Mute. Preserve the visual
identity and all other concept surfaces.
```

The first widget draft had an unsuitable medium aspect ratio and a slider that
the public system-control API cannot provide. The selected revision corrects
that direction. Final sizes and placement are chosen by macOS, not the mockup.

Repository exports omit non-pixel metadata, including the embedded certificate
container in the generated mockups. The AI-generation disclosure and design
briefs above are retained; no logo or device-art pixels were changed.
