import Foundation

/// An independently authored, read-only reader for one researched fitting format.
/// The constants describe interoperable bit positions, not a fitting algorithm.
/// It contains no vendor model files, executable code, curves or factory presets.
public enum OticonFittedConfiguration {
    public enum DecodeError: Error, Equatable {
        case unsupportedIdentity, unsupportedVersion, malformedSelection
        case truncated, invalidProgramDirectory, invalidValue, invalidString, invalidPadding
    }

    public struct Identity: Equatable, Sendable {
        public let modelUID: Int
        public let genericModelUID: Int
        public let hiidVersion: String
        public let releasePackageVersion: String
        public let runtimeMemoryMapVersion: String

        public init(modelUID: Int, genericModelUID: Int, hiidVersion: String,
                    releasePackageVersion: String, runtimeMemoryMapVersion: String) {
            self.modelUID = modelUID
            self.genericModelUID = genericModelUID
            self.hiidVersion = hiidVersion
            self.releasePackageVersion = releasePackageVersion
            self.runtimeMemoryMapVersion = runtimeMemoryMapVersion
        }

        public var isSupported: Bool {
            // Restrict application use to the captured firmware. A model lookup
            // accepting another patch does not itself establish its wire format.
            modelUID == 8513 && genericModelUID == 8460 && hiidVersion == "4.5"
                && releasePackageVersion == "5.0.29" && runtimeMemoryMapVersion == "10.0.0"
        }
    }

    public enum Slot: Int, Equatable, Sendable, CaseIterable {
        case p1, p2, p3, p4, automaticPhone, phoneShadow, television
        case remoteMicrophone, wiredMixed, wiredOnly, wiredShadow
        public var isUserProgram: Bool { rawValue < 4 }
        public var title: String {
            switch self {
            case .p1: "P1"
            case .p2: "P2"
            case .p3: "P3"
            case .p4: "P4"
            case .automaticPhone: "Automatic telephone"
            case .phoneShadow: "Telephone companion"
            case .television: "Television"
            case .remoteMicrophone: "Remote microphone"
            case .wiredMixed: "Wired input and microphone"
            case .wiredOnly: "Wired input"
            case .wiredShadow: "Wired input companion"
            }
        }
    }

    public enum Category: String, Equatable, Sendable {
        case listening, television, telephone, shadow, remoteMicrophone, wiredInput
    }

    /// These are serialized acoustic-selection codes, not decoded receiver,
    /// dome or vent dimensions. Keep them opaque until their code map is known.
    public struct Selection: Equatable, Sendable {
        public let earPieceCode, hookCode, ventCode, tubingCode: UInt8
        public let fittingLevelAcousticsCode, fittedSideCode: UInt8
    }

    public struct Adaptation: Equatable, Sendable {
        public enum Mode: Int, Equatable, Sendable { case manual, automatic, paused }
        public let mode: Mode
        public let startStep: Int
        public let currentStep: Double
        public let endStep: Int
        /// Stored time parameter; its unit is not established by this reader.
        public let timePerStep: Int
    }

    /// Values below are stored fitting parameter coordinates. This reader does
    /// not claim an acoustic dB scale, input-level scale or frequency axis.
    public struct Gain: Equatable, Sendable {
        public let map: [[Int]]
        public let prescribedSoftGain: [Int]
        public let mpo: [Int]
        public let kneePoints: [[Int]]
        public let reserveGain: Int
        public let compressionSpeedOrdinal: Int
    }

    public struct ProgramAdaptation: Equatable, Sendable {
        public let currentStepChange: [[Int]]
        public let prescribedStepChange: [[Int]]
    }

    public struct Feedback: Equatable, Sendable {
        public let isEnabled: Bool
        public let gainLimitDisabled: Bool
        public let limit: [Int]
        public let configurationOrdinal: Int
    }

    public struct Beamformer: Equatable, Sendable {
        public let transitionOrdinal, adaptationSpeedOrdinal: Int
        public let earMixtureOrdinal, directionalityPatternOrdinal: Int
    }

    public struct NoiseManagement: Equatable, Sendable {
        public let simpleAttenuationOrdinal, transitionOrdinal, complexAttenuationOrdinal: Int
        public let isEnabled: Bool
        public let patternOrdinal, omnidirectionalPatternOrdinal, adaptationPerformanceOrdinal: Int
        public let transientControlOrdinal: Int
        public let silencerEnabled: Bool
        public let windControlOrdinal: Int
        public let auxiliaryEnabled: Bool
        public let targetCompensationOrdinal: Int
    }

    /// Uninterpreted, bounded blocks remain available without inventing settings.
    /// packedBits is LSB-first and must remain in the private fitting archive.
    public struct OpaqueBits: Equatable, Sendable {
        public let name: String
        public let bitOffset, bitCount: Int
        public let packedBits: Data
    }

