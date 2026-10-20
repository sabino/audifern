import Foundation

/// Consumer remote-control session envelope recovered from the installed SDK.
/// This does not expose exclusive sessions, memory transactions or fitting modes.
public enum UTLConsumerSession {
    public static let serviceID: UInt32 = 0x02000009
    public static let interactiveType: UInt8 = 3
    public static let commandTransactionType: UInt8 = 5

    public static func supports(_ service: UTLProtocol.Service) -> Bool {
        service.isAvailable && service.id == serviceID && service.major == 1 && service.minor <= 1
    }

    /// Application class 3 is the SDK's consumer/OneApp class. The application
    /// version is supplied separately rather than impersonating the vendor build.
    public static func openPayload(service: UTLProtocol.Service, privateToken: UInt32, timeSince2020: UInt32,
                                   applicationClass: UInt8 = 3, version: (UInt16, UInt16, UInt16)) throws -> Data {
        guard supports(service) else { throw UTLProtocol.CodecError.unsupported("Consumer session contract") }
        var result = Data([interactiveType])
        append(privateToken, to: &result); append(timeSince2020, to: &result)
        result.append(applicationClass)
        for component in [version.0, version.1, version.2] {
            result.append(UInt8(truncatingIfNeeded: component >> 8)); result.append(UInt8(truncatingIfNeeded: component))
        }
        if service.minor == 1 { result.append(1) }
        return result
    }

    public static func transactionPayload(id: UInt16, starting: Bool) -> Data {
        let identity = Data([UInt8(truncatingIfNeeded: id >> 8), UInt8(truncatingIfNeeded: id)])
        return starting ? Data([commandTransactionType]) + identity : identity
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        data.append(contentsOf: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) })
    }
}
