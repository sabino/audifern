# Saved tap and indicator preferences

`OticonSavedPreferences` reads a bounded part of the end-user settings already preserved in a local device backup. It performs no device operation. Its result describes saved preferences for one aid; feature availability and current activity require additional evidence.

## Independent provenance

The Swift implementation and English descriptions were written independently from wire-format observations and static inspection of a shipped fitting application. The relevant evidence establishes the named GeneralSEUS and IndicatorSEUS transformation paths, local-control contexts, numeric enum meanings and ordered vector labels. No vendor XML, decompiled implementation, UI resources, presets, calibration tables or executable components are distributed with the reader. Tests use invented values and independently constructed CBOR; they contain no captured settings or device identifiers.

Protocol field names, enum symbols, numeric codes and vector order are the interoperability facts used by the implementation. English labels are original explanatory prose, rather than reproduced application resources.

## Accepted data

The caller supplies settings, the fitting reader's identity and service advertisements from the same validated backup. The reader requires the exact profile already accepted by `OticonFittedConfiguration.Identity.isSupported` and one available EUS 2.1 advertisement. It selects only global scope 0, record 0, after checking that the backup's inventory declares that read.

| Metadata field | Name | Required vector |
| --- | --- | --- |
| 3 | `tap_mapping` | 12 tap actions |
| 5 | `audible_indicator_configuration` | 23 indicator preferences |
| 6 | `audible_indicators_settings` | 3 categorical settings |

Each field's metadata must agree on its name, global scope, complete ordered labels and complete enum map. Enum-map keys must be native unsigned CBOR integers. Decimal text keys are rejected. Duplicate keys, missing fields, changed label order, incorrect vector lengths and nonunsigned values are rejected. The existing CBOR reader also bounds response size, nesting and collection sizes.

Tap order is six single-tap contexts followed by six double-tap contexts. The context numbers have explicit transformation definitions:

| Context | Meaning |
| --- | --- |
| LCUC1 | Normal listening |
| LCUC2 | Incoming call |
| LCUC3 | Ongoing call |
| LCUC4 | Streaming |
| LCUC5 | Tinnitus |
| LCUC6 | Auracast streaming |

An action to end an Auracast stream is recognized only in LCUC6. Each aid is decoded separately because the transformation defines these preferences per aid.

## Result and limits

`decode(settings, identity: identity, services: services)` returns typed tap assignments, audible indicator choices and indicator settings. Every choice retains its full unsigned raw code. Known codes also receive a stable identifier and English category label; unknown codes retain nil identifier and label. Missing actions are errors, so the reader never substitutes a default assignment.

Indicator modes describe tone/spoken notification preferences. Voice level, tone level and tone frequency remain low/medium/high categories, without an inferred dB value or frequency. A stored preference alone does not establish that the aid currently uses it or that the corresponding feature is available.

All other fields remain in the original backup. Physical-button assignments, tinnitus volume direction, `default_profile`, situation records and profile records are outside this reader. A metadata scope label does not authorize treating a value from another scope as global. This view does not establish a complete fitting backup or restore coverage.

## Verification

Ten synthetic tests cover context and gesture ordering, indicator categories, unknown-code preservation, exact identity and EUS version gates, inventory routing, missing metadata, metadata disagreement, vector bounds and types, duplicate keys, numeric enum-map keys and isolation from uninterpreted fields/scopes. A separate private static audit checks the authored wire constants against the inspected metadata without publishing captured preferences.

The coordinated Swift suite passes. Both private device archives also decode with
the exact metadata and vector contracts above; actual settings stay private.
Synthetic tests, archive validation and static analysis do not establish hardware
behavior or clinical compatibility.
