import Combine
import CompanionCore
import Foundation

@MainActor
final class DeviceBackupStore: ObservableObject {
    struct Entry: Identifiable {
        let backup: DeviceBackup
        let file: URL
        let digest: String
        var id: UUID { backup.id }
    }
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var failedFileCount = 0
    @Published private(set) var libraryReadFailed = false
    @Published private(set) var status: String?
    let folder: URL

    init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audifern/Backups", isDirectory: true)
        reload()
    }

    @discardableResult func save(_ backup: DeviceBackup) throws -> URL {
        let file = folder.appendingPathComponent("\(backup.id.uuidString.lowercased()).audifern-backup.json")
        try PrivateDocuments.writeVerifiedBackup(backup, to: file)
        reload()
        if failedFileCount == 0 && !libraryReadFailed { status = "Backup saved and verified on this Mac." }
        return file
    }

    func reload() {
        var loaded: [Entry] = [], failures = 0
        do {
            if (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw CocoaError(.fileReadNoPermission) }
            guard FileManager.default.fileExists(atPath: folder.path) else {
                entries = []; failedFileCount = 0; libraryReadFailed = false; status = nil; return
            }
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasSuffix(".audifern-backup.json") }
            // Do not silently omit older backups from an overfull directory.
            guard files.count <= 1000 else { throw CocoaError(.fileReadTooLarge) }
            for file in files {
                do {
                    let archive = try DeviceBackupArchive.decode(PrivateDocuments.read(file, maximumBytes: DeviceBackupArchive.maximumBytes))
                    loaded.append(Entry(backup: try archive.verifiedBackup(), file: file, digest: archive.sha256))
                } catch { failures += 1 }
            }
            entries = loaded.sorted { $0.backup.capturedAt > $1.backup.capturedAt }
            failedFileCount = failures
            libraryReadFailed = false
            status = failures > 0 ? "Some backups could not be verified. Their files have been preserved." : nil
        } catch {
            libraryReadFailed = true
            status = "The backup library could not be read. Existing files have been preserved."
        }
    }
}
