# Quick-access validation — 2026-10-21

Local development build: **0.8.0 (16)**. This records the extent of verification;
it is not a claim that a new public release has been published.

- Swift: 170 app tests and 131 core tests passed; the XCTest suite ran 68 cases
  with one optional case skipped and no failures.
- Python: 64 tests passed, including strict extension payload checks and nested
  signing without unnecessary provisioning-profile entitlements.
- Localization: 1,986 matching keys in English, Brazilian Portuguese and Spanish;
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

## Sound and Settings follow-up

- Sound now contains discovery, connection/disconnection and per-ear device
  details. Legacy setup links use discovery in the existing task sheet; device
  information and battery-time Help links go to Sound.
- Volume/mute, SpeechBooster, programs and each equalizer source keep independent
  grouping choices. Migration preserves the previous choice without sending a
  sound command. A dedicated migration and navigation test covers these paths.
- Every Settings category and each connection/quick-access tab was rendered in
  all three languages at the smallest supported content size. Native sheet
  switching kept both parent and sheet frames unchanged at two window sizes.
- Real pointer clicks on blank sidebar-row space opened Privacy and Battery
  alerts in the isolated preview. Both sidebars use the same green style.
- The final native preview showed the new filled faders and aligned sections.
  These are visual/interaction checks; no hearing-aid adjustment was issued by
  the preview.

## Master grouping and bounded Sound workspace

- The master Together/Separate selector updates all six grouping preferences,
  including each EQ source. Re-selecting Together clears later section overrides;
  Mixed modes is visible if a section overrides the master. No grouping or
  layout action sends a hearing-aid command.
- Sound uses a compact device strip and an inline EQ editor with vertical three-
  or eight-band controls. Separate displays two editors simultaneously. Together
  preserves per-ear differences until the user edits and chooses Apply. A draft
  in either ear enables the shared Apply action; loading the other ear does not
  clear it.
- Layout rendering covered all three languages, Together/Separate, both EQ
  sources and detail levels, compact/expanded device controls and tinnitus.
  Short 740 × 700 point workspaces and 960 × 597 point device panels were reviewed.
- A headless AppKit test checked the real native fader frames, both ear counts
  and absence of NSScrollView at 740 × 700 in Portuguese. The capsule slider now
  respects its proposed compact size instead of forcing a full-height control.
- Native preview interaction checked three/six and eight/sixteen vertical EQ
  faders, folding and restoring the editor, and all device-details tabs. No
  scrollbars were exposed in those views. The existing window-manager layout
  was preserved; short-window evidence comes from the headless checks above.
- SpeechBooster and program/device access are explicit compact buttons. Advanced
  discovery and diagnostic inventories remain available through their existing
  tasks; the no-scroll change applies to everyday Sound and device information.
- The two mailbox-expiry fixtures now use a fixed shared timestamp. Separate
  clock reads could accidentally make their sample snapshot come from the
  future; production freshness validation remains strict and unchanged.

## Horizontal daily volume follow-up

- Daily volume now runs horizontally with a fixed level label above, minus and
  plus buttons at the ends, and mute below. Together places one shared control
  between the original device images; Separate keeps both devices together with
  an explicitly labeled control for each ear. EQ bands stay vertical.
- The short-viewport test now verifies horizontal native volume controls and
  vertical EQ controls simultaneously, with all real fader frames inside the
  viewport. The full 170-app/131-core Swift suites passed. Compact and expanded
  layouts were rendered and reviewed in all three languages, including the
  740 × 700 point Portuguese layout. Widget and protocol behavior are unchanged.
- Native accessibility confirmed one horizontal volume fader for Together and
  two for Separate, while the sixteen detailed EQ faders remained vertical.
  Folding and reopening EQ preserved the eight-band choice. No scrollbar was
  present in the Sound workspace; protected focus was restored after capture.

## Fixed outer devices and aligned actions

- Device summaries and device/program buttons use fixed outer columns in both
  grouping modes. The central volume controls now use all remaining width.
  Their mute controls reuse the same middle columns and action-row center as
  the Details/program buttons. SpeechBooster is available from the header.
- The 170 app tests, 131 core tests and 68 XCTest cases (one optional skip)
  passed. The strict localization audit passed with 1,985 keys in each language.
  Compact and expanded workspaces were reviewed in all three languages, along
  with the short Portuguese viewport; no Sound scrolling was introduced.
- Native accessibility measurements confirmed that all eight device-summary,
  action-group, Details and program frames were identical before and after
  switching Together/Separate. Mute and Details shared the action-row center
  within two points. The shared horizontal slider used 1,306 points at the
  tested full-width window size. Both grouping modes exposed zero scrollbars.
