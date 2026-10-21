import Foundation

/// Additional saved settings for the exact profile accepted by the fitting
/// reader. These values describe stored configuration, not current activity.
public enum OticonSavedControls {
    public enum DecodeError: Error, Equatable {
        case unsupportedIdentity, missingOrDuplicateBlock, malformedBlock, invalidValue
    }

    public struct Choice: Equatable, Sendable {
        public let code: Int
        /// Nil preserves an unassigned ordinal without inventing its meaning.
        public let label: String?
    }

    public struct FrequencyLowering: Equatable, Sendable {
        /// Configuration indexes are not cutoff frequencies or a frequency map.
        public let configurationIndex: Int
        public let prescribedConfigurationIndex: Int
        public let weight: Choice
        public let retainsSource: Bool
    }

    public struct Streaming: Equatable, Sendable {
        public let microphoneBalance: Choice
        public let mfiLoudness: Choice
        public let televisionLoudness: Choice
        public let remoteMicrophoneLoudness: Choice
    }

    public struct Inputs: Equatable, Sendable {
        public let microphone: Choice
        public let auxiliary: Choice
        public let wirelessSoundQuality: Choice
        /// Stored numeric coordinate; this reader does not establish its unit.
        public let crosBalance: Double
        public let crosSource: Choice
    }

    public struct Tinnitus: Equatable, Sendable {
        public let signalGeneratorEnabled: Bool
        public let levelSteeringEnabled: Bool
        public let noiseType: Choice
        public let modulation: Choice
        // The spectral shaping vector remains in the original opaque block.
    }

    public struct Program: Equatable, Sendable {
        public let slot: OticonFittedConfiguration.Slot
        public let inputs: Inputs
        /// Absent for templates that contain only accessory input settings.
        public let frequencyLoweringEnabled: Bool?
        /// Common-template coordinate, not proof of model feature availability.
        public let sensorFusionEnabled: Bool?
        /// Saved preference; applicability also depends on hardware and style.
        public let bassBoost: Choice?
        public let tinnitus: Tinnitus?
        public let transientControl: Choice?
        public let windControl: Choice?
    }

    public struct Snapshot: Equatable, Sendable {
        public let frequencyLowering: FrequencyLowering
        public let streaming: Streaming
        public let programs: [Program]
    }

