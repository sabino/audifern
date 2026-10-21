import Combine
import CompanionCore
import Foundation

@MainActor
final class FittingWorkspaceStore: ObservableObject {
    @Published var draft = FittingWorkspaceDraft()
    @Published private(set) var status: String?
    @Published private(set) var canLoadDraft = false
    @Published private(set) var loadFailed = false
    private let file: URL
    private let preview: Bool

    init(file: URL? = nil, preview: Bool = false) {
        self.preview = preview
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audifern", isDirectory: true).appendingPathComponent("fitting-plan.json")
        draft.name = L("My fitting plan")
        if preview {
            draft.name = L("Everyday clarity"); draft.model = .intent3; draft.rationale = .vacPlus
            draft.programs = [.init(name: L("Everyday"), purpose: .everyday), .init(name: L("Music"), purpose: .music)]
            return
        }
        reload()
    }

    func save() {
        guard !preview, !loadFailed else { return }
        do {
            var updated = draft; updated.updatedAt = Date()
            let data = try updated.encoded()
            try PrivateDocuments.replace(data, at: file)
            let saved = try FittingWorkspaceDraft.decode(PrivateDocuments.read(file, maximumBytes: FittingWorkspaceDraft.maximumFileBytes))
            draft = saved; canLoadDraft = true; status = "Fitting plan saved on this Mac. No settings were sent to the hearing aids."
        } catch { status = "The plan could not be saved. The last saved copy has been preserved." }
    }

    func reload() {
        guard !preview else { return }
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let saved = try FittingWorkspaceDraft.decode(PrivateDocuments.read(file, maximumBytes: FittingWorkspaceDraft.maximumFileBytes))
            draft = saved; canLoadDraft = true; loadFailed = false; status = "Saved fitting plan loaded."
        } catch {
            loadFailed = true; canLoadDraft = false
            status = "The saved fitting plan could not be read. Its file has been preserved; saving is paused."
        }
    }
}
