import Foundation
import Testing
@testable import Audifern

@Test func localizationSupportsExplicitLanguageChangesAndSourceStringFallback() {
    let text = Localization(language: .english)
    #expect(text.string("Connect") == "Connect")
    text.language = .portugueseBrazil
    #expect(text.string("Connect") == "Conectar")
    #expect(text.string("Left") == "Esquerdo")
    text.setLanguage(.spanish)
    #expect(text.string("Right") == "Derecho")
    #expect(text.string("Uncatalogued English fallback") == "Uncatalogued English fallback")
}

@Test func localizationResolvesSystemLanguagePreferencesWithoutChangingStoredSelection() {
    let text = Localization(preferredLanguages: ["fr-FR", "es-MX"], systemLocale: Locale(identifier: "es_MX"))
    #expect(text.language == .system && text.effectiveLanguage == .spanish)
    #expect(text.string("Hearing aid") == "Audífono")
    #expect(AppLanguage.resolve(preferredLanguages: ["pt_PT"]) == .portugueseBrazil)
    #expect(AppLanguage.resolve(preferredLanguages: ["en-GB"]) == .english)
    #expect(AppLanguage.resolve(preferredLanguages: ["ja-JP", "de-DE"]) == .english)
}

@Test func localizationUsesSelectedLocaleForDecimalsAndHandlesPercentAndPositionalArguments() {
    let english = Localization(language: .english)
    let portuguese = Localization(language: .portugueseBrazil)
    #expect(english.string("Level %.1f dB", arguments: [1.5]) == "Level 1.5 dB")
    #expect(portuguese.string("Level %.1f dB", arguments: [1.5]) == "Nível 1,5 dB")
    #expect(portuguese.string("%1$@ · %2$ld%%", arguments: ["Synthetic", 42]) == "Synthetic · 42%")
    #expect(english.string("Unknown %.1f format", arguments: [2.5]) == "Unknown 2.5 format")
}

@Test func integerPluralMessagesFollowTheInitialLanguagesRules() {
    let english = Localization(language: .english), portuguese = Localization(language: .portugueseBrazil)
    let spanish = Localization(language: .spanish)
    #expect(english.plural("%ld hearing aid", "%ld hearing aids", count: 0) == "0 hearing aids")
    #expect(english.plural("%ld hearing aid", "%ld hearing aids", count: 1) == "1 hearing aid")
    #expect(portuguese.plural("%ld hearing aid", "%ld hearing aids", count: 0) == "0 aparelho auditivo")
    #expect(portuguese.plural("%ld hearing aid", "%ld hearing aids", count: 2) == "2 aparelhos auditivos")
    #expect(spanish.plural("%ld hearing aid", "%ld hearing aids", count: 0) == "0 audífonos")
    #expect(spanish.plural("%ld hearing aid", "%ld hearing aids", count: 1) == "1 audífono")
    #expect(english.plural("One", "Other", count: 1) == "One")
    #expect(english.plural("One", "Other", count: Int.min) == "Other")
}

@Test func localizedFormatsValidateArgumentTypesAndAllowPositionalReordering() throws {
    let ordered = try #require(LocalizedFormat.signature("%ld · %@ · %.1f"))
    let reordered = try #require(LocalizedFormat.signature("%2$@ · %3$.1f · %1$ld"))
    #expect(ordered == reordered)
    #expect(ordered.accepts([2, "Label", 1.5]))
    #expect(!ordered.accepts(["2", "Label", 1.5]))
    #expect(!ordered.accepts([2, "Label"]))
    #expect(LocalizedFormat.signature("%@")?.accepts([12]) == false)
    #expect(LocalizedFormat.signature("%f")?.accepts([NSNumber(value: 1.5)]) == false)
    #expect(Localization(language: .english).string("%@", arguments: [12]) == "%@")
}

@Test func localizedFormatsRejectUnsafeAmbiguousAndIncompatibleConversions() {
    for value in ["%n", "%s", "%p", "%l@", "%llf", "%*d", "%1$@ %@", "%1$ld %1$@", "%0$@", "%2$@", "%1000000d", "%.100f"] {
        #expect(LocalizedFormat.signature(value) == nil)
    }
    #expect(LocalizedFormat.signature("%ld") != LocalizedFormat.signature("%d"))
    #expect(LocalizedFormat.signature("%%")?.maximumIndex == 0)
}

@Test func localizationSelectionAndLookupCanBeUsedFromBackgroundTasks() async {
    let text = Localization(language: .english)
    await withTaskGroup(of: Bool.self) { group in
        for index in 0..<60 {
            group.addTask {
                text.language = index.isMultiple(of: 2) ? .english : .portugueseBrazil
                return ["Connect", "Conectar"].contains(text.string("Connect"))
            }
        }
        for await valid in group { #expect(valid) }
    }
}

@Test func everyTranslationHasTheEnglishKeysAndCompatibleFormatArguments() throws {
    let englishBundle = try #require(Localization.bundle(for: .english))
    let englishURL = try #require(englishBundle.url(forResource: "Localizable", withExtension: "strings"))
    let english = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: englishURL), format: nil) as? [String: String])
    #expect(!english.isEmpty)
    for language in AppLanguage.allCases where language != .system {
        let bundle = try #require(Localization.bundle(for: language))
        let url = try #require(bundle.url(forResource: "Localizable", withExtension: "strings"))
        let strings = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
        #expect(Set(strings.keys) == Set(english.keys))
        for (key, translation) in strings {
            #expect(!translation.isEmpty)
            #expect(LocalizedFormat.signature(translation) == LocalizedFormat.signature(try #require(english[key])))
        }
    }
}
