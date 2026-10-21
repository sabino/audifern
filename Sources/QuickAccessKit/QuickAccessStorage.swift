import Foundation

/// A local app-group mailbox. Files have bounded sizes/lifetimes and commands
/// are claimed by rename before execution, so stale actions cannot replay.
public struct QuickAccessStorage: Sendable {
    public let folder: URL
    public var inbox: URL { folder.appendingPathComponent("inbox", isDirectory: true) }
    private var results: URL { folder.appendingPathComponent("results", isDirectory: true) }
    public init(container: URL) { folder = container.appendingPathComponent("AudifernQuickAccess", isDirectory: true) }
    public static func applicationGroup(bundle: Bundle = .main) -> QuickAccessStorage? {
        guard let group = bundle.object(forInfoDictionaryKey: "AudifernAppGroupIdentifier") as? String,
              group.range(of: #"^[A-Z0-9]{10}\.org\.audifern\.shared$"#, options: .regularExpression) != nil,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return .init(container: container)
    }
    public func prepare() throws {
        for directory in [folder, inbox, results] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw StorageError.unavailable }
        }
    }
    public func save(_ state: QuickAccessState) throws {
        try prepare()
        try write(state, to: folder.appendingPathComponent("state.json"))
    }
    public func state() -> QuickAccessState? { read(QuickAccessState.self, at: folder.appendingPathComponent("state.json"), maximum: 65_536) }
    public func enqueue(_ command: QuickCommand, now: Date = Date()) throws {
        guard let state = state(), state.permits(command, at: now) else { throw StorageError.unavailable }
        try prepare()
        guard (try FileManager.default.contentsOfDirectory(atPath: inbox.path)).count < 24 else { throw StorageError.unavailable }
        try write(command, to: inbox.appendingPathComponent(command.id.uuidString + ".json"))
    }
    public func claimNext(now: Date = Date()) -> QuickCommand? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) else { return nil }
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(32) {
            guard file.pathExtension == "json", UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil else { try? FileManager.default.removeItem(at: file); continue }
            let claimed = file.appendingPathExtension("claimed")
            guard (try? FileManager.default.moveItem(at: file, to: claimed)) != nil else { continue }
            let command = read(QuickCommand.self, at: claimed, maximum: 4_096)
            try? FileManager.default.removeItem(at: claimed)
            if let command, command.id.uuidString + ".json" == file.lastPathComponent, command.isValid(at: now) { return command }
        }
        return nil
    }
    public func acknowledge(_ receipt: QuickReceipt) throws { try write(receipt, to: results.appendingPathComponent(receipt.id.uuidString + ".json")) }
    public func receipt(_ id: UUID) -> QuickReceipt? { read(QuickReceipt.self, at: results.appendingPathComponent(id.uuidString + ".json"), maximum: 4_096) }
    public func removeReceipt(_ id: UUID) { try? FileManager.default.removeItem(at: results.appendingPathComponent(id.uuidString + ".json")) }
    public func cleanup(now: Date = Date()) {
        for directory in [inbox, results] {
            for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if now.timeIntervalSince(date) > 30 || file.pathExtension == "claimed" { try? FileManager.default.removeItem(at: file) }
            }
        }
    }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let bytes = try JSONEncoder().encode(value)
        try bytes.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func read<T: Decodable>(_ type: T.Type, at url: URL, maximum: Int) -> T? {
        guard let attributes = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              attributes.isRegularFile == true, attributes.isSymbolicLink != true,
              let size = attributes.fileSize, size <= maximum, let bytes = try? Data(contentsOf: url), bytes.count <= maximum else { return nil }
        return try? JSONDecoder().decode(type, from: bytes)
    }
    public enum StorageError: Error { case unavailable }
}