    /// Supply the result of the existing identity/version/CRC-gated reader from
    /// the same archive. No Bluetooth, device writer, tap map or fitting engine
    /// is invoked. Unread portions remain in the original snapshot unchanged.
    public static func decode(_ fitting: OticonFittedConfiguration.Snapshot) throws -> Snapshot {
        guard fitting.identity.isSupported else { throw DecodeError.unsupportedIdentity }
        guard (1...11).contains(fitting.programs.count),
              Set(fitting.programs.map { $0.slot.rawValue }).count == fitting.programs.count else { throw DecodeError.invalidValue }
        let generalStart = 36 + fitting.programs.count * 9
        let shared = try block(fitting.opaqueFields, name: "Shared settings before program metadata",
                               offset: generalStart + 23, count: 379)
        let lowering = try FrequencyLowering(
            configurationIndex: shared.number(at: 311, width: 4, maximum: 9) + 1,
            prescribedConfigurationIndex: shared.number(at: 315, width: 4, maximum: 10),
            weight: shared.choice(at: 319, width: 3,
                                  labels: ["Low", "Low raised", "Medium reduced", "Medium", "Medium raised", "High reduced", "High"]),
            retainsSource: shared.read(at: 322, width: 1) == 0)
        let loudness = ["Default", "+3 dB", "+9 dB", "−3 dB", "−9 dB"]
        let streaming = try Streaming(
            microphoneBalance: shared.choice(at: 323, width: 3, labels: ["Default", "−3 dB", "−6 dB", "−9 dB", "−12 dB"]),
            mfiLoudness: shared.choice(at: 326, width: 3, labels: loudness),
            televisionLoudness: shared.choice(at: 329, width: 3, labels: loudness),
            remoteMicrophoneLoudness: shared.choice(at: 332, width: 3, labels: loudness))
        var start = generalStart + 7447
        var programs: [Program] = []
        for program in fitting.programs {
            let template = program.templateOrdinal
            guard (0...25).contains(template) else { throw DecodeError.invalidValue }
            let listening = template <= 18
            let input = try block(program.opaqueFields, name: "Input selection",
                                  offset: start + (listening ? 3692 : 0), count: 18)
            let inputs = try Inputs(
                microphone: input.choice(at: 0, width: 3, labels: ["Default", "−3 dB", "−6 dB", "−9 dB", "−12 dB", "Off"]),
                auxiliary: input.choice(at: 3, width: 1, labels: ["Default", "Off"]),
                wirelessSoundQuality: input.choice(at: 4, width: 3, labels: ["Fullest", "Fuller", "Default", "Brighter", "Brightest"]),
                crosBalance: Double(input.number(at: 7, width: 9, maximum: 400)) / 10 - 20,
                crosSource: input.choice(at: 16, width: 2, labels: ["Microphone only", "Stream only", "Microphone and stream"]))
            var loweringEnabled: Bool?, sensor: Bool?, bass: Choice?, tinnitus: Tinnitus?
            var transient: Choice?, wind: Choice?
            if listening {
                let before = try block(program.opaqueFields, name: "Listening settings before gain",
                                       offset: start + 1739, count: 23)
                loweringEnabled = try before.read(at: 19, width: 1) == 0
                let after = try block(program.opaqueFields, name: "Sensor, bass, soft gain, tinnitus and volume settings",
                                      offset: start + 3734, count: 671)
                sensor = try after.read(at: 0, width: 1) == 0
                bass = try after.choice(at: 1, width: 2, labels: ["High", "Medium", "Low", "Off"])
                tinnitus = try Tinnitus(
                    signalGeneratorEnabled: after.read(at: 294, width: 1) == 0,
                    levelSteeringEnabled: after.read(at: 295, width: 1) == 0,
                    noiseType: after.choice(at: 296, width: 2, labels: ["Shaped", "White", "Pink", "Red"]),
                    modulation: after.choice(at: 298, width: 3, labels: ["Off", "Ocean", "Tranquil", "Mild", "Spirited", "Bustling"]))
                guard let noise = program.noiseManagement else { throw DecodeError.malformedBlock }
                transient = choice(noise.transientControlOrdinal, labels: ["On low", "On medium", "On high", "On high plus", "On very high", "Off"])
                wind = choice(noise.windControlOrdinal, labels: ["On high", "On", "Off"])
                start += 4405
            } else if template == 19 || template == 23 {
                let accessory = try block(program.opaqueFields, name: "Accessory bass setting", offset: start + 18, count: 2)
                bass = try accessory.choice(at: 0, width: 2, labels: ["High", "Medium", "Low", "Off"])
                start += 20
            } else { start += 18 }
            programs.append(Program(slot: program.slot, inputs: inputs, frequencyLoweringEnabled: loweringEnabled,
                                    sensorFusionEnabled: sensor, bassBoost: bass, tinnitus: tinnitus,
                                    transientControl: transient, windControl: wind))
        }
        guard start == fitting.consumedBitCount else { throw DecodeError.malformedBlock }
        return Snapshot(frequencyLowering: lowering, streaming: streaming, programs: programs)
    }

    private static func choice(_ code: Int, labels: [String]) -> Choice {
        Choice(code: code, label: labels.indices.contains(code) ? labels[code] : nil)
    }

    private static func block(_ fields: [OticonFittedConfiguration.OpaqueBits], name: String,
                              offset: Int, count: Int) throws -> Bits {
        let matches = fields.filter { $0.name == name }
        guard matches.count == 1 else { throw DecodeError.missingOrDuplicateBlock }
        let field = matches[0]
        let bytes = Array(field.packedBits)
        guard field.bitOffset == offset, field.bitCount == count, bytes.count == (count + 7) / 8 else {
            throw DecodeError.malformedBlock
        }
        if count % 8 != 0, let last = bytes.last, last >> (count % 8) != 0 { throw DecodeError.malformedBlock }
        return Bits(bytes: bytes, count: count)
    }

    private struct Bits {
        let bytes: [UInt8]
        let count: Int
        func read(at offset: Int, width: Int) throws -> Int {
            guard offset >= 0, (1...16).contains(width), offset <= count, width <= count - offset else {
                throw DecodeError.malformedBlock
            }
            var result = 0
            for bit in 0..<width { result |= Int((bytes[(offset + bit) / 8] >> ((offset + bit) % 8)) & 1) << bit }
            return result
        }
        func number(at offset: Int, width: Int, maximum: Int) throws -> Int {
            let value = try read(at: offset, width: width)
            guard value <= maximum else { throw DecodeError.invalidValue }
            return value
        }
        func choice(at offset: Int, width: Int, labels: [String]) throws -> Choice {
            OticonSavedControls.choice(try read(at: offset, width: width), labels: labels)
        }
    }
}
