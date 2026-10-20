import Foundation

/// Read-only battery telemetry from Companion's versioned UTL contracts.
/// Remaining time is calculated from reported charge/current, never percentage.
public enum OticonBattery {
    public static let serviceID: UInt32 = 0x01000007
    public static let legacyInfoCharacteristic = "D5D0AFFB-35B8-4FDC-A50B-F777C90293B8"
    public static let fastInfoOpcode: UInt8 = 2
    public static let slowInfoOpcode: UInt8 = 1
    public static let batteryStateChangedEvent: UInt8 = 1
    public static let currentDrawChangedEvent: UInt8 = 2
    public static let pollingIntervalSeconds: TimeInterval = 300

    public enum DecodeError: Error, Equatable {
        case unsupportedVersion, malformed
    }

    public struct State: Equatable, Sendable {
        public let rawLevel: Int
        public var percentage: Int? { (0...100).contains(rawLevel) ? rawLevel : nil }
        public let remainingCharge: Int?
        public let currentDraw: Int?
        public let batteryLow: Bool?
        public let isDischarging: Bool?
        public let chargingDone: Bool?
        public var isCharging: Bool? { isDischarging.map { !$0 } }
        public var hasCorruptZeroTelemetry: Bool { remainingCharge == 0 && currentDraw == 0 }

        /// The shipped app treats reported charge / reported draw as hours.
        /// The absolute charge/current scales are not established by the contract.
        /// This app additionally suppresses the estimate when explicitly charging,
        /// or when signed/unknown telemetry cannot describe a remaining duration.
        public var estimatedTimeLeftSeconds: TimeInterval? {
            guard let remainingCharge, remainingCharge >= 0,
                  let currentDraw, currentDraw > 0, currentDraw <= Int(Int32.max),
                  isDischarging != false, chargingDone != true else { return nil }
            return Double(remainingCharge) / Double(currentDraw) * 3600
        }
    }

    /// Health fields have no proven time unit. In particular, lifespan is not
    /// remaining runtime and must not be displayed as hours/minutes.
    public struct Health: Equatable, Sendable {
        public let lifespan: Int
        public let lifespanThreshold: Int
        public let slowAverageCurrentDraw: Int
        public let fullChargeCapacity: Int
    }

    public struct LegacyInfo: Equatable, Sendable {
        public let rawLevel: UInt8
        public var percentage: Int? { rawLevel <= 100 ? Int(rawLevel) : nil }
        public let lifespan: UInt8
        public let threshold: UInt8
    }

    public static func supports(_ service: UTLProtocol.Service) -> Bool {
        service.isAvailable && service.id == serviceID
            && ((service.major == 1 && service.minor <= 1) || (service.major == 2 && service.minor == 0))
    }

    public static func fastState(_ payload: Data, service: UTLProtocol.Service) throws -> State {
        guard supports(service) else { throw DecodeError.unsupportedVersion }
        // The schema consumes three BE32 fields and MSB-first Boolean bits at
        // byte 12. The shipped decoder does not require payload exhaustion.
        // Battery 2.0 has also been observed returning 16 bytes, with a nonzero
        // three-byte tail unconsumed by that schema. Its meaning is unknown;
        // do not reinterpret it as additional Boolean words or require zeros.
        // Limit acceptance to the minimal shape and this observed 2.0 shape.
        guard payload.count == 13 || (service.major == 2 && payload.count == 16) else {
            throw DecodeError.malformed
        }
        let bytes = Array(payload), flags = bytes[12]
        return State(rawLevel: Int(unsigned32(bytes, at: 0)),
                     remainingCharge: Int(Int32(bitPattern: unsigned32(bytes, at: 4))),
                     currentDraw: Int(unsigned32(bytes, at: 8)), batteryLow: flags & 0x80 != 0,
                     isDischarging: flags & 0x40 != 0,
                     chargingDone: service.major == 2 ? flags & 0x20 != 0 : nil)
    }

    public static func slowHealth(_ payload: Data, service: UTLProtocol.Service) throws -> Health {
        guard supports(service) else { throw DecodeError.unsupportedVersion }
        guard payload.count == 16 else { throw DecodeError.malformed }
        let bytes = Array(payload)
        return Health(lifespan: Int(unsigned32(bytes, at: 0)),
                      lifespanThreshold: Int(unsigned32(bytes, at: 4)),
                      slowAverageCurrentDraw: Int(unsigned32(bytes, at: 8)),
                      fullChargeCapacity: Int(Int32(bitPattern: unsigned32(bytes, at: 12))))
    }

    /// Battery state/current-draw events carry the same fields as fastInfo.
    /// Ignore unrelated services and event codes without interpreting their bytes.
    public static func eventState(_ message: UTLProtocol.ServiceMessage,
                                  service: UTLProtocol.Service) throws -> State? {
        guard message.messageType == .event, message.serviceHandle == service.handle,
              [batteryStateChangedEvent, currentDrawChangedEvent].contains(message.code) else { return nil }
        return try fastState(message.payload, service: service)
    }

    public static func legacyInfo(_ data: Data) throws -> LegacyInfo {
        guard data.count == 3 else { throw DecodeError.malformed }
        let bytes = Array(data)
        return LegacyInfo(rawLevel: bytes[0], lifespan: bytes[1], threshold: bytes[2])
    }

    public static func standardState(_ data: Data) throws -> State {
        guard data.count == 1, let value = data.first else { throw DecodeError.malformed }
        return State(rawLevel: Int(value), remainingCharge: nil, currentDraw: nil,
                     batteryLow: nil, isDischarging: nil, chargingDone: nil)
    }

    /// Exact shipped stabilization rule: only a positive reported pairing timer
    /// adds the version's offset. A zero/absent timer has zero delay in the SDK.
    /// This helper does not invent a pairing timer from connection age.
    public static func settlingDelaySeconds(pairingTimerSeconds: UInt32?,
                                            service: UTLProtocol.Service) throws -> TimeInterval {
        guard supports(service) else { throw DecodeError.unsupportedVersion }
        guard let pairingTimerSeconds, pairingTimerSeconds > 0 else { return 0 }
        return TimeInterval(pairingTimerSeconds) + (service.major == 2 ? 300 : 60)
    }

    private static func unsigned32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }
}
