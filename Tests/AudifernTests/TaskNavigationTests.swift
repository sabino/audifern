import CompanionCore
import Foundation
import Testing
@testable import Audifern

@MainActor @Test func contextualTasksKeepTheirParentAndReturnToTheSamePlanStep() {
    let navigation = AppNavigation()
    navigation.page = .fitting; navigation.fittingStep = .hearingAids
    navigation.present(.fittingPlan)
    navigation.show(.audiogram)
    #expect(navigation.page == .fitting && navigation.sheet == .fittingPlan)
    #expect(navigation.sheetPath == [.audiograms])
    navigation.present(.audiograms)
    #expect(navigation.sheetPath.count == 1)
    navigation.sheetPath.removeLast()
    #expect(navigation.fittingStep == .hearingAids && navigation.sheet == .fittingPlan)
    navigation.closeSheet()
    #expect(navigation.sheet == nil && navigation.sheetPath.isEmpty)
}

@MainActor @Test func libraryDestinationsSelectTheIntendedTabAndCloseTheirContextualSheet() {
    let navigation = AppNavigation()
    navigation.present(.programDetails)
    navigation.show(.presets)
    #expect(navigation.page == .programs && navigation.libraryPresets && navigation.sheet == nil)
    navigation.present(.settings)
    navigation.show(.programs)
    #expect(navigation.page == .programs && !navigation.libraryPresets && navigation.sheet == nil)
    navigation.show(.sound)
    #expect(navigation.page == .programs && navigation.sheet == .equalizers)
}

@Test func guidedPlanStepsHaveBoundedForwardAndBackNavigation() {
    #expect(FittingPlanStep.aboutYou.previous == nil)
    #expect(FittingPlanStep.review.next == nil)
    #expect(FittingPlanStep.allCases.count == 5)
    for step in FittingPlanStep.allCases {
        if let next = step.next { #expect(next.previous == step) }
        if let previous = step.previous { #expect(previous.next == step) }
    }
}

@MainActor @Test func fittingPlanSaveReportsConfirmationAndKeepsAnUnsavedEditorOnDiskConflict() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("plan.json")
    let store = FittingWorkspaceStore(file: file)
    store.draft.name = "Synthetic plan"
    #expect(store.save())
    #expect(store.save())
    var concurrent = store.draft; concurrent.name = "Concurrent disk edit"
    let bytes = try concurrent.encoded()
    try PrivateDocuments.replace(bytes, at: file)
    store.draft.name = "Unsaved editor"
    #expect(!store.save())
    #expect(store.draft.name == "Unsaved editor")
    #expect(try Data(contentsOf: file) == bytes)
}

@MainActor @Test func namedSoundCapturePreservesPerEarConsumerStateAndRejectsIncompleteOrBusyAids() throws {
    let aids = DemoData.connections.values.sorted { $0.sideLabel == "Left" && $1.sideLabel != "Left" }
    let original = try SoundPresetCapture.make(aids: aids, name: "Synthetic preset", audiogramID: nil)
    #expect(original.aids.count == 2)
    for saved in original.aids {
        let aid = try #require(aids.first { $0.sideLabel.lowercased() == saved.side.rawValue })
        #expect(saved.volume == aid.volume?.level && saved.muted == aid.volume?.muted)
        #expect(saved.microphoneSteps == aid.microphoneEqualizer?.rawSteps)
        #expect(saved.streamingSteps == aid.streamingEqualizer?.rawSteps)
    }
    let update = try SoundPresetCapture.make(aids: aids, name: "Ignored rename", audiogramID: nil, replacing: original)
    #expect(update.id == original.id && update.name == original.name && update.createdAt == original.createdAt)
    var missing = aids[1]; missing.model = nil
    #expect(throws: (any Error).self) { try SoundPresetCapture.make(aids: [aids[0], missing], name: "Synthetic", audiogramID: nil) }
    missing = aids[1]; missing.groupActionPending = true
    #expect(throws: (any Error).self) { try SoundPresetCapture.make(aids: [aids[0], missing], name: "Synthetic", audiogramID: nil) }
    #expect(throws: (any Error).self) { try SoundPresetCapture.make(aids: [], name: "Synthetic", audiogramID: nil) }
}
