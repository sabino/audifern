import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Exam values are dB HL, not hearing-aid gain or sound-pressure output.
/// Chart conventions: https://www.asha.org/policy/GL1990-00006/
public enum AudiogramEar: String, CaseIterable, Codable, Sendable {
    case right, left

    public var label: String { rawValue.capitalized }
}

public enum AudiogramConduction: String, CaseIterable, Codable, Sendable {
    case air, bone

    public var label: String { "\(rawValue.capitalized) conduction" }
}

public struct AudiogramThresholdKey: Hashable, Codable, Sendable {
    public var ear: AudiogramEar
    public var conduction: AudiogramConduction
    public var frequencyHz: Int
    public var masked: Bool

    public init(ear: AudiogramEar, conduction: AudiogramConduction, frequencyHz: Int, masked: Bool = false) {
        self.ear = ear
        self.conduction = conduction
        self.frequencyHz = frequencyHz
        self.masked = masked
    }

    public var label: String {
        "\(ear.label), \(conduction.rawValue), \(frequencyHz) Hz\(masked ? ", masked" : "")"
    }
}

public struct AudiogramThreshold: Codable, Equatable, Sendable {
    public var key: AudiogramThresholdKey
    /// For `noResponse`, this is the presentation level, not a measured threshold.
    public var levelDBHL: Double
    public var noResponse: Bool

    public init(key: AudiogramThresholdKey, levelDBHL: Double, noResponse: Bool = false) {
        self.key = key
        self.levelDBHL = levelDBHL
        self.noResponse = noResponse
    }
}

public struct Audiogram: Identifiable, Codable, Equatable, Sendable {
    public static let frequenciesHz = [125, 250, 500, 1000, 2000, 3000, 4000, 6000, 8000]
    public static let levelRangeDBHL: ClosedRange<Double> = -20...130

    public var id: UUID
    public var name: String
    /// A date without a time zone, copied from the exam as YYYY-MM-DD. Nil means unknown.
    public var examDate: String?
    public var notes: String
    public var thresholds: [AudiogramThreshold]

    public init(id: UUID = UUID(), name: String = "New exam", examDate: String? = nil,
                notes: String = "", thresholds: [AudiogramThreshold] = []) {
        self.id = id
        self.name = name
        self.examDate = examDate
        self.notes = notes
        self.thresholds = thresholds
    }

    public func validated() throws -> Audiogram {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 160 else {
            throw AudiogramError.invalidName
        }
        guard notes.count <= 20_000 else { throw AudiogramError.notesTooLong }
        if let examDate, !Self.isValidExamDate(examDate) { throw AudiogramError.invalidExamDate }
        guard thresholds.count <= Self.frequenciesHz.count * 8 else { throw AudiogramError.tooManyThresholds }
        var keys = Set<AudiogramThresholdKey>()
        for threshold in thresholds {
            guard Self.frequenciesHz.contains(threshold.key.frequencyHz) else { throw AudiogramError.unsupportedFrequency }
            guard threshold.levelDBHL.isFinite, Self.levelRangeDBHL.contains(threshold.levelDBHL) else {
                throw AudiogramError.invalidLevel(threshold.key)
            }
            guard keys.insert(threshold.key).inserted else { throw AudiogramError.duplicateThreshold }
        }
        return self
    }

    /// Empty cells stay missing. Decimal commas are accepted; grouping separators are not.
    public static func parseLevel(_ text: String, for key: AudiogramThresholdKey) throws -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        let normalized = text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "−", with: "-")
        guard normalized.count <= 32,
              normalized.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
              let value = Double(normalized), value.isFinite, levelRangeDBHL.contains(value) else {
            throw AudiogramError.invalidLevel(key)
        }
        return value
    }

    public static func isValidExamDate(_ text: String) -> Bool {
        guard text.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else { return false }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...9999).contains(parts[0]) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return false }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        return actual.year == parts[0] && actual.month == parts[1] && actual.day == parts[2]
    }

    /// Normalized chart coordinates, including the exact logarithmic position of interoctave frequencies.
    public static func chartPosition(frequencyHz: Int, levelDBHL: Double) -> (x: Double, y: Double)? {
        guard frequenciesHz.contains(frequencyHz), levelDBHL.isFinite, levelRangeDBHL.contains(levelDBHL) else { return nil }
        return (log2(Double(frequencyHz) / 125) / 6,
                (levelDBHL - levelRangeDBHL.lowerBound) / (levelRangeDBHL.upperBound - levelRangeDBHL.lowerBound))
    }
}

public struct AudiogramDraft: Equatable, Sendable {
    public struct Cell: Equatable, Sendable {
        public var text: String
        public var noResponse: Bool

        public init(text: String = "", noResponse: Bool = false) { self.text = text; self.noResponse = noResponse }
    }

    public var id: UUID
    public var name: String
    public var examDate: String
    public var notes: String
    public var cells: [AudiogramThresholdKey: Cell]

    public init(_ exam: Audiogram = Audiogram()) {
        id = exam.id; name = exam.name; examDate = exam.examDate ?? ""; notes = exam.notes
        cells = [:]
        for threshold in exam.thresholds {
            cells[threshold.key] = Cell(text: Self.levelText(threshold.levelDBHL), noResponse: threshold.noResponse)
        }
    }

