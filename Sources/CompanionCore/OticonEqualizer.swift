import Foundation

/// Companion's user equalizers, separate from prescriptive fitting gain.
public enum OticonEqualizer {
    public static let legacyCharacteristic = "60415E72-C345-417A-BB2B-BBBA95B2C9A3"
    public static let defaultStepDB = 20 * log10(2.0) / 32
    public static let groups = [0..<1, 1..<4, 4..<8]

    public enum EQError: LocalizedError, Equatable {
        case malformed, outOfRange, unsupported
        public var errorDescription: String? {
            switch self {
            case .malformed: return "Equalizer data has an invalid format or range."
            case .outOfRange: return "Equalizer values exceed the supported consumer range."
            case .unsupported: return "This equalizer data format is not supported."
            }
        }
    }

    public struct State: Equatable, Sendable {
        public let rawSteps: [Int]
        public let minimumSteps: [Int]
        public let maximumSteps: [Int]
        public let stepDB: Double
        public let rangesReportedByDevice: Bool
        /// Optional frequencies reported by this aid's consumer EQ get_info.
        /// No fitted-gain or streaming-source frequency map is substituted.
        public let frequenciesHz: [Double]?

        public init(rawSteps: [Int], minimumSteps: [Int], maximumSteps: [Int], stepDB: Double,
                    rangesReportedByDevice: Bool = true, frequenciesHz: [Double]? = nil) throws {
            guard [rawSteps, minimumSteps, maximumSteps].allSatisfy({ $0.count == 8 && $0.allSatisfy { (-128...127).contains($0) } }),
                  stepDB.isFinite, stepDB > 0, stepDB <= 12,
                  (0..<8).allSatisfy({ minimumSteps[$0] <= maximumSteps[$0] && (minimumSteps[$0]...maximumSteps[$0]).contains(rawSteps[$0]) }),
                  frequenciesHz.map(Self.validFrequenciesHz) ?? true else { throw EQError.malformed }
            self.rawSteps = rawSteps; self.minimumSteps = minimumSteps; self.maximumSteps = maximumSteps
            self.stepDB = stepDB; self.rangesReportedByDevice = rangesReportedByDevice
            self.frequenciesHz = frequenciesHz
        }

        static func validFrequenciesHz(_ values: [Double]) -> Bool {
            values.count == 8 && values.allSatisfy { $0.isFinite && (20...24_000).contains($0) }
                && zip(values, values.dropFirst()).allSatisfy { $0.0 < $0.1 }
        }

        public var channelDB: [Double] { rawSteps.map { Double($0) * stepDB } }
        public var channelRangesDB: [ClosedRange<Double>] {
            zip(minimumSteps, maximumSteps).map { Double($0.0) * stepDB...Double($0.1) * stepDB }
        }
        public var threeBandDB: [Double] { groups.map { group in Double(group.map { rawSteps[$0] }.min()!) * stepDB } }
        public var threeBandRangesDB: [ClosedRange<Double>] {
            groups.map { group in
                let lower = Double(group.map { minimumSteps[$0] }.max()!) * stepDB
                let upper = Double(group.map { maximumSteps[$0] }.min()!) * stepDB
                return lower...max(lower, upper)
            }
        }

        public func steps(forThreeBandDB levels: [Double]) throws -> [Int] {
            guard levels.count == 3, levels.allSatisfy(\.isFinite) else { throw EQError.malformed }
            var result = [Int](repeating: 0, count: 8)
            for (index, group) in groups.enumerated() {
                let raw = (levels[index] / stepDB).rounded(.toNearestOrEven)
                guard (-128...127).contains(raw) else { throw EQError.outOfRange }
                for band in group { result[band] = Int(raw) }
            }
            try validate(result)
            return result
        }

        /// Independent consumer channels, in the device's existing wire order.
        /// Frequency labels require a separately verified map for that source.
        public func steps(forChannelDB levels: [Double]) throws -> [Int] {
            guard levels.count == 8, levels.allSatisfy(\.isFinite) else { throw EQError.malformed }
            let steps = try levels.map { level -> Int in
                let value = (level / stepDB).rounded(.toNearestOrEven)
                guard (-128...127).contains(value) else { throw EQError.outOfRange }
                return Int(value)
            }
            try validate(steps)
            return steps
        }

        public func validate(_ steps: [Int]) throws {
            guard steps.count == 8 else { throw EQError.malformed }
            guard (0..<8).allSatisfy({ (minimumSteps[$0]...maximumSteps[$0]).contains(steps[$0]) }) else { throw EQError.outOfRange }
        }
    }

    /// The first eight bytes are tinnitus attenuation and must remain unchanged.
    public static func legacyStreamingState(_ data: Data) throws -> State {
        guard data.count == 16 else { throw EQError.unsupported }
        // The installed application's GATT path limits streaming EQ to -12...+6 dB.
        let minimum = Int((-12 / defaultStepDB).rounded(.toNearestOrEven)), maximum = Int((6 / defaultStepDB).rounded(.toNearestOrEven))
        return try State(rawSteps: data.dropFirst(8).map { Int(Int8(bitPattern: $0)) },
                         minimumSteps: .init(repeating: minimum, count: 8), maximumSteps: .init(repeating: maximum, count: 8),
                         stepDB: defaultStepDB, rangesReportedByDevice: false)
    }

    public static func legacyStreamingPayload(current: Data, steps: [Int]) throws -> Data {
        let state = try legacyStreamingState(current)
        try state.validate(steps)
        return Data(current.prefix(8)) + Data(steps.map { UInt8(bitPattern: Int8($0)) })
    }
}

public enum OticonProgramInfo {
    public static let selector = "68BFA64E-3209-4172-B117-F7EAFCE17414"
    public static let information = "BBA1C7F1-B445-4657-90C3-8DBD97361A0C"
    public static let version = "42E940EF-98C8-4CCD-A557-30425295AF89"

    public struct Program: Equatable, Sendable {
        public let id: Int
        public let label: String
        public let category: UInt8
        public let tinnitus: Bool
        public let boostable: Bool

        public init(data: Data, id: Int) throws {
            let bytes = Array(data)
            guard (0...254).contains(id), bytes.count >= 3, Int(bytes[1]) + 3 <= bytes.count,
                  let label = String(bytes: bytes[2..<(2 + Int(bytes[1]))], encoding: .utf8) else { throw OticonEqualizer.EQError.malformed }
            self.id = id; self.label = label; category = bytes[0]
            let flags = bytes[2 + Int(bytes[1])]
            tinnitus = flags & 1 != 0; boostable = flags & 2 != 0
        }
    }
}
