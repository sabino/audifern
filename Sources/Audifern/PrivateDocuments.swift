import Darwin
import CompanionCore
import Foundation

/// Small private documents, with exclusive creation and no symlink following.
/// A failed save leaves an existing document intact. Callers choose whether an
/// explicit replace is appropriate; backups always use a new UUID filename.
enum PrivateDocuments {
    @discardableResult static func writeVerifiedBackup(_ backup: DeviceBackup, to url: URL) throws -> DeviceBackupArchive {
        let archive = try DeviceBackupArchive(backup)
        try writeNew(try archive.encoded(), to: url)
        let readback = try DeviceBackupArchive.decode(read(url, maximumBytes: DeviceBackupArchive.maximumBytes))
        guard readback.payload == archive.payload else { throw DeviceBackup.BackupError.invalid }
        return readback
    }

    static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        try refuseLinks(url)
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        return data
    }

    static func writeNew(_ data: Data, to url: URL) throws {
        try prepareParent(url)
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data); try handle.synchronize(); try handle.close()
        } catch {
            try? handle.close(); try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    static func replace(_ data: Data, at url: URL) throws {
        try prepareParent(url)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".document-\(UUID().uuidString).tmp")
        try writeNew(data, to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        // rename is atomic on this directory's filesystem. Never open an
        // existing destination, even when it is a symlink created after checks.
        guard Darwin.rename(temporary.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func prepareParent(_ url: URL) throws {
        try refuseLinks(url)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // FileManager applies 0700 when creating a new directory. An explicit
        // CLI destination may already be shared; never chmod an unrelated
        // existing parent just to create a private 0600 file inside it.
        let values = try parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw CocoaError(.fileWriteNoPermission) }
        try refuseLinks(url)
    }

    private static func refuseLinks(_ url: URL) throws {
        // Resolve the user's application-support hierarchy normally; refuse
        // links in the dedicated document directory and document itself.
        for item in [url.deletingLastPathComponent(), url] {
            if (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw CocoaError(.fileReadNoPermission)
            }
        }
    }
}
