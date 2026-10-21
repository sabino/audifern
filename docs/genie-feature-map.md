# Genie feature map for Audifern

This is an implementation map based on offline inspection of the supplied Genie 2 2026.2 installer, its help, UI metadata and Intent 3 model definitions. It describes observed features and proposed Audifern work. It does not mean those fitting features have been implemented or tested on hearing aids.

The reviewed Audifern baseline is `6ebe7826fa443b23f5adb93883cb87c91e211012` (2026-10-21). Its existing consumer controls, local presets and audiogram records remain distinct from a complete fitting session. [Hardware verification](hardware-verification.md), [program data](program-data.md) and [audiograms](audiogram.md) describe their current evidence and limits.

## Implemented workbench in 0.7.0

The new **Fitting** page has separate saved-data and planning views. Verified
private backups expose program names/structure, adaptation, selected processing,
gain/MPO parameter tables, stored rationale codes, fitting software version,
audiogram levels/tags and additional real-ear/in-situ metadata. Program and ear
selection in this inspector only changes what is displayed. The local plan
records context, per-ear acoustics, a linked exam, supported rationale/adaptation
preferences and program ideas. **Backups** preserves completed reads
incrementally and reports coverage. Existing everyday controls continue to use
their proven consumer path.

These are working readers and local preparation tools. The catalog below also
contains future editors and measurement tools; it is not a claim that every
Genie operation can already be performed by Audifern.

## Workflow and interface

Genie's current workflow is **Welcome → Prepare → Fit → Finish**, with a **Client** step when running without NOAH. Each step has a task list; program selection, connection status and common commands stay accessible across tools.

An independently designed Audifern workbench can preserve that continuity in one native Mac window:

| Area | Contents | Initial implementation boundary |
|---|---|---|
| Client and exam | Existing audiogram, measurement conditions, per-ear history and client context. | Local records and explicit exam selection. An entered exam does not itself calculate a fitting. |
| Prepare | Instrument/model selection, physical acoustics, rationale and personalization. | A local plan with the source and availability of each choice visible. Reading a connected model must not replace a manually entered acoustic configuration. |
| Fit | Programs, gain/MPO grid, adaptation, sound processing and verification tools. | Local drafts first; validated calculation and device application are separate capabilities. |
| Finish | Review changes, device/session destination, controls, accessories, reports and saved session history. | A local summary/export is available before a complete device fitting writer exists. |

Keep left/right and program linking separate. A program strip should retain the active selection when changing tools. Gain tables need keyboard navigation, row/column selection, useful frequency grouping and a readable narrow-window layout. Graphs should distinguish measured data, a calculated target, a simulated response and an edited draft. Show an unavailable feature with a useful reason; do not present an inactive control as a working port.

## Intent 3 boundaries established by the model

The recovered Intent 3 definition advertises:

- Four standard program slots; the actual fitted programs and usable slots still come from the session. A model capacity is not a claim that the connected pair already contains four programs.
- Eighteen fitting bands over a 24-band internal representation.
- VAC+ version 2, NAL-NL1, NAL-NL2, and adult/pediatric DSL v5 rationales. The inspected Intent 3 definition does not advertise NAL-NL3 or DSE.
- Automatic adaptation, frequency lowering, advanced noise controls, feedback processing, remote fitting and real-ear/in-situ tools.
- Conditional tinnitus treatment, CROS reception, button/tap configuration, audible/spoken/visual indicators and accessory settings.

The same definition explicitly marks **Sensor Fused Audiology, CROS transmission, dynamic environment compression, extended dynamic input range, volume learning and shaped volume control unavailable**. Generic Genie help or a higher-tier screen must not override those model-specific gates.

Availability also depends on physical style, receiver/acoustics, program, firmware and fitted configuration. For example, a coil program needs suitable hardware, and tinnitus source volume requires an already fitted tinnitus source.

The new read-only fitting reader is narrower than the planned editor. It accepts the researched Intent 3 firmware profile, validates the packed layout, and separates standard user slots from accessory records. It recovers stored gain/MPO coordinates, per-channel knee points, adaptation and selected processing settings. It does not recover a rationale name, an acoustic selection label or a frequency axis from those register bits. A four-row internal gain matrix must not be presented as the three input rows in Genie's user interface. Uninterpreted blocks remain opaque, and no device-writing operation is part of this reader.

## Feature catalog

**Existing** means present in the reviewed Audifern source, subject to its documented hardware limits. **Local** means suitable for an offline editor or report. **Fitting** needs complete model-aware calculation/state handling and fitting-session integration before changing aids. **Measurement** needs an active measurement workflow or external equipment. These labels can apply to different parts of the same feature.

