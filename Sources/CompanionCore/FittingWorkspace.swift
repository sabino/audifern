import Foundation

/// Local preparation records. This model has no gain calculator, transport,
/// device-write payload, authentication data, or clinical restore operation.
public enum FittingWorkspaceModel: String, Codable, CaseIterable, Identifiable, Sendable {
    case notSelected, intent3, otherOticon
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .notSelected: "Choose a hearing-aid model"
        case .intent3: "Oticon Intent 3"
        case .otherOticon: "Another Oticon model"
        }
    }

    /// Independently described planning choices for the researched model.
    /// Availability of a rationale is not execution or device compatibility.
    public var rationales: [FittingWorkspaceRationale] {
        self == .intent3 ? [.vacPlus, .nalNL1, .nalNL2, .dslAdult, .dslPediatric] : []
    }
}

public enum FittingWorkspaceRationale: String, Codable, CaseIterable, Identifiable, Sendable {
    case vacPlus, nalNL1, nalNL2, dslAdult, dslPediatric
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .vacPlus: "VAC+"
        case .nalNL1: "NAL-NL1"
        case .nalNL2: "NAL-NL2"
        case .dslAdult: "DSL v5 · Adult"
        case .dslPediatric: "DSL v5 · Pediatric"
        }
    }
}

public enum FittingWorkspaceEars: String, Codable, CaseIterable, Identifiable, Sendable {
    case both, left, right
    public var id: String { rawValue }
    public var title: String {
        switch self { case .both: "Both ears"; case .left: "Left ear"; case .right: "Right ear" }
    }
    public var ears: [AudiogramEar] {
        switch self { case .both: [.left, .right]; case .left: [.left]; case .right: [.right] }
    }
}

public enum FittingWorkspaceExperience: String, Codable, CaseIterable, Identifiable, Sendable {
    case notRecorded, firstTime, experienced
    public var id: String { rawValue }
    public var title: String {
        switch self { case .notRecorded: "Not recorded"; case .firstTime: "First hearing aids"; case .experienced: "Experienced wearer" }
    }
}

public enum FittingWorkspaceCoupling: String, Codable, CaseIterable, Identifiable, Sendable {
    case notRecorded, openDome, ventedDome, powerDome, customMold
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .notRecorded: "Not recorded"
        case .openDome: "Open dome"
        case .ventedDome: "Vented dome"
        case .powerDome: "Power dome"
        case .customMold: "Custom earmold"
        }
    }
}

public struct FittingWorkspaceAcoustics: Codable, Equatable, Sendable {
    public var receiver: String
    public var coupling: FittingWorkspaceCoupling
    public var ventDescription: String
    /// A user's local checklist entry, never reported as a device measurement.
    public var checkedAgainstRecord: Bool

    public init(receiver: String = "", coupling: FittingWorkspaceCoupling = .notRecorded,
                ventDescription: String = "", checkedAgainstRecord: Bool = false) {
        self.receiver = receiver; self.coupling = coupling
        self.ventDescription = ventDescription; self.checkedAgainstRecord = checkedAgainstRecord
    }
    public var isRecorded: Bool {
        !receiver.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && coupling != .notRecorded && checkedAgainstRecord
    }
}

public enum FittingWorkspaceAdaptation: String, Codable, CaseIterable, Identifiable, Sendable {
    case notSelected, step1, step2, step3
    public var id: String { rawValue }
    public var title: String {
        switch self { case .notSelected: "Review together"; case .step1: "Step 1"; case .step2: "Step 2"; case .step3: "Step 3" }
    }
}

public enum FittingProgramPurpose: String, Codable, CaseIterable, Identifiable, Sendable {
    case everyday, conversation, music, comfort, custom
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .everyday: "Everyday listening"
        case .conversation: "Conversation in noise"
        case .music: "Music"
        case .comfort: "Listening comfort"
        case .custom: "Another situation"
        }
    }
    public var symbol: String {
        switch self {
        case .everyday: "sun.max"
        case .conversation: "person.2.wave.2"
        case .music: "music.note"
        case .comfort: "leaf"
        case .custom: "sparkles"
        }
    }
}

