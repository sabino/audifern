import Foundation
import Testing
@testable import Audifern

@Test func sectionGroupingMigratesOnceAndPreservesLaterIndependentChoices() {
    let suite = "org.audifern.tests.grouping-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(false, forKey: "groupedHearingAidControls")
    SoundGroupingPreferences.migrate(defaults: defaults)
    #expect(SoundGroupingPreferences.sectionKeys.allSatisfy { !defaults.bool(forKey: $0) })
    defaults.set(true, forKey: "groupedSpeechBoosterControls")
    defaults.set(true, forKey: "groupedProgramControls")
    SoundGroupingPreferences.migrate(defaults: defaults)
    #expect(defaults.bool(forKey: "groupedSpeechBoosterControls"))
    #expect(defaults.bool(forKey: "groupedProgramControls"))
    #expect(!defaults.bool(forKey: "groupedHearingAidControls"))
    #expect(!defaults.bool(forKey: "groupedEqualizerControls"))
    #expect(!defaults.bool(forKey: "groupedStreamingControls"))
}

@MainActor @Test func deviceDiscoveryKeepsSoundAsHomeAndUsesTheExistingTaskSheet() {
    let navigation = AppNavigation()
    navigation.page = .programs
    navigation.show(.devices)
    #expect(navigation.page == .hearingAids)
    #expect(navigation.sheet == .nearbyDevices)
    #expect(!AppPage.mainPages.contains(.devices))
    navigation.closeSheet()
    navigation.present(.settings)
    navigation.show(.devices)
    #expect(navigation.sheet == .settings && navigation.sheetPath == [.nearbyDevices])
}

@MainActor @Test func deviceHelpTopicsReachSoundWhileSetupStillOpensDiscovery() {
    let suite = "org.audifern.tests.device-help-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let navigation = AppNavigation(), help = AppHelpController(navigation: navigation, defaults: defaults)
    help.openFeature("device-information")
    #expect(navigation.page == .hearingAids && navigation.sheet == nil)
    help.openFeature("battery-time")
    #expect(navigation.page == .hearingAids && navigation.sheet == nil)
    help.openFeature("getting-started")
    #expect(navigation.page == .hearingAids && navigation.sheet == .nearbyDevices)
}

@MainActor @Test func masterGroupingReappliesToEverySectionEvenWhenVolumeWasAlreadyTogether() {
    let suite = "org.audifern.tests.master-grouping-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = AppPreferences(defaults: defaults)
    SoundGroupingPreferences.setAll(true, defaults: defaults)
    defaults.set(false, forKey: "groupedEqualizerControls")
    defaults.set(false, forKey: "groupedSpeechBoosterControls")
    preferences.groupAllSoundControls(true)
    #expect(([SoundGroupingPreferences.volumeKey] + SoundGroupingPreferences.sectionKeys).allSatisfy { defaults.bool(forKey: $0) })
    preferences.groupAllSoundControls(false)
    #expect(([SoundGroupingPreferences.volumeKey] + SoundGroupingPreferences.sectionKeys).allSatisfy { !defaults.bool(forKey: $0) })
    defaults.set(true, forKey: "groupedStreamingControls")
    #expect(!defaults.bool(forKey: "groupedHearingAidControls"))
    #expect(!defaults.bool(forKey: "groupedEqualizerControls"))
    #expect(defaults.bool(forKey: "groupedStreamingControls"))
}

@MainActor @Test func equalizerNavigationFocusesTheInlineCardAndCanBeRequestedAgain() {
    let navigation = AppNavigation()
    navigation.show(.sound)
    let first = navigation.soundFocus
    #expect(navigation.page == .hearingAids && navigation.sheet == nil && first != nil)
    navigation.show(.sound)
    #expect(navigation.soundFocus != first)
    navigation.show(.hearingAids)
    #expect(navigation.soundFocus == nil)
}