| Feature | Observed Genie capability | Intent 3 scope and Audifern work |
|---|---|---|
| Client and audiogram | Client/session history; conventional and in-situ audiograms; audiometry conditions and real-ear inputs. | **Existing / Local:** reuse Audifern exam entry, plotting and JSON/HIMSA export. Add explicit exam-to-plan selection and provenance; keep imported, measured and estimated data distinct. |
| Instrument selection | Detect or manually select instruments; choose model, style and fitting level; resolve differences between session and instrument state. | **Existing / Local / Fitting:** reuse identity reads. Add a local model/acoustics plan. A connected product name alone is insufficient to reconstruct its clinical configuration. |
| Acoustics | Receiver/earpiece/dome/vent selection, fitting-range display and recalculation after acoustic changes. | **Local / Fitting:** model the physical choices per ear. Changing acoustics changes calculations and feedback assumptions; it is not a cosmetic label edit. |
| Personalization | Per-ear experience and client context; questionnaire or ACT input; recalculation where applicable. | **Local / Fitting / Measurement:** stage questionnaire/context data. ACT acquisition and applicability need separate hardware/model validation. Do not invent a score from listening preferences. |
| Rationale and first fit | Select a supported rationale and calculate a starting fitting from client and instrument data. | **Local / Fitting:** expose only the supported Intent 3 choices above. Selected VAC+ numerical stages are promising for a Mac calculation worker; full first-fit equivalence remains unproven. |
| Program management | Add, copy, rename, annotate, reorder and delete fitted programs; link adjustments across programs. | **Existing / Local / Fitting:** existing-program selection and local presets already exist. Add a separate local program plan. General occupies P1; its special deletion/reordering rules must be preserved. Device creation requires a full prescription and slot-assignment path. |
| Standard program choices | General, comfort, music and speech-in-noise programs, plus telephone/coil/auditorium variants. | **Local / Fitting / Conditional:** use the Intent 3 permitted subset. Internal, accessory, test and factory templates are not all user-selectable standard programs. |
| Gain controls and MPO | Frequency-by-input-level tables, maximum output, compression-ratio display and linked adjustments. | **Local / Fitting:** build the 18-band editor with soft/moderate/loud rows and MPO. Genie's help describes 45/65/80 dB SPL input rows and 1 dB editing steps; absolute limits and a legal device representation still require the calculation engine. Consumer EQ cannot populate this grid. |
| Sound perception | Brightness/fullness and soft-sound detail/comfort controls tied to the fitting. | **Local / Fitting:** Intent 3 advertises brightness and soft-gain controls. Do not expose a power-instrument-only bass control merely because it appears in general help. |
| Graphs and targets | Insertion gain, output, input/output, SPLogram/audiological views, target and feedback-margin overlays. | **Local / Fitting:** an audiogram or draft chart can be drawn independently. A simulated device response needs the actual response/acoustic engine; plotting an edited matrix is not that simulation. |
| Adaptation | Three steps, current/final step, automatic progression interval and progress display. | **Local / Fitting:** supported in the model and applies across programs. Persist a local plan; implement calculated gain changes and on-device progression only with complete fitting semantics. |
| Directionality and noise | Environment-dependent noise attenuation, help transition, directionality and outer-ear configuration. | **Local / Fitting:** Intent 3 advertises advanced controls with a restricted choice set. Automatic, forward-focused and omnidirectional modes need program/physical-microphone gates. Do not copy the entire higher-tier sensor screen. |
| Transient and wind handling | Sudden-sound attenuation, wind/handling processing and binaural coordination. | **Local / Fitting:** the Intent 3 definition exposes off/low/medium/high transient choices and off/medium wind choices. Those are discrete model options, not permission to invent a continuous dB slider. |
| SpeechBooster | End-user help-in-noise toggle, separate from the underlying fitted noise settings. | **Existing:** use the active program's reported support and confirmed consumer writes. Keep it separate from clinical directionality/noise configuration. |
| Speech Rescue / frequency lowering | Enablement, source/destination configuration, strength and high-frequency-band behavior. | **Local / Fitting:** frequency lowering is advertised. Its settings can be shared across programs with per-program enablement; target calculations and complete register transformations remain required. |
| Feedback management | Feedback settings, measured margins, noise-level indication, start/stop/clear analysis and unstable-gain indicators. | **Local / Fitting / Measurement:** show known or imported results with provenance. Measurement emits sound and changes analysis state; it is not a passive diagnostic read. |
| In-situ audiometry | Present controlled tones, record thresholds, choose conventional/in-situ inputs and communicate with the client during testing. | **Measurement / Fitting:** model advertises the tool, but Audifern's exam editor is not an audiometer. Tone generation, calibration, interruption and microphone-state handling require a separate implementation. |
| RECD / REUG | Enter or use measured/predicted real-ear data and appropriate measurement conditions. | **Local / Fitting:** add structured import/entry and provenance. The selected fitting path must honor the actual real-ear data and conditions. |
| Manual REM and REM AutoFit | Probe calibration, unaided/aided measurement, target verification and automatic adjustment. | **Measurement / External:** requires a compatible real-ear system and integration, such as IMC 2 or VerifitLINK. An offline graph does not establish a REM measurement. |
| Fitting Assistant | Structured listening complaints and suggested fitting adjustments. | **Local / Fitting:** useful as a future guided editor, but suggestions require the actual rule/model coverage and a preview of their full changes. No substitute prescription rules are implied by this catalog. |
| Tinnitus fitting | Enable a therapy program; select broadband/audiogram-shaped/ocean sounds; level, shaping, modulation, level steering and usage-limit information. | **Existing / Local / Fitting:** current consumer source volume/mute covers already fitted therapy only. Sound generation, enablement and therapy parameters need the complete fitting path and model/program gates. |
| Buttons, taps and indicators | Assign call/program/volume actions, configure coordination and limits; audible, spoken and visual notifications. | **Local / Fitting / Conditional:** draft a per-ear control overview. Physical controls, coordination and current program must determine available assignments; demonstrations can emit sound. |
| Accessories and streaming | Phone/TV/remote-mic tuning, microphone-to-stream balance, tonal settings, bass options and pairing management. | **Existing / Local / Fitting / Conditional:** consumer streaming EQ/source volume covers part of this. Clinical source balance and pairing deletion are separate operations; verify accessory/firmware support before exposing them. |
| Battery and power | Charge status, rechargeable-instrument handling, power preferences and battery-related feature gates. | **Existing / Conditional:** reuse battery status, supported telemetry and local alerts. Device battery-protection or power-mode changes require their own verified contracts. |
| Data logging | Wear/on time, program/accessory use, environment and volume summaries, conversation activity and consent settings. | **Local / Fitting / Conditional:** start with imported/read-only data whose acquisition is established. Some Genie lifecycle paths clear device logs; do not treat a complete logging workflow as a harmless getter. |
| Device information and diagnostics | Identification, connection/status information and service-dependent diagnostic tools. | **Existing / Conditional:** reuse typed version/battery/crash-counter reads. Do not interpret a counter as a diagnosis or confuse a firmware version with an installed firmware image. |
| Transfer, comparison and undo | Transfer settings between compatible devices/sessions; recalculate; undo/redo changes. | **Local / Fitting:** local revision history and plan comparison can come first. Device transfer needs compatible models, complete source data and transformation rules. |
| Summary and reports | Session summary, client instructions, fitting/verification reports and local/NOAH session storage. | **Local / Fitting:** generate independently designed reports from data actually available. Label a consumer export, local plan and complete clinical backup differently. |
| RemoteCare | Remote fitting session, communication/status and a relayed programming connection. | **External / Fitting:** requires the actual service/session/credential lifecycle and transport. A locally connected pair is not a RemoteCare session. |
| NOAH and client database | Client/session integration, audiogram exchange and external measurement modules. | **Existing / Local / External:** HIMSA audiogram export is present; NOAH session integration and schema/protocol interoperability are separate work. |
| Technical measurements | Special test-box programs and standards-oriented measurements, with restoration of user settings. | **Measurement / External:** not an everyday listening feature. Keep outside the connected-user workbench until a separate test-box workflow is verified. |
| Firmware and accessory updates | Eligibility checks, update-package handling, programming/restart and updater recovery. | **External:** maintain the existing version-information boundary. A full updater, installed-image readout, factory reset or recovery path is not established by UI or model metadata. |
| DemoFlex / price-point tools | Vendor trial and technology-level workflows. | **Unestablished:** generic Genie presence does not establish availability or an independent implementation path for this pair. Exclude from ordinary settings. |

