import Foundation

/// Consumer Speech Booster mappings from the shipped Companion SDK.
/// MCESystemControl.reset resets its three adjustments, not the hearing aid.
public enum OticonSpeechBooster {
    public static let serviceID: UInt32 = 0x02000013
    public static let legacyCharacteristic = "9215A295-B813-483F-9F85-B700D0B7BC75"

    public static func supports(_ service: UTLProtocol.Service) -> Bool {
        service.isAvailable && service.id == serviceID && service.major == 1 && (1...2).contains(service.minor)
    }

    public struct Adjustment: Equatable, Sendable {
        public let value: Int
        public let range: ClosedRange<Int>
        public init(_ payload: Data) throws {
            let values = payload.map { Int(Int8(bitPattern: $0)) }
            guard values.count == 3, values[1] <= values[2], (values[1]...values[2]).contains(values[0]) else {
                throw UTLAdvanced.ParseError("Speech Booster adjustment expected a signed value/min/max triple.")
            }
            value = values[0]; range = values[1]...values[2]
        }
    }

    public struct State: Equatable, Sendable {
        public let noiseReduction: Adjustment
        public let directionality: Adjustment
        public let targetLoss: Adjustment
        public var isEnabled: Bool {
            [noiseReduction, directionality, targetLoss].allSatisfy { $0.value == $0.range.upperBound }
        }
        public init(noiseReduction: Data, directionality: Data, targetLoss: Data) throws {
            self.noiseReduction = try Adjustment(noiseReduction)
            self.directionality = try Adjustment(directionality)
            self.targetLoss = try Adjustment(targetLoss)
        }

        /// Values are the reported maxima, never assumed model-specific levels.
        public var enableCommands: [(opcode: UInt8, payload: Data)] {
            zip([UInt8(1), 3, 5], [noiseReduction, directionality, targetLoss]).map { opcode, adjustment in
                (opcode, Data([UInt8(bitPattern: Int8(adjustment.range.upperBound))]))
            }
        }
    }

    private static func legacyBoostBytes(length: Int) -> [UInt8]? {
        switch length {
        case 7, 8: return [2, 4, 1, 1, 4]
        case 9: return [3, 4, 5, 5, 3, 3]
        default: return nil
        }
    }
    public static func legacyEnabled(_ data: Data) -> Bool? {
        guard let expected = legacyBoostBytes(length: data.count) else { return nil }
        return Array(data.dropFirst(2).prefix(expected.count)) == expected
    }
    public static func legacyPayload(current: Data, enabled: Bool) throws -> Data {
        guard let bytes = legacyBoostBytes(length: current.count) else { throw OticonEqualizer.EQError.unsupported }
        var result = Array(current)
        result.replaceSubrange(2..<(2 + bytes.count), with: enabled ? bytes : .init(repeating: 255, count: bytes.count))
        return Data(result)
    }
}
