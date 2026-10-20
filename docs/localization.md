# Localization

Audifern initially supports English, Brazilian Portuguese and Spanish. The
translations are independently authored; no manufacturer's translation resources
are included. The system language selects the first supported language from the
user's preferred languages, falling back to English. A language chosen in Settings
affects the interface and number formatting, not hearing-aid settings.

## Runtime API

English source text is the lookup key. Use `L` for interface text and pass variable
content as arguments:

```swift
Text(L("Connect"))
Text(L("%d connected", count))
Text(L("Level %.1f dB", gain))
Text(L("%1$@ · %2$ld%%", aidName, batteryPercentage))
Text(LP("%ld hearing aid", "%ld hearing aids", count: count))
```

Use fixed keys rather than interpolating inside the lookup key. Keep user-entered
names, the name of a device or program, identifiers, and imported exam values
verbatim. Localize the surrounding sentence. Canonical model values such as the
English hearing-aid side must remain stable internally; localize them only when
displaying them. Use `M` only for canonical English backend status/error text:
it recognizes a bounded allowlist of complete messages and templates, preserves
captured names, and leaves unknown diagnostics unchanged. Passing arbitrary
interpolated sentences to `L` cannot reconstruct their original format key.

`Localization.shared.language` accepts `AppLanguage.system`, `.english`,
`.portugueseBrazil`, and `.spanish`. `AppPreferences` persists this selection and
publishes changes. Views update their locale and interface text without changing
view identity or discarding pending equalizer/audiogram drafts. Lookup is safe to use from background tasks. Missing keys fall
back to English, then to the source key.

`LP` takes a singular key and a plural key, each an ordinary catalog entry. It
handles integer counts for the initial languages. Brazilian Portuguese uses the
singular form for zero and one, following [CLDR's cardinal plural rules](https://unicode.org/cldr/charts/49/supplemental/language_plural_rules.html).
If a future language requires other noun forms, extend this API or use a plural
catalog before adding that language.

## Catalogs and formatting

Resources live under the application's `Resources/<language>.lproj` directories.
Each language contains the same English keys. Retain the type and index of every
printf argument. For example, `%ld` must not become `%d`, and translators may use
`%2$@ … %1$ld` to change sentence order. Literal percent signs inside a format use
`%%`.

The runtime validates argument count, conversion types and translation signatures
before calling Foundation's formatter. It rejects pointer/string-pointer/write
conversions, dynamic widths, positional gaps and mixed positional formats. A bad
format falls back to its English source rather than interpreting incompatible
arguments. Use `%@` with a Swift `String` or object, integer conversions with
integer values, and floating-point conversions with floating-point values.

Swift Package Manager processes these resources and generates `Bundle.module`.
When packaging the executable as a `.app`, also copy the generated SwiftPM
resource bundle into `Contents/Resources`. `AppResources` prefers that packaged
bundle before the generated development accessor. Check this after changing the
package or target name. Shipping only the executable omits catalogs and artwork.

## Auditing and adding a language

```sh
python3 scripts/test-audit-localization.py
python3 scripts/audit-localization.py
python3 scripts/audit-localization.py --inventory private/localization-source-inventory.json
```

The audit checks catalog syntax, duplicate keys, language parity, printf argument
parity and literal `L`/`LP` references. It scans `Sources` and discovers the
application resource directory automatically. Its inventory also suggests format
keys for interpolated literals and preserves the original expressions for manual
migration. `--strict` additionally fails on likely hardcoded interface strings.
That list uses lexical heuristics and needs review: it is not a complete
SwiftSyntax or accessibility audit. Generated technical diagnostics may still use
the English fallback.

To add a language, add an `AppLanguage` case, its preferred-language mapping and
formatting locale, a complete `.lproj/Localizable.strings` catalog, and tests for
its plural rules and number formatting. The audit discovers the new catalog
automatically. Verify the interface in that language as well as running tests;
key parity alone does not establish translation quality or layout.
