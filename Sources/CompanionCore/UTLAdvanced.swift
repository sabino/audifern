import Foundation

public enum UTLAdvanced {
    public struct ParseError: LocalizedError, Equatable {
        public let context: String
        public var errorDescription: String? { context }
        public init(_ context: String) { self.context = context }
    }
    public static let equalizerServiceID: UInt32 = 0x02000010
    public static func request(identifier: UInt8, service: UTLProtocol.Service, opcode: UInt8, payload: Data = Data()) throws -> Data {
        guard service.isAvailable, identifier != 0, identifier & 1 == 1 else { throw UTLProtocol.CodecError.malformed("Advanced request identity") }
        return Data([0x0C, identifier, service.handle, opcode]) + payload
    }
    public static func supportsEqualizer(_ service: UTLProtocol.Service, microphone: Bool) -> Bool {
        guard service.isAvailable, service.id == equalizerServiceID else { return false }
        return (service.major == 1 && service.minor <= 2 && (!microphone || service.minor >= 1)) || (service.major == 2 && service.minor == 0)
    }
    public static func equalizerInfo(_ payload: Data) throws -> Double {
        try equalizerMetadata(payload).stepDB
    }
    public struct EqualizerMetadata: Equatable, Sendable {
        public let stepDB: Double
        public let frequenciesHz: [Double]?
    }
    public static func equalizerMetadata(_ payload: Data, legacyConsumerScale: Bool = false) throws -> EqualizerMetadata {
        let values = try UTLCBOR.decodeSequence(payload)
        guard values.count == 1, case .map(let map) = values[0] else { throw OticonEqualizer.EQError.malformed }
        // Companion's supported 1.x readers ignore a reported scale and use
        // this historical conversion. Optional labels are independent of it.
        let scale = legacyConsumerScale ? OticonEqualizer.defaultStepDB : map["stepsize"]?.double
        guard let step = scale,
              step.isFinite, step > 0, step <= 12 else { throw OticonEqualizer.EQError.malformed }
        var frequencies: [Double]?
        if case .array(let vector)? = map["freqs"] {
            let decoded = vector.compactMap(\.double)
            if decoded.count == vector.count, OticonEqualizer.State.validFrequenciesHz(decoded) { frequencies = decoded }
        }
        // Missing or invalid optional labels in a valid CBOR map never invent
        // an axis. The original step and bounded wire decoder remain mandatory.
        return EqualizerMetadata(stepDB: step, frequenciesHz: frequencies)
    }
    public static func equalizerState(_ payload: Data, stepDB: Double, sdkConsumerRangeDB: ClosedRange<Double>? = nil,
                                     frequenciesHz: [Double]? = nil) throws -> OticonEqualizer.State {
        let values = try UTLCBOR.decodeSequence(payload)
        guard values.count == 3 else { throw ParseError("EQ expected three CBOR vectors; received \(values.count) values.") }
        let vectors = try values.enumerated().map { index, value -> [Int] in
            guard case .array(let array) = value else { throw ParseError("EQ vector \(index) is not a CBOR array.") }
            if index == 0 || sdkConsumerRangeDB == nil {
                guard array.count == 8 else { throw ParseError("EQ vector \(index) expected eight coefficients; received \(array.count).") }
            }
            return try array.map {
                guard let int = $0.int else { throw ParseError("EQ vector \(index) contains a noninteger value.") }
                if index != 0 && sdkConsumerRangeDB != nil { return int }
                guard (-128...255).contains(int) else { throw ParseError("EQ vector \(index) contains a non-byte coefficient.") }
                return int > 127 ? int - 256 : int
            }
        }
        if let range = sdkConsumerRangeDB {
            // The installed SDK's 1.1/1.2 GetInstrumentData reads only level,
            // then supplies fixed consumer dB limits; it ignores min/max arrays.
            guard stepDB.isFinite, stepDB > 0 else { throw OticonEqualizer.EQError.malformed }
            let lower = Int((range.lowerBound / stepDB).rounded(.toNearestOrEven)), upper = Int((range.upperBound / stepDB).rounded(.toNearestOrEven))
            guard (-128...127).contains(lower), (-128...127).contains(upper), lower <= upper else { throw OticonEqualizer.EQError.malformed }
            return try OticonEqualizer.State(rawSteps: vectors[0], minimumSteps: .init(repeating: lower, count: 8),
                maximumSteps: .init(repeating: upper, count: 8), stepDB: stepDB, rangesReportedByDevice: false,
                frequenciesHz: frequenciesHz)
        }
        return try OticonEqualizer.State(rawSteps: vectors[0], minimumSteps: vectors[1], maximumSteps: vectors[2],
                                        stepDB: stepDB, frequenciesHz: frequenciesHz)
    }

    /// EQ-only bounded structural information; never use for authentication data.
    public static func equalizerPayloadSummary(_ payload: Data) -> String {
        guard let values = try? UTLCBOR.decodeSequence(payload) else { return "CBOR decode failed" }
        return values.map { value in
            switch value {
            case .array(let array):
                let sample = array.prefix(8).map { $0.int.map(String.init) ?? "noninteger" }.joined(separator: ",")
                return "array[\(array.count)]{\(sample)}"
            case .map(let map): return "map{\(map.keys.sorted().prefix(12).map { String($0.prefix(32)) }.joined(separator: ","))}"
            case .integer(let int): return "integer(\(int))"
            case .number(let number): return "number(\(number))"
            case .text(let text): return "text[\(text.utf8.count)]"
            case .bytes(let data): return "bytes[\(data.count)]"
            case .boolean: return "boolean"
            case .null: return "null"
            }
        }.joined(separator: "; ")
    }
}