## Concrete implementation order

1. **An honest offline workbench:** select an existing exam, create a named local plan, show the Intent 3 capabilities and physical configuration, and preserve the user's tool/program/ear selection. Save local drafts independently of consumer presets.
2. **Program and fine-tuning editors:** up to four planned standard programs, P1 rules, supported program choices, per-ear/program linking, the 18-band gain/MPO grid, adaptation and discrete noise controls. Store revisions and a readable change summary. Values remain local drafts until their calculation and device representation are established.
3. **A validated calculation layer:** complete client/instrument input contracts, constants/selection rules, supported rationale calculation, legalization, full global/program units and model-specific transformations. Compare complete outputs with the original engine; one numerical smoke test does not validate first fit.
4. **A complete fitting session:** capture the necessary baseline, distinguish imported/current/planned state, implement session transitions and full persistence/readback/restore, then enable only the verified operations. Preserve consumer adjustments explicitly where the fitting lifecycle resets them.
5. **Measurement and external integrations:** feedback/in-situ procedures, REM, data-log lifecycle, accessories, NOAH, RemoteCare and firmware workflows each need their own concrete dependencies and verification. Their screens can be cataloged before their hardware actions exist.

## Evidence limits

This map used the local installer, 112 packaged English help pages, selected managed UI/view-model metadata, resource-name inventories, and the recovered version-5.0 Intent 3 configuration. It did not run Genie, render its windows, execute its assemblies, access a hearing aid, or establish clinical outcome equivalence. Resource and class presence support feature discovery; model definitions and runtime gates determine applicability.

All extracted help, vendor code, XML, BAML, graphics, private evidence and device records stay outside public source. Audifern's interface, prose, models and assets must be independently authored. Exact artifact identities, method tokens, evidence IDs and inspection scopes are retained in the private research ledger.

The public fitting reader contains independently authored bit-reading logic and bounded wire facts such as field widths, offsets, integer bias, matrix ordering and template-dependent presence. It ships no extracted model document, factory preset, calculation table or vendor implementation. Its tests construct invented records; personal fitting bytes and decoded values remain in the private archive.
