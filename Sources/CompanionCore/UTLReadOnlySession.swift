import Foundation

/// Genie 2026.2's minimal read-only session, without its controlled-state,
/// high-speed, keepalive, memory-write or device-update setup. Unknown session
/// versions are refused. See docs/fitting-backups.md for the read boundary.
public enum UTLReadOnlySession {
    public static let type: UInt8 = 4
    public static let readNVRAMTransaction: UInt8 = 2

    public static func openPayload(service: UTLProtocol.Service, privateToken: UInt32,
                                   timeSince2020: UInt32, version: (UInt16, UInt16, UInt16)) throws -> Data {
        guard UTLConsumerSession.supports(service), service.minor == 1 else {
            throw UTLProtocol.CodecError.unsupported("Read-only session contract")
        }
        var data = try UTLConsumerSession.openPayload(service: service, privateToken: privateToken,
            timeSince2020: timeSince2020, version: version)
        data[0] = type
        return data
    }
}
