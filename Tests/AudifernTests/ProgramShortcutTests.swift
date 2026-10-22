import Foundation
import Testing
@testable import Audifern

@MainActor private func shortcutPair() -> [AidConnection] {
    [false, true].map { right in
        var aid = AidConnection(id: right ? DemoData.rightID : DemoData.leftID, name: "Synthetic aid", phase: .connected)
        aid.sinkAudioLocations = right ? 2 : 1
        aid.activeProgram = 0; aid.programIDs = [0, 1, 2]
        aid.programNames = [0: "General", 1: "Comfort", 2: "Music"]
        return aid
    }
}

@MainActor @Test func quickProgramsRequireMatchingNamesAndIDsOnEveryTarget() {
    var aids = shortcutPair()
    aids[1].programNames[1] = "Different program"
    aids[1].programIDs = [0, 1]
    let catalog = ProgramShortcutCatalog(aids: aids)
    #expect(catalog.programs.map(\.id) == [0])
    #expect(catalog.visible(saved: nil).map(\.name) == ["General"])
    aids[1].programNames = [:]
    #expect(ProgramShortcutCatalog(aids: aids).programs.isEmpty)
}

@MainActor @Test func shortcutsCannotRemoveTheLastChoiceOrChangeTheActiveProgram() throws {
    let aids = shortcutPair(), catalog = ProgramShortcutCatalog(aids: aids)
    let two = try #require(catalog.selection(changing: 2, included: false, saved: nil))
    #expect(two == [0, 1])
    let one = try #require(catalog.selection(changing: 1, included: false, saved: two))
    #expect(one == [0])
    #expect(catalog.selection(changing: 0, included: false, saved: one) == nil)
    #expect(catalog.selection(changing: 99, included: true, saved: one) == nil)
    #expect(catalog.selection(changing: 1, included: true, saved: one) == [0, 1])
    #expect(aids.allSatisfy { $0.activeProgram == 0 })
}

@MainActor @Test func favoritesSurvivePartialDiscoveryAndNeverImplyAnInactiveProgramIsActive() throws {
    var aids = shortcutPair()
    aids[0].activeProgram = 2; aids[1].activeProgram = 2
    let catalog = ProgramShortcutCatalog(aids: aids)
    #expect(catalog.visible(saved: [1]).map(\.id) == [1])
    #expect(catalog.activeID == 2)
    #expect(catalog.visible(saved: [99]).map(\.id) == [2])
    aids[1].activeProgram = 0
    #expect(ProgramShortcutCatalog(aids: aids).activeID == nil)
    aids[1].programNames = [:]
    #expect(ProgramShortcutCatalog(aids: aids).visible(saved: [1]).isEmpty)
    #expect(catalog.visible(saved: [1]).map(\.id) == [1])
}

@MainActor @Test func shortcutPreferencesPersistPerDevicePairAndNeverPersistAnEmptySelection() throws {
    let suite = "Audifern.ProgramShortcuts.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = AppPreferences(defaults: defaults)
    let catalog = ProgramShortcutCatalog(aids: shortcutPair())
    #expect(preferences.menuBarPrograms)
    preferences.setQuickProgram(2, included: false, catalog: catalog)
    preferences.setQuickProgram(1, included: false, catalog: catalog)
    preferences.setQuickProgram(0, included: false, catalog: catalog)
    #expect(preferences.quickProgramSelections[catalog.scope] == [0])
    let restored = AppPreferences(defaults: defaults)
    #expect(restored.quickProgramSelections[catalog.scope] == [0])
    #expect(ProgramShortcutCatalog(aids: Array(shortcutPair().reversed())).scope == catalog.scope)
    var other = shortcutPair()
    other[1] = AidConnection(id: UUID(), name: "Other synthetic aid", phase: .connected)
    other[1].programIDs = [0, 1, 2]; other[1].programNames = catalog.aids[1].programNames
    let otherCatalog = ProgramShortcutCatalog(aids: other)
    #expect(otherCatalog.visible(saved: restored.quickProgramSelections[otherCatalog.scope]).count == 3)
    defaults.set(false, forKey: "menuBarPrograms")
    #expect(!AppPreferences(defaults: defaults).menuBarPrograms)
}