public struct FittingProgramPlan: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var purpose: FittingProgramPurpose
    public var notes: String

    public init(id: UUID = UUID(), name: String = "Everyday", purpose: FittingProgramPurpose = .everyday, notes: String = "") {
        self.id = id; self.name = name; self.purpose = purpose; self.notes = notes
    }
}

public struct FittingWorkspaceDraft: Codable, Equatable, Identifiable, Sendable {
    public static let maximumFileBytes = 256 * 1024
    /// An editor bound, not a claim about hearing-aid program capacity.
    public static let maximumProgramIdeas = 12
    public let schemaVersion: Int
    public let scope: String
    public let clinicalFittingIncluded: Bool
    public var id: UUID
    public var name: String
    public var updatedAt: Date
    public var model: FittingWorkspaceModel
    public var ears: FittingWorkspaceEars
    public var patientLabel: String
    /// Optional date copied from an existing record. Empty remains unknown.
    public var birthDate: String
    public var experience: FittingWorkspaceExperience
    public var listeningGoals: String
    public var leftAcoustics: FittingWorkspaceAcoustics
    public var rightAcoustics: FittingWorkspaceAcoustics
    public var audiogramID: UUID?
    public var rationale: FittingWorkspaceRationale?
    public var adaptation: FittingWorkspaceAdaptation
    public var programs: [FittingProgramPlan]

    public init(id: UUID = UUID(), name: String = "My fitting plan", updatedAt: Date = Date(),
                model: FittingWorkspaceModel = .notSelected, ears: FittingWorkspaceEars = .both,
                patientLabel: String = "", birthDate: String = "", experience: FittingWorkspaceExperience = .notRecorded,
                listeningGoals: String = "", leftAcoustics: FittingWorkspaceAcoustics = .init(),
                rightAcoustics: FittingWorkspaceAcoustics = .init(), audiogramID: UUID? = nil,
                rationale: FittingWorkspaceRationale? = nil, adaptation: FittingWorkspaceAdaptation = .notSelected,
                programs: [FittingProgramPlan] = []) {
        schemaVersion = 1; scope = "local-fitting-plan"; clinicalFittingIncluded = false
        self.id = id; self.name = name; self.updatedAt = updatedAt; self.model = model; self.ears = ears
        self.patientLabel = patientLabel; self.birthDate = birthDate; self.experience = experience
        self.listeningGoals = listeningGoals; self.leftAcoustics = leftAcoustics; self.rightAcoustics = rightAcoustics
        self.audiogramID = audiogramID; self.rationale = rationale; self.adaptation = adaptation; self.programs = programs
    }

    public func acoustics(for ear: AudiogramEar) -> FittingWorkspaceAcoustics {
        ear == .left ? leftAcoustics : rightAcoustics
    }

    public var capabilities: FittingWorkspaceCapabilities { .init(model: model) }

    public func validated() throws -> Self {
        guard schemaVersion == 1, scope == "local-fitting-plan", !clinicalFittingIncluded else { throw ValidationError.unsupportedFormat }
        guard validText(name, maximum: 160, required: true), validText(patientLabel, maximum: 160),
              validText(listeningGoals, maximum: 8_000, multiline: true), updatedAt.timeIntervalSince1970.isFinite else {
            throw ValidationError.invalidDetails
        }
        let date = birthDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validText(birthDate, maximum: 32), date.isEmpty || Audiogram.isValidExamDate(date) else { throw ValidationError.invalidBirthDate }
        for acoustics in [leftAcoustics, rightAcoustics] {
            guard validText(acoustics.receiver, maximum: 120), validText(acoustics.ventDescription, maximum: 160) else {
                throw ValidationError.invalidAcoustics
            }
        }
        if let rationale, !capabilities.rationales.contains(rationale) { throw ValidationError.unsupportedRationale }
        guard programs.count <= Self.maximumProgramIdeas, Set(programs.map(\.id)).count == programs.count else {
            throw ValidationError.invalidPrograms
        }
        for program in programs {
            guard validText(program.name, maximum: 100, required: true), validText(program.notes, maximum: 4_000, multiline: true) else {
                throw ValidationError.invalidPrograms
            }
        }
        return self
    }

