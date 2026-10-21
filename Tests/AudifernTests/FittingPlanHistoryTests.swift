import CompanionCore
import Foundation
import Testing
@testable import Audifern

private func historyTestFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

@MainActor @Test func savedPlanHistoryPreservesLegacyFileAndRecoversUnsavedDrafts() throws {
    let folder = historyTestFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("plan.json")
    let legacy = FittingWorkspaceDraft(name: "Legacy plan", updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
    try PrivateDocuments.writeNew(legacy.encoded(), to: file)
    let store = FittingWorkspaceStore(file: file)
    #expect(store.revisions.isEmpty)
    store.draft.name = "New plan"; store.save()
    #expect(store.revisions.count == 2)
    let old = try #require(store.revisions.first { $0.plan.name == "Legacy plan" })
    let bytes = try Data(contentsOf: file)
    store.draft.name = "Unsaved draft"; store.draft.listeningGoals = "Keep this unfinished note"
    store.useRevision(old.id)
    #expect(store.draft.name == "Legacy plan")
    #expect(try Data(contentsOf: file) == bytes, "Choosing a revision must not replace the current saved plan")
    let checkpoint = try #require(store.revisions.first { $0.plan.name == "Unsaved draft" })
    #expect(checkpoint.archive.reason == .beforeRestoring)
    #expect(checkpoint.plan.listeningGoals == "Keep this unfinished note")
    store.useRevision(checkpoint.id)
    #expect(store.draft.name == "Unsaved draft")
    #expect(store.draft.listeningGoals == "Keep this unfinished note")
    store.save()
    #expect(try FittingWorkspaceDraft.decode(Data(contentsOf: file)).name == "Unsaved draft")
    let reloaded = FittingWorkspaceStore(file: file)
    #expect(reloaded.revisions.count >= 3)
    #expect(reloaded.draft.name == "Unsaved draft")
    for entry in reloaded.revisions {
        let mode = try FileManager.default.attributesOfItem(atPath: entry.file.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        #expect(try FittingPlanRevision.decode(Data(contentsOf: entry.file)).verifiedPlan() == entry.plan)
    }
    let mode = try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("FittingPlanRevisions").path)[.posixPermissions] as? NSNumber
    #expect(mode?.intValue == 0o700)
}

@MainActor @Test func unchangedPlanSavesDoNotCreateDuplicateRevisionsOrAlterSaveTime() throws {
    let folder = historyTestFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("plan.json"), store = FittingWorkspaceStore(file: file)
    store.save(); let bytes = try Data(contentsOf: file), time = store.draft.updatedAt
    #expect(store.revisions.count == 1)
    store.save()
    #expect(store.revisions.count == 1 && store.draft.updatedAt == time)
    #expect(try Data(contentsOf: file) == bytes)
}

@MainActor @Test func historyCorruptionCannotReplaceTheEditorAndFilesRemainAvailable() throws {
    let folder = historyTestFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let store = FittingWorkspaceStore(file: folder.appendingPathComponent("plan.json"))
    store.save(); let entry = try #require(store.revisions.first)
    let corrupt = Data("not a revision".utf8)
    try corrupt.write(to: entry.file)
    store.draft.name = "Keep editor"
    store.useRevision(entry.id)
    #expect(store.draft.name == "Keep editor")
    #expect(store.failedRevisionCount == 1)
    #expect(try Data(contentsOf: entry.file) == corrupt)
    store.save()
    #expect(store.revisions.count == 2 && store.failedRevisionCount == 1)
    #expect(try Data(contentsOf: entry.file) == corrupt)
}

@MainActor @Test func invalidUnsavedPlanCannotBeDiscardedByLoadingARevision() throws {
    let folder = historyTestFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("plan.json"), store = FittingWorkspaceStore(file: file)
    store.save(); let revision = try #require(store.revisions.first), bytes = try Data(contentsOf: file)
    store.draft.name = ""; store.useRevision(revision.id)
    #expect(store.draft.name.isEmpty)
    #expect(try Data(contentsOf: file) == bytes)
}

@MainActor @Test func inaccessibleOrSymlinkedHistoryBlocksReplacementAndPreservesExistingPlan() throws {
    let folder = historyTestFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("plan.json"), history = folder.appendingPathComponent("history")
    try PrivateDocuments.writeNew(FittingWorkspaceDraft(name: "Baseline").encoded(), to: file)
    let real = folder.appendingPathComponent("elsewhere")
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: history, withDestinationURL: real)
    let bytes = try Data(contentsOf: file), store = FittingWorkspaceStore(file: file, revisionFolder: history)
    #expect(store.historyReadFailed)
    store.draft.name = "Changed"; store.save()
    #expect(try Data(contentsOf: file) == bytes)
    #expect(try FileManager.default.contentsOfDirectory(atPath: real.path).isEmpty)
}

@MainActor @Test func externallyChangedPlanIsNotOverwrittenByAnOlderEditor() throws {
    let folder = historyTestFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("plan.json"), store = FittingWorkspaceStore(file: file)
    store.save()
    let external = try FittingWorkspaceDraft(name: "External change").encoded()
    try PrivateDocuments.replace(external, at: file)
    store.draft.name = "Older editor change"; store.save()
    #expect(try Data(contentsOf: file) == external)
    #expect(store.draft.name == "Older editor change")
}

@MainActor @Test func previewPlanDoesNotCreateFilesOrSnapshots() throws {
    let folder = historyTestFolder()
    let store = FittingWorkspaceStore(file: folder.appendingPathComponent("plan.json"), preview: true)
    store.save(); store.reloadHistory(); store.useRevision(UUID())
    #expect(!FileManager.default.fileExists(atPath: folder.path))
    #expect(store.revisions.isEmpty)
}