    public func validated() throws -> Audiogram {
        var thresholds: [AudiogramThreshold] = []
        for (key, cell) in cells {
            if let value = try Audiogram.parseLevel(cell.text, for: key) {
                thresholds.append(AudiogramThreshold(key: key, levelDBHL: value, noResponse: cell.noResponse))
            } else if cell.noResponse {
                throw AudiogramError.missingNoResponseLevel(key)
            }
        }
        thresholds.sort {
            if $0.key.ear != $1.key.ear { return $0.key.ear.rawValue < $1.key.ear.rawValue }
            if $0.key.conduction != $1.key.conduction { return $0.key.conduction.rawValue < $1.key.conduction.rawValue }
            if $0.key.masked != $1.key.masked { return !$0.key.masked }
            return $0.key.frequencyHz < $1.key.frequencyHz
        }
        let date = examDate.trimmingCharacters(in: .whitespacesAndNewlines)
        return try Audiogram(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            examDate: date.isEmpty ? nil : date, notes: notes, thresholds: thresholds).validated()
    }

    public static func levelText(_ level: Double) -> String {
        level.rounded() == level ? String(format: "%.0f", level) : String(level)
    }
}

public struct AudiogramLibrary: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var exams: [Audiogram]

    public init(exams: [Audiogram] = []) { schemaVersion = 1; self.exams = exams }

    public func validated() throws -> AudiogramLibrary {
        guard schemaVersion == 1 else { throw AudiogramError.unsupportedSchema }
        guard exams.count <= 500 else { throw AudiogramError.tooManyExams }
        var ids = Set<UUID>()
        for exam in exams {
            _ = try exam.validated()
            guard ids.insert(exam.id).inserted else { throw AudiogramError.duplicateExam }
        }
        return self
    }

    public func encoded() throws -> Data {
        _ = try validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= AudiogramRepository.maximumFileBytes else { throw AudiogramError.fileTooLarge }
        return data
    }

    public static func decode(_ data: Data) throws -> AudiogramLibrary {
        guard data.count <= AudiogramRepository.maximumFileBytes else { throw AudiogramError.fileTooLarge }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }
}

public enum AudiogramError: Error, LocalizedError, Equatable {
    case invalidName, notesTooLong, invalidExamDate, unsupportedFrequency, duplicateThreshold
    case invalidLevel(AudiogramThresholdKey), missingNoResponseLevel(AudiogramThresholdKey)
    case tooManyThresholds, unsupportedSchema, duplicateExam, tooManyExams, fileTooLarge
    case insecurePath, writeFailed

    public var errorDescription: String? {
        switch self {
        case .invalidName: "Enter an exam name of 1–160 characters."
        case .notesTooLong: "Notes can contain up to 20,000 characters."
        case .invalidExamDate: "Use a real exam date in YYYY-MM-DD format, or leave it blank."
        case .unsupportedFrequency: "This exam contains a frequency outside the supported 125–8000 Hz table."
        case .duplicateThreshold: "This exam contains duplicate measurements for the same ear, frequency and test condition."
        case .invalidLevel(let key): "\(key.label): enter a number from −20 to 130 dB HL, or leave it blank."
        case .missingNoResponseLevel(let key): "\(key.label): NR needs the presentation level printed on the exam."
        case .tooManyThresholds: "This exam contains too many measurements."
        case .unsupportedSchema: "This audiogram file uses an unsupported format version."
        case .duplicateExam: "This file contains duplicate exam identifiers."
        case .tooManyExams: "This file contains more than 500 exams."
        case .fileTooLarge: "This audiogram file is too large (maximum 4 MB)."
        case .insecurePath: "The audiogram path is not a regular local file."
        case .writeFailed: "The audiogram file could not be saved. Your previous saved file was left unchanged."
        }
    }
}

/// Local exam storage only. No account, device identifier, network, prescription or BLE dependency.
public struct AudiogramRepository: Sendable {
    public static let maximumFileBytes = 4 * 1024 * 1024
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public static func applicationSupport() throws -> AudiogramRepository {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return AudiogramRepository(fileURL: root.appendingPathComponent("Open Companion", isDirectory: true)
            .appendingPathComponent("audiograms.json"))
    }

    public func load() throws -> AudiogramLibrary {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return AudiogramLibrary() }
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw AudiogramError.insecurePath }
        guard (values.fileSize ?? 0) <= Self.maximumFileBytes else { throw AudiogramError.fileTooLarge }
        return try AudiogramLibrary.decode(Data(contentsOf: fileURL))
    }

    public func save(_ library: AudiogramLibrary) throws {
        let data = try library.encoded()
        let directory = fileURL.deletingLastPathComponent()
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let directoryValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else { throw AudiogramError.insecurePath }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        if manager.fileExists(atPath: fileURL.path) {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw AudiogramError.insecurePath }
        }
        // Create private from the first byte; atomic Data.write can otherwise inherit the process umask.
        let temporary = directory.appendingPathComponent(".audiograms-\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw AudiogramError.writeFailed }
        var descriptorOpen = true
        defer {
            if descriptorOpen { close(descriptor) }
            try? manager.removeItem(at: temporary)
        }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                guard let base = buffer.baseAddress else { throw AudiogramError.writeFailed }
                let count = write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw AudiogramError.writeFailed }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw AudiogramError.writeFailed }
        let closeResult = close(descriptor)
        descriptorOpen = false
        guard closeResult == 0, rename(temporary.path, fileURL.path) == 0 else { throw AudiogramError.writeFailed }
    }
}
