import CompanionCore
import Foundation
import Testing
@testable import Audifern

@MainActor @Test func copiedFittingAudiogramIsAnUnsavedDraftAndDoesNotReplaceTheLibrary() throws {
    let store = AudiogramEditorStore(preview: true)
    let original = Audiogram(name: "Saved exam")
    store.library = AudiogramLibrary(exams: [original])
    store.select(original.id)
    let imported = Audiogram(name: "For review", thresholds: [
        .init(key: .init(ear: .right, conduction: .air, frequencyHz: 1500), levelDBHL: 15)
    ])
    #expect(store.reviewImportedExam(imported))
    #expect(store.draft.id == imported.id && store.isDirty && !store.isSaved)
    #expect(store.draft.examDate.isEmpty)
    #expect(store.library.exams == [original])
    #expect(try store.draft.validated() == imported)
    let before = store.draft
    #expect(!store.reviewImportedExam(Audiogram(name: "")))
    #expect(store.draft == before && store.library.exams == [original])
}
