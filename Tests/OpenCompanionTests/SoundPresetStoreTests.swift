import Foundation
import Testing
import CompanionCore
@testable import OpenCompanion

@MainActor
struct SoundPresetStoreTests {
    private func preset(name: String = "Test preset") throws -> SoundPreset {
        try SoundPreset(name: name, aids: [.init(side: .left, model: "Test model", programID: 0, volume: 0, muted: false)])
    }

    @Test func privatePersistenceCanReplaceAndReloadExistingLibrary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("presets.json")
        let store = SoundPresetStore(file: file)
        var saved = try preset()
        try store.save(saved)
        saved.name = "Updated test preset"
        try store.save(saved)
        let reloaded = SoundPresetStore(file: file)
        #expect(reloaded.presets.count == 1)
        #expect(reloaded.presets.first?.name == saved.name)
        let fileMode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        let directoryMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        #expect(fileMode?.intValue == 0o600)
        #expect(directoryMode?.intValue == 0o700)
    }

    @Test func corruptLibraryIsPreservedWhenSaveIsAttempted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("presets.json")
        let original = Data("invalid existing library".utf8)
        try original.write(to: file)
        let store = SoundPresetStore(file: file)
        #expect(store.loadFailed)
        #expect(throws: (any Error).self) { try store.save(preset()) }
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func symbolicLinkCannotRedirectPrivatePresetStorage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("target.json")
        try SoundPresetArchive(presets: [preset()]).encoded().write(to: target)
        let link = directory.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let store = SoundPresetStore(file: link)
        #expect(store.loadFailed)
        #expect(throws: (any Error).self) { try store.save(preset(name: "Replacement")) }
        #expect(try SoundPresetArchive.decode(Data(contentsOf: target)).presets.first?.name == "Test preset")
    }
}
