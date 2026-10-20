import Foundation

/// A read-only export of consumer controls. This is not a clinical fitting,
/// a complete DSP backup, or an additional fitted program in the hearing aid.
public struct ConsumerProgramSnapshot: Codable, Equatable, Sendable {
    public enum Side: String, Codable, Sendable { case left, right }
    public enum SnapshotError: Error, LocalizedError, Equatable {
        case invalid
        public var errorDescription: String? { "The consumer program snapshot is invalid or unsupported." }
    }

    public struct Program: Codable, Equatable, Sendable {
        public let programID: Int
        public let name: String
        public let category: UInt32
        public let boostable: Bool
        public let tinnitus: Bool
        public let mic: Bool?

        public init(programID: Int, name: String, category: UInt32, boostable: Bool, tinnitus: Bool, mic: Bool? = nil) throws {
            self.programID = programID; self.name = name; self.category = category
            self.boostable = boostable; self.tinnitus = tinnitus; self.mic = mic
            try validate()
        }
        fileprivate func validate() throws {
            guard (0...255).contains(programID), ConsumerProgramSnapshot.validText(name, maximumBytes: 256) else {
                throw SnapshotError.invalid
            }
        }
    }

    public struct Volume: Codable, Equatable, Sendable {
        public struct Range: Codable, Equatable, Sendable {
            public let minimum: Int
            public let maximum: Int
        }
        public let level: Int
        public let muted: Bool
        public let range: Range?

        public init(level: Int, muted: Bool, range: ClosedRange<Int>? = nil) throws {
            self.level = level; self.muted = muted
            self.range = range.map { Range(minimum: $0.lowerBound, maximum: $0.upperBound) }
            try validate()
        }
        fileprivate func validate() throws {
            guard (-128...127).contains(level) else { throw SnapshotError.invalid }
            if let range {
                guard (-128...127).contains(range.minimum), (-128...127).contains(range.maximum),
                      range.minimum <= range.maximum, level >= range.minimum, level <= range.maximum else {
                    throw SnapshotError.invalid
                }
            }
        }
    }

    public struct Equalizer: Codable, Equatable, Sendable {
        public let rawSteps: [Int]
        public let stepDB: Double
        public let minimumSteps: [Int]
        public let maximumSteps: [Int]
        public let rangesReportedByDevice: Bool

        public init(state: OticonEqualizer.State) {
            rawSteps = state.rawSteps; stepDB = state.stepDB
            minimumSteps = state.minimumSteps; maximumSteps = state.maximumSteps
            rangesReportedByDevice = state.rangesReportedByDevice
        }
        fileprivate func validate() throws {
            do {
                _ = try OticonEqualizer.State(rawSteps: rawSteps, minimumSteps: minimumSteps,
                                             maximumSteps: maximumSteps, stepDB: stepDB,
                                             rangesReportedByDevice: rangesReportedByDevice)
            } catch { throw SnapshotError.invalid }
        }
    }

    public struct Aid: Codable, Equatable, Sendable {
        public let side: Side
        public let model: String?
        public let program: Program
        public let volume: Volume?
        public let streamingVolume: Volume?
        public let tinnitusVolume: Volume?
        public let microphoneEqualizer: Equalizer?
        public let streamingEqualizer: Equalizer?
        public let speechBoosterEnabled: Bool?

        public init(side: Side, model: String? = nil, program: Program, volume: Volume? = nil,
                    streamingVolume: Volume? = nil, tinnitusVolume: Volume? = nil,
                    microphoneEqualizer: Equalizer? = nil, streamingEqualizer: Equalizer? = nil,
                    speechBoosterEnabled: Bool? = nil) throws {
            self.side = side; self.model = model; self.program = program; self.volume = volume
            self.streamingVolume = streamingVolume; self.tinnitusVolume = tinnitusVolume
            self.microphoneEqualizer = microphoneEqualizer; self.streamingEqualizer = streamingEqualizer
            self.speechBoosterEnabled = speechBoosterEnabled
            try validate()
        }
        fileprivate func validate() throws {
            if let model, !ConsumerProgramSnapshot.validText(model, maximumBytes: 120) { throw SnapshotError.invalid }
            try program.validate()
            for value in [volume, streamingVolume, tinnitusVolume].compactMap({ $0 }) { try value.validate() }
            for value in [microphoneEqualizer, streamingEqualizer].compactMap({ $0 }) { try value.validate() }
        }
    }

    public let schemaVersion: Int
    public let scope: String
    public let clinicalFittingIncluded: Bool
    public let capturedAt: Date
    public let aids: [Aid]

    public init(capturedAt: Date = Date(), aids: [Aid]) throws {
        schemaVersion = 1; scope = "consumer-controls"; clinicalFittingIncluded = false
        self.capturedAt = capturedAt; self.aids = aids
        try validate()
    }

    public func validate() throws {
        guard schemaVersion == 1, scope == "consumer-controls", !clinicalFittingIncluded,
              capturedAt.timeIntervalSince1970.isFinite, (1...2).contains(aids.count),
              Set(aids.map(\.side)).count == aids.count else { throw SnapshotError.invalid }
        for aid in aids { try aid.validate() }
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 65_535 else { throw SnapshotError.invalid }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(Self.self, from: data)
        try result.validate()
        return result
    }

    private static func validText(_ text: String, maximumBytes: Int) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= maximumBytes
            && !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

/// Companion's ordinary consumer ProgramControl getters, not fitting APIs.
public enum OticonConsumerPrograms {
    public static let serviceID: UInt32 = 0x0200000E
    public static let activeProgramOpcode: UInt8 = 0
    public static let programInformationOpcode: UInt8 = 2
    public enum DecodeError: Error, Equatable { case malformed, unsupported }

