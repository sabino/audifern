# Saved sound and input settings

`OticonSavedControls` is an independently authored reader for selected stored fields left opaque by `OticonFittedConfiguration`. It accepts that reader's result from the same verified backup: Intent 3 / model UID 8513, generic UID 8460, HIID 4.5, release package 5.0.29 and runtime memory map 10.0.0. Other identities and versions are rejected. It contains no vendor executable code, model resource, factory preset, fitting calculation or device writer.

## Interpretation and boundaries

The result contains shared frequency-lowering configuration indexes, weighting and source retention; streaming microphone balance and source loudness preferences; and per-directory-entry input choices, frequency-lowering enablement, tinnitus choices, transient control and wind control. These describe the saved configuration. An accessory directory entry is not an additional user program, and a saved switch does not prove that a feature is available or operating.

The common listening template also stores sensor-fusion and bass coordinates. The examined feature map declares only a `NotAvailable` sensor-fusion variant with hardware dependencies; its PowerBass variation declares `Available`. Neither the presence of a bit nor this variation declaration resolves every hardware, style and program rule. Sensor fusion must not appear as an available Intent 3 feature on that evidence alone. Bass may be shown as a raw saved input preference without asserting hardware applicability. The feature-map resource's metadata is release 5.0.27; it is source context, not the captured firmware version.

Frequency-lowering configuration numbers are indexes, not frequencies or a source/destination frequency map. The CROS balance number is a stored coordinate whose unit is not established here. The tinnitus fields preserve noise type and modulation separately: Genie can combine them for its displayed noise choice, including Ocean. They do not describe the signal spectrum, acoustic output or a recommended treatment. The shaping vector stays opaque. Labels containing dB occur explicitly in the source restrictions for streaming/input choices; they do not establish an acoustic gain scale for other fields.

## Bit contract

Bit offsets are zero-based in the complete ProdRegs byte sequence, with the low bit of each byte read first. After the existing 32-bit null-version marker, the directory occupies four count bits and nine bits per entry. For `n` entries, the general scope starts at `G = 36 + 9n`, spans 7,447 bits, and is followed by program blocks in directory order.

| Stored group | Offset and size |
| --- | --- |
| Shared lowering configuration / prescribed index / weight / retain source | `G+334`, widths 4 / 4 / 3 / 1 |
| Shared microphone / MFi / television / remote microphone preferences | `G+346`, four 3-bit choices |
| Listening-template lowering switch | Program start + 1,758, one bit |
| Input preferences | Listening start + 3,692, or accessory start + 0; 18 bits |
| Sensor switch / bass choice | Listening start + 3,734 / 3,735; one / two bits |
| Tinnitus enable / level steering / noise / modulation | Listening start + 4,028; widths 1 / 1 / 2 / 3 |
| Transient / wind choices | Listening start + 3,725 / 3,729; three / two bits |

Listening template ordinals 0–18 span 4,405 bits. Accessory ordinals 19 and 23 span 20 bits, including two final bass bits; other accessory ordinals 20–22 and 24–25 span 18 bits. The helper checks the parent reader's named opaque blocks, absolute offsets, lengths, unused padding, unique slots and final consumed extent before interpreting them. It leaves every original opaque block intact.

The two lowering configuration fields encode bounded numeric coordinates: the first adds one to a four-bit value limited to 0–9, while the prescribed index is limited to 0–10. CROS balance encodes a value of `raw / 10 − 20`, with raw limited to 0–400. Stored On/Off switches use ordinal zero for On. Unassigned enum ordinals in the newly interpreted opaque fields remain available as their numeric code with no invented label; the parent reader retains its existing validity checks for transient and wind ordinals.

## Artifact provenance

The exact field order, widths, ranges and restrictions come from the extracted GenericModel.Aludra3 ProdRegsMap v5.0 resource, SHA-256 `7ecc18a705fdd15c0fbee99ccee2b922e372a6939223964fb596a800b32dd9ef`. Feature-map context comes from its FVM resource, SHA-256 `f0718260028db58518185b29f09cdfb8d1b5e3aa0f870b1ff165249f1d112b9e`. Extracted resources and all personal fitting bytes remain private.

Managed getter corroboration is from `Phoenix.BusinessLogic.TrimmerEngine.dll`, SHA-256 `07bc15fa7a62c3582a6fa2adaea777e211177f3131234d10008c50b28833813b`, MVID `24a6be6b-9490-4aa5-83c4-1090906ff3c7`. Tokens below are meaningful only with that identity.

| Producer getter | Token | Corroboration |
| --- | --- | --- |
| FrequencyLoweringTransformation.GetTrimmer | `0x0600060e` | Reads Active; microphone selection affects whether the control is editable |
| MonauralTransientNoiseReductionTransformation.GetTrimmer | `0x060006b3` | Returns the stored string choice; shadow templates have an empty control |
| TinnitusOnOffTransformationTechnical.GetTrimmer | `0x0600074e` | Reads SignalGeneratorOn for the program |
| TinnitusLevelSteeringTransformation.GetTrimmer | `0x06000737` | Reads LevelSteeringOn; microphone Off makes it read-only |
| TinnitusNoiseTypeTransformation.GetTrimmer | `0x06000747` | Uses both NoiseType and SignalModulation |
| TinnitusSignalModulationTransformation.GetTrimmer | `0x06000764` | Filters Ocean differently from other modulation choices |
| CrosStreamBalanceTransformation.GetTrimmer | `0x060005d5` | CROS source mixing affects editability |
| PowerBassTransformation.GetTrimmer | `0x060005bb` | Produces an empty control when no applicable register is found |

REA selected-member parents are `ev_060a98be15a759c33f13d5d097fa07c882acdfdaf72efd396d39b0a0cc004f49` and `ev_c555a332a69fdf7d2c2f2f27dd0a718870954a45307c46c8a187b2462071fe4a`; exact method pages are `ev_c3af26a2be3f5f30ea5c007fec70f47fee7ea64dad577ee7b4a6acc26381d092` and `ev_f9934832a4027d299dddba9583ff52db5288c43044b7ebfdcf3e954430dd8ec9`. These are static file-backed metadata/CIL observations; no vendor assembly was loaded or executed.

## Verification and remaining scope

Synthetic tests cover non-byte-aligned original-stream offsets, switch polarity, listening/accessory boundaries, unknown ordinals, invalid numeric coordinates, identity gating, malformed opaque geometry, duplicate blocks, padding, final extent and Data slices. Captured-backup comparison can independently check every selected coordinate against the private, schema-driven decoder without printing clinical data. Test execution and captured-backup verification are reported separately from this static evidence.

The common template's legacy LocalControl and visual-indicator blocks are not exposed by this helper. Current tap controls use context-specific GeneralSEUS/UseCases values and hardware rules; legacy bits alone cannot reconstruct them. The helper also leaves personalization, tinnitus shaping, pairing information and all other uninterpreted fields in the original private archive.
