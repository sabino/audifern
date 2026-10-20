import Combine
import CompanionCore
import Foundation

@MainActor
final class SoundPresetStore: ObservableObject {
    @Published private(set) var presets: [SoundPreset] = []
    @Published var error: String?
    @Published var linkedAudiogramID: UUID?
    @Published var linkedAudiogramLabel: String?
    @Published private(set) var loadFailed = false
    private let file: URL

    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Open Companion", isDirectory: true).appendingPathComponent("sound-presets.json")
        do {
            try Self.refuseSymbolicLinks(self.file)
            if FileManager.default.fileExists(atPath: self.file.path) {
                presets = try SoundPresetArchive.decode(Data(contentsOf: self.file)).presets
            }
        } catch {
            self.loadFailed = true
            self.error = "Could not read your saved sound presets: \(error.localizedDescription). The existing file has been preserved."
        }
    }

    func save(_ preset: SoundPreset) throws {
        try preset.validate()
        var updated = presets
        if let index = updated.firstIndex(where: { $0.id == preset.id }) { updated[index] = preset }
        else { updated.append(preset) }
        try persist(updated)
    }

    func delete(_ id: UUID) throws { try persist(presets.filter { $0.id != id }) }

    private func persist(_ updated: [SoundPreset]) throws {
        guard !loadFailed else {
            throw SoundPreset.ValidationError.invalid("The existing preset library could not be loaded. Restore it before saving changes.")
        }
        try Self.refuseSymbolicLinks(file)
        let data = try SoundPresetArchive(presets: updated).encoded()
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let temporary = folder.appendingPathComponent(".presets-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil,
                                              attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary)
        if FileManager.default.fileExists(atPath: file.path) {
            _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
        } else { try FileManager.default.moveItem(at: temporary, to: file) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        presets = updated; error = nil
    }

    private static func refuseSymbolicLinks(_ file: URL) throws {
        for url in [file.deletingLastPathComponent(), file] {
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw SoundPreset.ValidationError.invalid("Preset storage cannot use a symbolic link.")
            }
        }
    }
}
