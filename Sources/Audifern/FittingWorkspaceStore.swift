import Combine
import CompanionCore
import Foundation

@MainActor
final class FittingWorkspaceStore: ObservableObject {
    struct Revision: Identifiable {
        let archive: FittingPlanRevision
        let plan: FittingWorkspaceDraft
        let file: URL
        var id: UUID { archive.id }
    }
    @Published var draft = FittingWorkspaceDraft()
    @Published private(set) var status: String?
    @Published private(set) var canLoadDraft = false
    @Published private(set) var loadFailed = false
    @Published private(set) var revisions: [Revision] = []
    @Published private(set) var failedRevisionCount = 0
    @Published private(set) var historyReadFailed = false
    private let file: URL
    private let revisionFolder: URL
    private let preview: Bool
    private var lastSavedData: Data?

    init(file: URL? = nil, revisionFolder: URL? = nil, preview: Bool = false) {
        self.preview = preview
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audifern", isDirectory: true).appendingPathComponent("fitting-plan.json")
        self.revisionFolder = revisionFolder ?? self.file.deletingLastPathComponent()
            .appendingPathComponent("FittingPlanRevisions", isDirectory: true)
        draft.name = L("My fitting plan")
        if preview {
            draft.name = L("Everyday clarity"); draft.model = .intent3; draft.rationale = .vacPlus
            draft.programs = [.init(name: L("Everyday"), purpose: .everyday), .init(name: L("Music"), purpose: .music)]
            return
        }
        reload()
        reloadHistory()
    }

    func save() {
        guard !preview, !loadFailed else { return }
        do {
            // Preserve an existing legacy plan before replacing it. Refuse a
            // concurrent disk edit instead of overwriting a newly changed file.
            let previous = try currentSavedPlan()
            if let previous { try preserve(previous, reason: .savedPlan) }
            if let previous, FittingPlanComparison(previous, draft).isUnchanged {
                reloadHistory(); status = "No changes to save. Your saved plan is preserved."; return
            }
            var updated = draft; updated.updatedAt = Date()
            let data = try updated.encoded()
            try preserve(updated, reason: .savedPlan)
            try PrivateDocuments.replace(data, at: file)
            let readback = try PrivateDocuments.read(file, maximumBytes: FittingWorkspaceDraft.maximumFileBytes)
            guard readback == data else { throw CocoaError(.fileWriteUnknown) }
            let saved = try FittingWorkspaceDraft.decode(readback)
            lastSavedData = readback
            draft = saved; canLoadDraft = true; status = "Fitting plan saved on this Mac. No settings were sent to the hearing aids."
            reloadHistory()
        } catch {
            reloadHistory()
            status = "The plan could not be saved. The last saved copy has been preserved."
        }
    }

    func reload() {
        guard !preview else { return }
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let bytes = try PrivateDocuments.read(file, maximumBytes: FittingWorkspaceDraft.maximumFileBytes)
            let saved = try FittingWorkspaceDraft.decode(bytes)
            lastSavedData = bytes
            draft = saved; canLoadDraft = true; loadFailed = false; status = "Saved fitting plan loaded."
        } catch {
            loadFailed = true; canLoadDraft = false
            status = "The saved fitting plan could not be read. Its file has been preserved; saving is paused."
        }
    }

    /// Selecting a revision only loads the editor. Its unsaved contents get an
    /// immutable checkpoint first; the current saved plan is not replaced.
    func useRevision(_ id: UUID) {
        guard !preview, !loadFailed, let entry = revisions.first(where: { $0.id == id }) else { return }
        do {
            let verified = try readRevision(entry.file)
            guard verified.id == entry.id, verified.archive.payload == entry.archive.payload else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if !FittingPlanComparison(draft, verified.plan).isUnchanged {
                try preserve(draft, reason: .beforeRestoring)
            }
            draft = verified.plan
            reloadHistory()
            status = "Revision loaded into the editor. Your previous draft is preserved in history. Save when ready."
        } catch {
            reloadHistory()
            status = "The revision could not be loaded. Your editor and saved plan have been preserved."
        }
    }

    func reloadHistory() {
        guard !preview else { return }
        do {
            if (try? revisionFolder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw CocoaError(.fileReadNoPermission)
            }
            guard FileManager.default.fileExists(atPath: revisionFolder.path) else {
                revisions = []; failedRevisionCount = 0; historyReadFailed = false; return
            }
            let files = try FileManager.default.contentsOfDirectory(at: revisionFolder, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasSuffix(".audifern-plan-revision.json") }
            guard files.count <= 1000 else { throw CocoaError(.fileReadTooLarge) }
            var loaded: [Revision] = [], failed = 0, identifiers = Set<UUID>()
            for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                do {
                    let revision = try readRevision(url)
                    guard identifiers.insert(revision.id).inserted else { throw CocoaError(.fileReadCorruptFile) }
                    loaded.append(revision)
                } catch { failed += 1 }
            }
            revisions = loaded.sorted {
                if $0.archive.savedAt != $1.archive.savedAt { return $0.archive.savedAt > $1.archive.savedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            failedRevisionCount = failed; historyReadFailed = false
        } catch { historyReadFailed = true }
    }

    private func currentSavedPlan() throws -> FittingWorkspaceDraft? {
        guard FileManager.default.fileExists(atPath: file.path) else {
            guard lastSavedData == nil else { throw CocoaError(.fileNoSuchFile) }
            return nil
        }
        let bytes = try PrivateDocuments.read(file, maximumBytes: FittingWorkspaceDraft.maximumFileBytes)
        guard bytes == lastSavedData else { throw CocoaError(.fileWriteFileExists) }
        return try FittingWorkspaceDraft.decode(bytes)
    }

    private func readRevision(_ url: URL) throws -> Revision {
        let archive = try FittingPlanRevision.decode(PrivateDocuments.read(url, maximumBytes: FittingPlanRevision.maximumBytes))
        return .init(archive: archive, plan: try archive.verifiedPlan(), file: url)
    }

    private func preserve(_ plan: FittingWorkspaceDraft, reason: FittingPlanRevision.Reason) throws {
        let archive = try FittingPlanRevision(plan, reason: reason)
        reloadHistory()
        guard !historyReadFailed, revisions.count + failedRevisionCount < 1000 else { throw CocoaError(.fileWriteUnknown) }
        for entry in revisions where entry.archive.payload == archive.payload {
            // Re-read before relying on a snapshot that could have changed on
            // disk since the library was scanned.
            if try readRevision(entry.file).archive.payload == archive.payload { return }
        }
        let url = revisionFolder.appendingPathComponent("\(archive.id.uuidString.lowercased()).audifern-plan-revision.json")
        try PrivateDocuments.writeNew(archive.encoded(), to: url)
        guard try readRevision(url).archive.payload == archive.payload else { throw CocoaError(.fileWriteUnknown) }
    }
}