- The isolated preview uses synthetic devices and issued no hearing-aid sound
  change. These checks establish layout and navigation, not a new audio test.

## Centered menu selectors and clearer mixed modes

- Removed the menu panel's Volume heading so its green Together/Separate
  selector centers over the controls, aligned with the purple SpeechBooster
  selector. Its volume/mute scope and accessible label remain unchanged.
- The master now says Mixed modes when sections disagree, with translated hover
  guidance explaining how to apply one mode to all sections.
- The full 170-app/131-core Swift suites and 68 XCTest cases passed, with one
  optional XCTest skip. The strict localization audit passed with 1,986 matching
  keys in all three languages and no hardcoded-string candidates.
- Twelve complete menu panels were rendered at their natural height: all three
  languages, both grouping modes and compact/expanded layouts. English and
  Portuguese captures were reviewed. The render harness now measures the same
  native fitting height as the running popover instead of clipping its footer.
- The isolated preview was refreshed. A fresh foreground capture could not be
  completed because another app reclaimed focus; the protected focus was
  restored. The updated menu screenshot is explicitly a direct AppKit render.
  No hearing-aid sound command or new physical audio check was performed.

## Release candidate screenshots

- Refreshed the README's native 0.8.0 (16) window captures: English light Sound,
  Portuguese dark Sound, Spanish Settings, both grouping modes, inline eight-
  band EQ, device information, About, connection/quick-access settings and Help.
- A fresh native menu-bar capture confirms the centered green and purple mode
  selectors. This supersedes the earlier direct-render screenshot and the
  foreground-capture limitation recorded above.
- All captures use the isolated demo app. No Bluetooth central or real-device
  data was used. Export strips nonessential PNG metadata. The temporary app was
  closed, and preview preferences, layout and protected focus were restored.
- Re-ran the 64 Python packaging/signing tests, five localization-audit fixtures
  and strict 1,986-key audit. Known-private-pattern scanning found no new source
  or device-data findings; historical signatures remain intentional public
  metadata and dangling historical identities remain private.

## Canonical branding follow-up — 0.8.1 (17)

- The repository's `branding/mark.svg` is unchanged and is now the canonical
  source for the app's transparent mark, widget art, menu panel and Dock tile.
  The monochrome SVG is generated from the same paths. The manifest records
  source/output hashes; local packaging and CI check for stale exports.
- Checked that both packaged host and widget contain the exact same generated
  PNG. Extracted and reviewed the packaged ICNS. Temporary fixtures confirmed
  the export check rejects an independently modified source SVG or PNG.
- Re-ran the 64 Python tests and strict 1,986-key localization audit. No sound
  or protocol behavior was changed.
- Retook 15 native demo views in English, Brazilian Portuguese and Spanish,
  including both grouping modes, About, Help, Settings and the native popover.
  README captures and an extracted app-icon image were exported without
  nonessential PNG metadata. No real-device data or Bluetooth central was used.
  The temporary capture app was closed and demo preferences and focus restored.


## Sound-control clarity follow-up

- White labels on native filled buttons and segmented controls now use a deeper
  green, with a tested contrast ratio of at least 4.5:1. Ordinary button text,
  icons and slider tracks retain the adaptive semantic accent.
- Connectivity and Settings share one fixed toolbar group. Native accessibility
  measurements show separated targets; both buttons open the intended panel.
- Hearing-aid and EQ grouping selectors use the same centered header layout,
  including when a section has no title in its leading lane. Native measurements
  confirm that their centers match within half a point.
- Removed the extra sound-controls destination from the inline EQ card. Restore
  sound defaults is directly underneath; each Reset EQ action is beside Apply.
  Dedicated streaming-source gain remains accessible through Source volume.
- The microphone-volume scale uses the device-reported bounds, with every native
  step marked and explicit minimum, zero and maximum labels in narrow controls.
  Wider controls label each step. Zero follows the native thumb travel rather
  than assuming a symmetric range; the synthetic sample uses -8 through +3.
  A detached native-cell copy supplies the thumb endpoints on each macOS version;
  tests confirm these geometry queries leave the live value and actions unchanged.
- The full Swift test run passed: 68 XCTest cases (one optional fixture skipped),
  131 core Swift Testing cases and 174 app cases. The separate opt-in rendering
  check passed for English, Brazilian Portuguese and Spanish, both grouping
  modes, eight-band EQ and the 740 x 700-point workspace. Rendering is run
  separately so it cannot block the protocol tests' response deadlines.
- Strict localization and canonical-brand checks passed. The debug app, including
  its widget extension, built and passed bundle/signature verification. Native
  UI checks used an isolated sample app; no physical sound-change test was made.
