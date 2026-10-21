import Foundation

/// A deliberately narrow, shareable projection of one immutable backup. It
/// never retains the archive, device identifiers, custom names, clinical curves,
/// parameter matrices, raw records or free-form acquisition notes.
public struct SavedFittingReport: Codable, Equatable, Sendable {
    public enum Capture: String, Codable, Sendable {
        case completed, partial, consumerCheckpoint, unspecified
    }

    public enum FittingStatus: String, Codable, Sendable {
        case decoded, notCaptured, unsupported, unreadable
    }

    public struct EndUserCoverage: Codable, Equatable, Sendable {
        public let capturedCount: Int
        public let advertisedCount: Int?
        public let advertisedInventoryComplete: Bool
    }

    public struct Adaptation: Codable, Equatable, Sendable {
        public enum Mode: String, Codable, Sendable { case manual, automatic, paused }
        public let mode: Mode
        public let currentStep: Double
        public let startStep: Int
        public let endStep: Int
    }

    /// Only names recognized by the existing version-gated acoustic reader.
    /// Nil means an unrecognized saved category, not a missing physical part.
    public struct Acoustics: Codable, Equatable, Sendable {
        public let earpiece: String?
        public let vent: String?
        public let fittingLevel: String?
    }

    public struct Program: Codable, Equatable, Sendable {
        /// Zero-based fitted user slot. Custom labels are intentionally omitted.
        public let slot: Int
        public let noiseManagementEnabled: Bool?
        public let feedbackManagementEnabled: Bool?
        public let frequencyLoweringEnabled: Bool?
        public let transientControl: String?
        public let windControl: String?
    }

    public struct Metadata: Codable, Equatable, Sendable {
        public let fittingSoftwareVersion: String
        public let isPrerelease: Bool
        /// Saved setup positions, not a rationale-to-user-program assignment.
        /// Nil preserves an unknown rationale without including its raw code.
        public let rationales: [String?]
    }

    public struct Ear: Codable, Equatable, Sendable {
        public let side: ConsumerProgramSnapshot.Side
        public let isCaptured: Bool
        /// Model/version metadata only; never the advertised/custom device name.
        public let model: String?
        public let firmwareVersion: String?
        public let softwareVersion: String?
        public let fittingStatus: FittingStatus
        public let endUserCoverage: EndUserCoverage?
        public let adaptation: Adaptation?
        public let acoustics: Acoustics?
        public let programs: [Program]
        public let metadata: Metadata?
    }

    public let capturedAt: Date
    public let capture: Capture
    /// Always left then right. An absent ear is explicit, never copied from its
    /// partner or filled with the currently connected hearing aid's state.
    public let ears: [Ear]
    public var capturedEarCount: Int { ears.filter(\.isCaptured).count }

    public init(backup: DeviceBackup) throws {
        try backup.validate()
        capturedAt = backup.capturedAt
        switch backup.acquisitionStage {
        case .readCompleted: capture = .completed
        case .partialRead: capture = .partial
        case .consumerCheckpoint: capture = .consumerCheckpoint
        case nil: capture = .unspecified
        }
        ears = [ConsumerProgramSnapshot.Side.left, .right].map { side in
            guard let aid = backup.aids.first(where: { $0.side == side }) else {
                return Ear(side: side, isCaptured: false, model: nil, firmwareVersion: nil,
                    softwareVersion: nil, fittingStatus: .notCaptured, endUserCoverage: nil,
                    adaptation: nil, acoustics: nil, programs: [], metadata: nil)
            }
            let coverage = aid.endUserSettings.map { settings in
                EndUserCoverage(capturedCount: settings.records.count,
                    advertisedCount: (try? OticonEndUserSettings.decodeInventory(settings.inventory))?.reads.count,
                    advertisedInventoryComplete: settings.isComplete)
            }
            let status: FittingStatus
            var adaptation: Adaptation?
            var acoustics: Acoustics?
            var programs: [Program] = []
            if !aid.records.contains(where: { $0.key == OticonFittingRead.recordKey }) {
                status = .notCaptured
            } else if !SavedFitting.supports(aid) {
                status = .unsupported
            } else {
                do {
                    let fitting = try SavedFitting.decode(aid)
                    status = .decoded
                    let mode: Adaptation.Mode
                    switch fitting.adaptation.mode {
                    case .manual: mode = .manual
                    case .automatic: mode = .automatic
                    case .paused: mode = .paused
                    }
                    adaptation = Adaptation(mode: mode, currentStep: fitting.adaptation.currentStep,
                        startStep: fitting.adaptation.startStep, endStep: fitting.adaptation.endStep)
                    if let labels = try? OticonSavedAcoustics.decode(fitting) {
                        acoustics = Acoustics(earpiece: labels.earpiece.label, vent: labels.vent.label,
                            fittingLevel: labels.fittingLevel.label)
                    }
                    let controls = try? OticonSavedControls.decode(fitting)
                    programs = fitting.userPrograms.sorted { $0.slot.rawValue < $1.slot.rawValue }.map { program in
                        let extra = controls?.programs.first { $0.slot == program.slot }
                        return Program(slot: program.slot.rawValue,
                            noiseManagementEnabled: program.noiseManagement?.isEnabled,
                            feedbackManagementEnabled: program.feedback?.isEnabled,
                            frequencyLoweringEnabled: extra?.frequencyLoweringEnabled,
                            transientControl: extra?.transientControl?.label,
                            windControl: extra?.windControl?.label)
                    }
                } catch {
                    // CRC-valid archives can still contain an unsupported
                    // inner layout. Never fall back to consumer program data.
                    if let error = error as? OticonFittedConfiguration.DecodeError,
                       error == .unsupportedIdentity || error == .unsupportedVersion {
                        status = .unsupported
                    } else if let error = error as? OticonFittingRead.DecodeError,
                              error == .unsupportedFormat || error == .unsupportedHIIDVersion {
                        status = .unsupported
                    } else {
                        status = .unreadable
                    }
                }
            }
            let metadata: Metadata?
            if status == .decoded, let business = try? SavedFitting.businessData(aid) {
                let version = business.softwareVersion
                metadata = Metadata(fittingSoftwareVersion: "\(version.major).\(version.minor).\(version.patch)",
                    isPrerelease: version.isPrerelease, rationales: business.rationales.map(\.label))
            } else { metadata = nil }
            return Ear(side: side, isCaptured: true, model: aid.identity.model,
                firmwareVersion: aid.identity.firmware, softwareVersion: aid.identity.software,
                fittingStatus: status, endUserCoverage: coverage, adaptation: adaptation,
                acoustics: acoustics, programs: programs, metadata: metadata)
        }
    }
}