    public static func supports(_ service: UTLProtocol.Service) -> Bool {
        service.isAvailable && service.id == serviceID && service.major == 2 && service.minor <= 1
    }

    public static func activeProgram(_ payload: Data, service: UTLProtocol.Service) throws -> Int {
        guard supports(service) else { throw DecodeError.unsupported }
        guard payload.count == 1, let value = payload.first else { throw DecodeError.malformed }
        return Int(value)
    }

    public static func programInformation(_ payload: Data, service: UTLProtocol.Service) throws -> [ConsumerProgramSnapshot.Program] {
        guard supports(service) else { throw DecodeError.unsupported }
        guard !payload.isEmpty, payload.count <= 65_535 else { throw DecodeError.malformed }
        var reader = Reader(bytes: Array(payload))
        let root = try reader.header()
        guard root.major == 5, (1...32).contains(root.argument) else { throw DecodeError.malformed }
        var rootKeys = Set<String>(), programs: [ConsumerProgramSnapshot.Program] = []
        for position in 0..<Int(root.argument) {
            guard rootKeys.insert(try reader.text(maximumBytes: 128)).inserted else { throw DecodeError.malformed }
            // The shipped wrapper uses the first root-map value. Preserve wire
            // order here instead of relying on Swift Dictionary iteration order.
            if position == 0 { programs = try reader.programs() }
            else { try reader.skip(depth: 0) }
        }
        guard reader.index == reader.bytes.count else { throw DecodeError.malformed }
        return programs
    }

    private struct Reader {
        let bytes: [UInt8]
        var index = 0
        var items = 0

        mutating func byte() throws -> UInt8 {
            guard index < bytes.count else { throw DecodeError.malformed }
            defer { index += 1 }; return bytes[index]
        }
        mutating func header() throws -> (major: UInt8, info: UInt8, argument: UInt64) {
            items += 1
            guard items <= 8192 else { throw DecodeError.malformed }
            let initial = try byte(), info = initial & 31
            let count: Int
            switch info {
            case 0...23: return (initial >> 5, info, UInt64(info))
            case 24: count = 1
            case 25: count = 2
            case 26: count = 4
            case 27: count = 8
            default: throw DecodeError.malformed
            }
            var argument: UInt64 = 0
            for _ in 0..<count { argument = argument << 8 | UInt64(try byte()) }
            return (initial >> 5, info, argument)
        }
        mutating func text(maximumBytes: Int) throws -> String {
            let value = try header()
            guard value.major == 3, value.argument <= UInt64(maximumBytes),
                  value.argument <= UInt64(bytes.count - index) else { throw DecodeError.malformed }
            let end = index + Int(value.argument)
            guard let result = String(bytes: bytes[index..<end], encoding: .utf8) else { throw DecodeError.malformed }
            index = end
            return result
        }
        mutating func unsigned(maximum: UInt64) throws -> UInt64 {
            let value = try header()
            guard value.major == 0, value.argument <= maximum else { throw DecodeError.malformed }
            return value.argument
        }
        mutating func boolean() throws -> Bool {
            let value = try header()
            guard value.major == 7, value.info == 20 || value.info == 21 else { throw DecodeError.malformed }
            return value.info == 21
        }
        mutating func programs() throws -> [ConsumerProgramSnapshot.Program] {
            let array = try header()
            guard array.major == 4, array.argument <= 256 else { throw DecodeError.malformed }
            var result: [ConsumerProgramSnapshot.Program] = [], ids = Set<Int>()
            for _ in 0..<Int(array.argument) {
                let map = try header()
                guard map.major == 5, (5...32).contains(map.argument) else { throw DecodeError.malformed }
                var keys = Set<String>(), id: Int?, name: String?, category: UInt32?, boostable: Bool?, tinnitus: Bool?, mic: Bool?
                for _ in 0..<Int(map.argument) {
                    let key = try text(maximumBytes: 64)
                    guard keys.insert(key).inserted else { throw DecodeError.malformed }
                    switch key {
                    case "program_id": id = Int(try unsigned(maximum: 255))
                    case "name": name = try text(maximumBytes: 256)
                    case "category": category = UInt32(try unsigned(maximum: UInt64(UInt32.max)))
                    case "boostable": boostable = try boolean()
                    case "tinnitus": tinnitus = try boolean()
                    case "mic": mic = try boolean()
                    default: try skip(depth: 0)
                    }
                }
                guard let id, ids.insert(id).inserted, let name, let category, let boostable, let tinnitus else {
                    throw DecodeError.malformed
                }
                do { result.append(try .init(programID: id, name: name, category: category, boostable: boostable, tinnitus: tinnitus, mic: mic)) }
                catch { throw DecodeError.malformed }
            }
            return result
        }
        /// Ignore unknown fields without retaining raw values, fitting blobs,
        /// identifiers or credentials in the resulting consumer snapshot.
        mutating func skip(depth: Int) throws {
            guard depth <= 12 else { throw DecodeError.malformed }
            let value = try header()
            switch value.major {
            case 0, 1: break
            case 2, 3:
                guard value.argument <= UInt64(bytes.count - index) else { throw DecodeError.malformed }
                index += Int(value.argument)
            case 4, 5:
                guard value.argument <= 256 else { throw DecodeError.malformed }
                for _ in 0..<(Int(value.argument) * (value.major == 5 ? 2 : 1)) { try skip(depth: depth + 1) }
            case 7:
                guard [20, 21, 22, 23, 25, 26, 27].contains(value.info) else { throw DecodeError.malformed }
            default: throw DecodeError.malformed
            }
        }
    }
}