    /// Readiness describes preparation only. No point count or checklist entry
    /// confers clinical validity, generated gains, or permission to program.
    public func readiness(audiograms: [Audiogram]) -> FittingWorkspaceReadiness {
        let exam = audiogramID.flatMap { id in audiograms.first { $0.id == id } }
        let examIsUsable = exam.flatMap { try? $0.validated() }.map { exam in
            ears.ears.allSatisfy { ear in
                exam.thresholds.contains { $0.key.ear == ear && $0.key.conduction == .air && !$0.noResponse }
            }
        } ?? false
        return .init(steps: [
            .init(id: .model, completed: model == .intent3),
            .init(id: .patient, completed: !patientLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && experience != .notRecorded),
            .init(id: .acoustics, completed: ears.ears.allSatisfy { acoustics(for: $0).isRecorded }),
            .init(id: .audiogram, completed: examIsUsable),
            .init(id: .rationale, completed: rationale.map { capabilities.rationales.contains($0) } ?? false),
            .init(id: .programs, completed: !programs.isEmpty && programs.count <= Self.maximumProgramIdeas
                && Set(programs.map(\.id)).count == programs.count
                && programs.allSatisfy { validText($0.name, maximum: 100, required: true) && validText($0.notes, maximum: 4_000, multiline: true) })
        ], draftIsValid: (try? validated()) != nil)
    }

    public func encoded() throws -> Data {
        _ = try validated()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumFileBytes else { throw ValidationError.fileTooLarge }
        return data
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumFileBytes else { throw ValidationError.fileTooLarge }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: data).validated()
    }

    private func validText(_ value: String, maximum: Int, required: Bool = false, multiline: Bool = false) -> Bool {
        guard value.count <= maximum, !required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !value.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar) && !(multiline && [10, 13, 9].contains(scalar.value))
        }
    }

    public enum ValidationError: Error, LocalizedError, Equatable {
        case unsupportedFormat, invalidDetails, invalidBirthDate, invalidAcoustics, unsupportedRationale, invalidPrograms, fileTooLarge
        public var errorDescription: String? {
            switch self {
            case .unsupportedFormat: "This file is not a supported local fitting plan."
            case .invalidDetails: "Give the plan a name and keep the entered details within their text limits."
            case .invalidBirthDate: "Use a real birth date in YYYY-MM-DD format, or leave it blank."
            case .invalidAcoustics: "Receiver and acoustic descriptions must be short, single-line text."
            case .unsupportedRationale: "Choose a rationale supported by the selected planning profile."
            case .invalidPrograms: "Program ideas need unique identifiers and names of 1–100 characters, with at most 12 ideas."
            case .fileTooLarge: "This fitting-plan file is too large (maximum 256 KB)."
            }
        }
    }
}

public struct FittingWorkspaceCapabilities: Equatable, Sendable {
    public let model: FittingWorkspaceModel
    public init(model: FittingWorkspaceModel) { self.model = model }
    public var rationales: [FittingWorkspaceRationale] { model.rationales }
    public var canGenerateClinicalGains: Bool { false }
    public var canWriteFittedPrograms: Bool { false }
    public var canRestoreClinicalFitting: Bool { false }
}

public struct FittingWorkspaceReadiness: Equatable, Sendable {
    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case model, patient, acoustics, audiogram, rationale, programs
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .model: "Model profile"
            case .patient: "Patient and goals"
            case .acoustics: "Receiver and acoustics"
            case .audiogram: "Linked audiogram"
            case .rationale: "Fitting rationale"
            case .programs: "Program ideas"
            }
        }
    }
    public struct Step: Equatable, Identifiable, Sendable {
        public let id: Section
        public let completed: Bool
    }
    public let steps: [Step]
    public let draftIsValid: Bool
    public var completedCount: Int { steps.filter(\.completed).count }
    public var preparationComplete: Bool { draftIsValid && steps.allSatisfy(\.completed) }
    public var canProgramHearingAids: Bool { false }
}