    public struct Program: Equatable, Sendable {
        public let slot: Slot
        public let templateOrdinal: Int
        public let category: Category
        public let label: String?
        public let gain: Gain?
        public let adaptation: ProgramAdaptation?
        public let feedback: Feedback?
        public let beamformer: Beamformer?
        public let noiseManagement: NoiseManagement?
        public let opaqueFields: [OpaqueBits]
        public var displayName: String { label.flatMap { $0.isEmpty ? nil : $0 } ?? slot.title }
    }

    public struct Snapshot: Equatable, Sendable {
        public let identity: Identity
        public let selection: Selection
        public let adaptation: Adaptation
        /// P1 through P4, remote microphone, television, default, in that order.
        public let programLabels: [String]
        public let programs: [Program]
        public let opaqueFields: [OpaqueBits]
        public let consumedBitCount, paddingBitCount: Int
        public var userPrograms: [Program] { programs.filter { $0.slot.isUserProgram } }
        public var accessoryPrograms: [Program] { programs.filter { !$0.slot.isUserProgram } }
    }

    /// Call after outer CRC/header validation with identity from the same saved
    /// device snapshot. Neither a user-selected model nor an assumed identity is
    /// a substitute for that check. The null version uses this exact model map.
    public static func decode(blob: OticonFittingRead.Blob, identity: Identity) throws -> Snapshot {
        guard identity.isSupported else { throw DecodeError.unsupportedIdentity }
        let selectionBytes = Array(blob.selection)
        guard selectionBytes.count == 6 else { throw DecodeError.malformedSelection }
        let selection = Selection(earPieceCode: selectionBytes[0], hookCode: selectionBytes[1],
                                  ventCode: selectionBytes[2], tubingCode: selectionBytes[3],
                                  fittingLevelAcousticsCode: selectionBytes[4], fittedSideCode: selectionBytes[5])
        let bytes = Array(blob.prodRegs)
        guard bytes.count >= 4, bytes.count <= 4000,
              bytes.prefix(4).allSatisfy({ $0 == 0xFF }) else { throw DecodeError.unsupportedVersion }
        var bits = BitCursor(bytes: bytes, position: 32)
        let countCode = try bits.read(4)
        let count = countCode == 0 ? 16 : countCode
        guard (1...11).contains(count) else { throw DecodeError.invalidProgramDirectory }
        var directory: [(Slot, Int)] = []
        var seen = Set<Int>()
        for _ in 0..<count {
            let slotCode = try bits.read(4)
            let template = try bits.read(5)
            guard let slot = Slot(rawValue: slotCode), template <= 25,
                  seen.insert(slotCode).inserted else { throw DecodeError.invalidProgramDirectory }
            directory.append((slot, template))
        }

        guard let mode = Adaptation.Mode(rawValue: try bits.ordinal(2, maximum: 2)) else {
            throw DecodeError.invalidValue
        }
        let start = try bits.ordinal(2, maximum: 2) + 1
        let current = Double(try bits.ordinal(8, maximum: 200)) / 100 + 1
        let end = try bits.ordinal(2, maximum: 2) + 1
        let time = try bits.ordinal(9, maximum: 300)
        let adaptation = Adaptation(mode: mode, startStep: start, currentStep: current,
                                    endStep: end, timePerStep: time)
        var opaque: [OpaqueBits] = []
        opaque.append(try bits.opaque("Shared settings before program metadata", count: 379))
        // Twelve one-bit program flags precede four fixed UTF-8 template fields.
        opaque.append(try bits.opaque("Program metadata flags", count: 12))
        for _ in 0..<4 {
            let start = bits.position
            _ = try bits.string(maximumBytes: 80, lengthWidth: 7)
            opaque.append(bits.capture("Program template metadata", from: start))
        }
        var labels: [String] = []
        for _ in 0..<7 { labels.append(try bits.string(maximumBytes: 30, lengthWidth: 5)) }
        // Singleton enum ordinals must be zero, including their one-bit storage.
        guard try bits.read(1) == 0 else { throw DecodeError.invalidValue }
        opaque.append(try bits.opaque("User program assignments", count: 3))
        _ = try bits.ordinal(3, maximum: 4)
        guard try bits.read(1) == 0 else { throw DecodeError.invalidValue }
        opaque.append(try bits.opaque("Ear and vent compensation and controls", count: 2722))

        var programs: [Program] = []
        for (slot, template) in directory {
            var programOpaque: [OpaqueBits] = []
            var gain: Gain?
            var programAdaptation: ProgramAdaptation?
            var feedback: Feedback?
            var beamformer: Beamformer?
            var noise: NoiseManagement?
            if template <= 18 {
                programAdaptation = try ProgramAdaptation(currentStepChange: bits.matrix(),
                                                           prescribedStepChange: bits.matrix())
                feedback = try Feedback(isEnabled: bits.read(1) != 0, gainLimitDisabled: bits.read(1) != 0,
                                        limit: bits.vector(), configurationOrdinal: bits.read(1))
                beamformer = try Beamformer(transitionOrdinal: bits.read(2),
                                            adaptationSpeedOrdinal: bits.ordinal(2, maximum: 2),
                                            earMixtureOrdinal: bits.ordinal(2, maximum: 2),
                                            directionalityPatternOrdinal: bits.ordinal(2, maximum: 2))
                programOpaque.append(try bits.opaque("Listening settings before gain", count: 23))
                gain = try Gain(map: bits.matrix(), prescribedSoftGain: bits.vector(), mpo: bits.vector(),
                                kneePoints: [bits.vector(), bits.vector(), bits.vector(), bits.vector()],
                                reserveGain: bits.read(8) - 78,
                                compressionSpeedOrdinal: bits.ordinal(2, maximum: 2))
            }
            programOpaque.append(try bits.opaque("Input selection", count: 18))
            if template <= 18 {
                noise = try NoiseManagement(simpleAttenuationOrdinal: bits.read(2),
                                             transitionOrdinal: bits.ordinal(3, maximum: 4),
                                             complexAttenuationOrdinal: bits.read(2),
                                             isEnabled: bits.read(1) == 0,
                                             patternOrdinal: bits.ordinal(3, maximum: 4),
                                             omnidirectionalPatternOrdinal: bits.read(2),
                                             adaptationPerformanceOrdinal: bits.read(2),
                                             transientControlOrdinal: bits.ordinal(3, maximum: 5),
                                             silencerEnabled: bits.read(1) == 0,
                                             windControlOrdinal: bits.ordinal(2, maximum: 2),
                                             auxiliaryEnabled: bits.read(1) == 0,
                                             targetCompensationOrdinal: bits.ordinal(2, maximum: 2))
                programOpaque.append(try bits.opaque("Sensor, bass, soft gain, tinnitus and volume settings", count: 671))
            } else if template == 19 || template == 23 {
                programOpaque.append(try bits.opaque("Accessory bass setting", count: 2))
            }
            let labelIndex: Int? = slot.isUserProgram ? slot.rawValue
                : slot == .remoteMicrophone ? 4 : slot == .television ? 5 : nil
            programs.append(Program(slot: slot, templateOrdinal: template, category: category(template),
                                    label: labelIndex.map { labels[$0] }, gain: gain,
                                    adaptation: programAdaptation, feedback: feedback,
                                    beamformer: beamformer, noiseManagement: noise, opaqueFields: programOpaque))
        }
        let consumed = bits.position
        let padding = bytes.count * 8 - consumed
        guard (0...7).contains(padding), try bits.read(padding) == 0 else { throw DecodeError.invalidPadding }
        return Snapshot(identity: identity, selection: selection, adaptation: adaptation,
                        programLabels: labels, programs: programs, opaqueFields: opaque,
                        consumedBitCount: consumed, paddingBitCount: padding)
    }

