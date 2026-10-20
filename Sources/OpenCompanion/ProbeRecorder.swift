import Darwin
import Foundation

/// Probe evidence is written only to the explicitly requested, mode-0600 local file.
@MainActor
final class ProbeRecorder {
    private let handle: FileHandle
    private let encoder: JSONEncoder

    init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    func append(_ event: SessionEvent) throws {
        var bytes = try encoder.encode(event)
        bytes.append(0x0A)
        try handle.write(contentsOf: bytes)
    }

    func finish() {
        try? handle.synchronize()
        try? handle.close()
    }
}
