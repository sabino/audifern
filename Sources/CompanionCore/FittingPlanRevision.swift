import CryptoKit
import Foundation

/// Immutable local preparation history. A revision contains no prescription,
/// device transaction or authority to restore the hearing aids.
public struct FittingPlanRevision: Codable, Identifiable, Sendable {
    public enum Reason: String, Codable, Sendable {
        case savedPlan, beforeRestoring
        public var title: String {
            switch self {
            case .savedPlan: "Saved plan"
            case .beforeRestoring: "Draft before restoring"
            }
        }
    }
    public static let maximumBytes = FittingWorkspaceDraft.maximumFileBytes * 4 / 3 + 4096
    public let schemaVersion: Int
    public let scope: String
    public let id: UUID
    public let savedAt: Date
    public let reason: Reason
    public let sha256: String
    public let payload: Data

    public init(_ plan: FittingWorkspaceDraft, reason: Reason = .savedPlan,
                id: UUID = UUID(), savedAt: Date = Date()) throws {
        schemaVersion = 1; scope = "local-fitting-plan-revision"
        self.id = id; self.savedAt = savedAt; self.reason = reason
        payload = try plan.encoded(); sha256 = Self.digest(payload)
        _ = try verifiedPlan()
    }

    public func verifiedPlan() throws -> FittingWorkspaceDraft {
        guard schemaVersion == 1, scope == "local-fitting-plan-revision",
              savedAt.timeIntervalSince1970.isFinite,
              payload.count <= FittingWorkspaceDraft.maximumFileBytes else { throw RevisionError.invalid }
        guard sha256 == Self.digest(payload) else { throw RevisionError.digestMismatch }
        return try FittingWorkspaceDraft.decode(payload)
    }

    public func encoded() throws -> Data {
        _ = try verifiedPlan()
        // Keep fractional seconds so successive saves sort in their actual
        // order rather than falling back to UUID ordering within one second.
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw RevisionError.invalid }
        return data
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw RevisionError.invalid }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let revision = try decoder.decode(Self.self, from: data)
        _ = try revision.verifiedPlan()
        return revision
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public enum RevisionError: Error, Equatable { case invalid, digestMismatch }
}

/// A preparation comparison, deliberately independent of raw registers, gain
/// calculations and hearing-aid state. Save timestamps do not count as edits.
public struct FittingPlanComparison: Equatable, Sendable {
    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case plan, profile, patient, leftAcoustics, rightAcoustics, audiogram, rationale, adaptation, programs
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .plan: "Plan details"
            case .profile: "Model and ears"
            case .patient: "Patient details and goals"
            case .leftAcoustics: "Left acoustics"
            case .rightAcoustics: "Right acoustics"
            case .audiogram: "Linked audiogram"
            case .rationale: "Fitting rationale"
            case .adaptation: "Adaptation preference"
            case .programs: "Program ideas"
            }
        }
    }
    public let changedSections: [Section]
    public var isUnchanged: Bool { changedSections.isEmpty }

    public init(_ previous: FittingWorkspaceDraft, _ current: FittingWorkspaceDraft) {
        var sections: [Section] = []
        if previous.id != current.id || previous.name != current.name { sections.append(.plan) }
        if previous.model != current.model || previous.ears != current.ears { sections.append(.profile) }
        if previous.patientLabel != current.patientLabel || previous.birthDate != current.birthDate
            || previous.experience != current.experience || previous.listeningGoals != current.listeningGoals {
            sections.append(.patient)
        }
        if previous.leftAcoustics != current.leftAcoustics { sections.append(.leftAcoustics) }
        if previous.rightAcoustics != current.rightAcoustics { sections.append(.rightAcoustics) }
        if previous.audiogramID != current.audiogramID { sections.append(.audiogram) }
        if previous.rationale != current.rationale { sections.append(.rationale) }
        if previous.adaptation != current.adaptation { sections.append(.adaptation) }
        if previous.programs != current.programs { sections.append(.programs) }
        changedSections = sections
    }
}