    private static func category(_ template: Int) -> Category {
        switch template {
        case 19: .television
        case 20: .telephone
        case 18, 21, 22: .shadow
        case 23: .remoteMicrophone
        case 24, 25: .wiredInput
        default: .listening
        }
    }

    private struct BitCursor {
        let bytes: [UInt8]
        var position: Int

        mutating func read(_ width: Int) throws -> Int {
            guard (0...31).contains(width), width <= bytes.count * 8 - position else { throw DecodeError.truncated }
            var value = 0
            for bit in 0..<width {
                let source = position + bit
                value |= Int((bytes[source / 8] >> (source % 8)) & 1) << bit
            }
            position += width
            return value
        }

        mutating func ordinal(_ width: Int, maximum: Int) throws -> Int {
            let value = try read(width)
            guard value <= maximum else { throw DecodeError.invalidValue }
            return value
        }

        mutating func vector() throws -> [Int] { try (0..<24).map { _ in try read(8) - 78 } }
        mutating func matrix() throws -> [[Int]] { try (0..<4).map { _ in try vector() } }

        mutating func string(maximumBytes: Int, lengthWidth: Int) throws -> String {
            let length = try ordinal(lengthWidth, maximum: maximumBytes)
            let storage = try (0..<maximumBytes).map { _ in UInt8(try read(8)) }
            guard storage.dropFirst(length).allSatisfy({ $0 == 0 }),
                  let value = String(bytes: storage.prefix(length), encoding: .utf8) else { throw DecodeError.invalidString }
            return value
        }

        mutating func opaque(_ name: String, count: Int) throws -> OpaqueBits {
            guard count >= 0, count <= bytes.count * 8 - position else { throw DecodeError.truncated }
            let start = position
            position += count
            return capture(name, from: start)
        }

        func capture(_ name: String, from start: Int) -> OpaqueBits {
            let count = position - start
            var packed = [UInt8](repeating: 0, count: (count + 7) / 8)
            for bit in 0..<count {
                let source = start + bit
                packed[bit / 8] |= ((bytes[source / 8] >> (source % 8)) & 1) << (bit % 8)
            }
            return OpaqueBits(name: name, bitOffset: start, bitCount: count, packedBits: Data(packed))
        }
    }
}
