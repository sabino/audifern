import CompanionCore
import Foundation
import SwiftUI

@MainActor
final class AudiogramEditorStore: ObservableObject {
    @Published var library = AudiogramLibrary()
    @Published var draft = AudiogramDraft()
    @Published private(set) var error: String?
    @Published private(set) var status = ""
    @Published private(set) var loadFailed = false
    private var repository: AudiogramRepository?
    private var baseline: AudiogramDraft

    init(selectedExamID: UUID? = nil) {
        let initial = AudiogramDraft()
        baseline = initial
        draft = initial
        do {
            let repository = try AudiogramRepository.applicationSupport()
            self.repository = repository
            library = try repository.load()
            let selected = selectedExamID.flatMap { id in library.exams.first { $0.id == id } } ?? library.exams.last
            if let selected { draft = AudiogramDraft(selected); baseline = draft }
        } catch {
            loadFailed = true
            self.error = "Could not read local audiograms. The saved file was left unchanged."
        }
    }

    var isDirty: Bool { draft != baseline }
    var isSaved: Bool { library.exams.contains { $0.id == draft.id } }
    var validationError: String? {
        do { _ = try draft.validated(); return nil }
        catch { return error.localizedDescription }
    }
    var plottedThresholds: [AudiogramThreshold] {
        // A malformed cell never becomes an invented point or suppresses other valid cells.
        draft.cells.compactMap { key, cell in
            guard let value = try? Audiogram.parseLevel(cell.text, for: key) else { return nil }
            return AudiogramThreshold(key: key, levelDBHL: value, noResponse: cell.noResponse)
        }
    }

    func text(for key: AudiogramThresholdKey) -> String { draft.cells[key]?.text ?? "" }
    func noResponse(for key: AudiogramThresholdKey) -> Bool { draft.cells[key]?.noResponse ?? false }

    func setText(_ text: String, for key: AudiogramThresholdKey) {
        var cell = draft.cells[key] ?? .init()
        cell.text = text
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.cells.removeValue(forKey: key)
        } else {
            draft.cells[key] = cell
        }
        status = ""
    }

    func setNoResponse(_ value: Bool, for key: AudiogramThresholdKey) {
        var cell = draft.cells[key] ?? .init()
        cell.noResponse = value
        draft.cells[key] = cell
        status = ""
    }

    func newExam() {
        draft = AudiogramDraft(); baseline = draft; error = nil; status = ""
    }

    func select(_ id: UUID) {
        guard let exam = library.exams.first(where: { $0.id == id }) else { return }
        draft = AudiogramDraft(exam); baseline = draft; error = nil; status = ""
    }

    func revert() { draft = baseline; error = nil; status = "" }

    func clearThresholds() { draft.cells = [:]; error = nil; status = "" }

    @discardableResult
    func save() -> Audiogram? {
        guard !loadFailed, let repository else { return nil }
        do {
            let exam = try draft.validated()
            var replacement = library
            if let index = replacement.exams.firstIndex(where: { $0.id == exam.id }) {
                replacement.exams[index] = exam
            } else {
                replacement.exams.append(exam)
            }
            try repository.save(replacement)
            library = replacement; draft = AudiogramDraft(exam); baseline = draft
            error = nil; status = "Saved on this Mac."
            return exam
        } catch { self.error = error.localizedDescription; return nil }
    }

    func deleteExam() {
        guard !loadFailed, let repository, isSaved else { return }
        do {
            var replacement = library
            replacement.exams.removeAll { $0.id == draft.id }
            try repository.save(replacement)
            library = replacement
            if let next = library.exams.last { select(next.id) } else { newExam() }
            error = nil; status = "Exam deleted from this Mac."
        } catch { self.error = error.localizedDescription }
    }

    func prepareExport() -> Data? {
        do {
            error = nil
            return try AudiogramLibrary(exams: [draft.validated()]).encoded()
        } catch { self.error = error.localizedDescription; return nil }
    }

    func prepareHIMSAExport(signal: HIMSAAudiogramExport.Signal,
                           airTransducer: HIMSAAudiogramExport.AirTransducer?) -> Data? {
        do {
            let result = try HIMSAAudiogramExport.xml(for: draft.validated(), signal: signal, airTransducer: airTransducer)
            error = nil
            return result
        } catch { self.error = error.localizedDescription; return nil }
    }

    func importExam(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= AudiogramRepository.maximumFileBytes else { throw AudiogramError.fileTooLarge }
            let imported = try AudiogramLibrary.decode(Data(contentsOf: url))
            guard imported.exams.count == 1, let exam = imported.exams.first else {
                error = "Choose a single exam exported by Open Companion."
                return
            }
            draft = AudiogramDraft(exam)
            baseline = library.exams.first(where: { $0.id == exam.id }).map(AudiogramDraft.init) ?? AudiogramDraft(Audiogram(id: exam.id))
            error = nil; status = "Imported for review. Save to keep it on this Mac."
        } catch {
            self.error = (error as? AudiogramError)?.localizedDescription ?? "This file is not a valid Open Companion audiogram."
        }
    }

    func reportExport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                error = nil; status = "Exam exported."
            } catch {
                self.error = "The exam was exported, but its file permissions could not be restricted."
            }
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError { self.error = "The exam could not be exported." }
        }
    }

    func reportImportError(_ error: Error) {
        if (error as NSError).code != NSUserCancelledError { self.error = "The exam could not be imported." }
    }
}
