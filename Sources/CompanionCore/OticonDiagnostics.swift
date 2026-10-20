import Foundation

/// Read-only diagnostic counters. This API does not retrieve or clear dumps.
public enum OticonDiagnostics {
    public static let coreDumpServiceID: UInt32 = 0x0200000C
    public static let coreDumpInfoOpcode: UInt8 = 0

    public enum DecodeError: Error, Equatable { case unsupportedVersion, malformed }

    public struct CoreDumpInfo: Equatable, Sendable {
        public let lastDumpCounter: UInt16
        public let storedCrashDumps: UInt16
    }

    public static func supportsCoreDumpInfo(_ service: UTLProtocol.Service) -> Bool {
        service.isAvailable && service.id == coreDumpServiceID && service.major == 1 && service.minor == 0
    }

    public static func coreDumpInfo(_ payload: Data, service: UTLProtocol.Service) throws -> CoreDumpInfo {
        guard supportsCoreDumpInfo(service) else { throw DecodeError.unsupportedVersion }
        guard payload.count == 4 else { throw DecodeError.malformed }
        let bytes = Array(payload)
        return CoreDumpInfo(lastDumpCounter: UInt16(bytes[0]) << 8 | UInt16(bytes[1]),
                            storedCrashDumps: UInt16(bytes[2]) << 8 | UInt16(bytes[3]))
    }
}
