import Foundation

/// A local snapshot of consumer controls, not a clinical fitting or an extra
/// program slot in a hearing aid. An audiogram reference is metadata only.
public struct SoundPreset: Codable, Equatable, Identifiable, Sendable {
    public enum Side: String, Codable, CaseIterable, Sendable { case left, right }
    public enum ValidationError: Error, LocalizedError, Equatable {
        case invalid(String)
        public var errorDescription: String? {
            if case let .invalid(message) = self { return message }
            return nil
        }
    }

    public struct Aid: Codable, Equatable, Sendable {
        public var side: Side
        public var model: String
        public var programID: Int
        public var volume: Int
        public var muted: Bool
        public var microphoneSteps: [Int]?
        public var streamingSteps: [Int]?
        public var microphoneStepDB: Double?
        public var streamingStepDB: Double?

        public init(side: Side, model: String, programID: Int, volume: Int, muted: Bool,
                    microphoneSteps: [Int]? = nil, streamingSteps: [Int]? = nil,
                    microphoneStepDB: Double? = nil, streamingStepDB: Double? = nil) throws {
            self.side = side; self.model = model; self.programID = programID
            self.volume = volume; self.muted = muted
            self.microphoneSteps = microphoneSteps; self.streamingSteps = streamingSteps
            self.microphoneStepDB = microphoneStepDB; self.streamingStepDB = streamingStepDB
            try validate()
        }

        public func validate() throws {
            guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, model.count <= 120,
                  (0...255).contains(programID), (-128...127).contains(volume) else {
                throw ValidationError.invalid("The saved hearing-aid settings are invalid.")
            }
            for vector in [microphoneSteps, streamingSteps].compactMap({ $0 }) {
                guard vector.count == 8, vector.allSatisfy({ (-128...127).contains($0) }) else {
                    throw ValidationError.invalid("An equalizer must contain eight signed gain steps.")
                }
            }
            for (vector, step) in [(microphoneSteps, microphoneStepDB), (streamingSteps, streamingStepDB)] {
                if vector != nil {
                    guard let step, step.isFinite, step > 0, step <= 12 else {
                        throw ValidationError.invalid("The equalizer step size is missing or invalid.")
                    }
                }
            }
        }
    }

    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var audiogramID: UUID?
    public var aids: [Aid]

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), updatedAt: Date = Date(),
                audiogramID: UUID? = nil, aids: [Aid]) throws {
        self.id = id; self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.audiogramID = audiogramID; self.aids = aids
        try validate()
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
              (1...2).contains(aids.count), Set(aids.map(\.side)).count == aids.count,
              createdAt.timeIntervalSince1970.isFinite, updatedAt.timeIntervalSince1970.isFinite else {
            throw ValidationError.invalid("A preset needs a name and one unique entry per hearing-aid side.")
        }
        for aid in aids { try aid.validate() }
    }
}

public struct SoundPresetArchive: Codable, Equatable, Sendable {
    public let version: Int
    public var presets: [SoundPreset]

    public init(presets: [SoundPreset]) throws {
        self.version = 1; self.presets = presets
        try validate()
    }

    public func validate() throws {
        guard version == 1, presets.count <= 100, Set(presets.map(\.id)).count == presets.count else {
            throw SoundPreset.ValidationError.invalid("This preset library is unsupported or contains duplicate records.")
        }
        for preset in presets { try preset.validate() }
    }

    public static func decode(_ data: Data) throws -> SoundPresetArchive {
        guard data.count <= 1_048_576 else {
            throw SoundPreset.ValidationError.invalid("The preset library is too large.")
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(Self.self, from: data)
        try archive.validate()
        return archive
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
