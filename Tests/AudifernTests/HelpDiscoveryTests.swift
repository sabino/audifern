import Foundation
import Testing
@testable import Audifern

@Test func helpSearchFindsBatterySettingsAndMultilingualFeatureNames() {
    let english = Localization(language: .english)
    #expect(HelpCatalog.search("Battery", localize: { english.string($0) }).first?.id == "battery-alerts")
    #expect(HelpCatalog.search("bateria notificações").contains { $0.id == "battery-alerts" })
    #expect(HelpCatalog.search("agrupar").contains { $0.id == "grouping" })
    #expect(HelpCatalog.search("volumen").contains { $0.id == "volume" })
    #expect(HelpCatalog.search("Genie").contains { $0.id == "fitting-plan" })
    #expect(HelpCatalog.search("battery", limit: 1).count == 1)
    #expect(HelpCatalog.search("battery", limit: 0).isEmpty)
    #expect(HelpCatalog.search("no-such-feature-synthetic").isEmpty)
    #expect(Set(HelpCatalog.topics.map(\.id)).count == HelpCatalog.topics.count)
}

@MainActor @Test func helpResultsNavigateToTheExactSettingsPaneWithoutChangingSound() {
    let suite = "org.audifern.tests.help-" + UUID().uuidString, navigation = AppNavigation()
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let help = AppHelpController(navigation: navigation, defaults: defaults)
    help.openFeature("battery-alerts")
    #expect(navigation.sheet == .settings && defaults.string(forKey: "settingsSection") == "battery")
    help.openFeature("nearby-signal")
    #expect(defaults.string(forKey: "settingsSection") == "connections" && defaults.integer(forKey: "connectionSettingsSection") == 1)
    help.openFeature("mac-audio")
    #expect(defaults.integer(forKey: "connectionSettingsSection") == 2)
    help.openFeature("stream-eq")
    #expect(defaults.string(forKey: "equalizerSoundSection") == "streaming")
    help.openFeature("widgets")
    #expect(defaults.integer(forKey: "quickAccessSettingsSection") == 1)
    #expect(help.openURL(URL(string: "audifern://feature/battery-alerts")!))
    #expect(!help.openURL(URL(string: "audifern://feature/battery-alerts?mute=1")!))
    #expect(!help.openURL(URL(string: "audifern://command/unmute")!))
    #expect(!help.openURL(URL(string: "https://feature/battery-alerts")!))
}

@Test func everyHelpArticleIsTranslatedInAllSupportedLanguages() {
    for language in [AppLanguage.portugueseBrazil, .spanish] {
        let locale = Localization(language: language)
        for topic in HelpCatalog.topics {
            #expect(locale.string(topic.summary) != topic.summary)
            #expect(locale.string(topic.guidance) != topic.guidance)
        }
    }
}

@Test func nativeHelpSearchRespectsTheResultLimitAndReturnsLocalizedPaths() {
    let handler = NativeHelpSearch(selected: { _ in }, all: { _ in })
    var found: [Any] = []
    handler.searchForItems(withSearch: "battery", resultLimit: 1) { found = $0 }
    #expect(found.count == 1)
    #expect(handler.localizedTitles(forItem: "battery-alerts").count == 2)
    #expect(handler.localizedTitles(forItem: "not-a-topic").isEmpty)
}
