import Foundation

/// Reads the hardware-selection fields in detect_info opcode 3's HIID map.
/// This is a format decoder, not a hardware, acoustics or calibration validator.
/// Only the researched, fixed HIID 4.5 layouts are accepted. No serial is retained.
public enum OticonHardwareProfile {
    public enum DecodeError: Error, Equatable {
        case malformed
        case unsupportedHIIDVersion
        case missingEntry(UInt16)
        case unexpectedEntryLength(UInt16)
    }

    public struct Value: Equatable, Sendable {
        public let rawCode: UInt8
        /// HIID enumeration symbol; nil means the numeric code is unrecognized.
        /// An explicit Undefined or None remains distinct from an unknown code.
        public let identifier: String?
        public var isRecognized: Bool { identifier != nil }
    }

    public struct Product: Equatable, Sendable {
        public let brandUID: UInt32
        public let modelUID: UInt32
        public let modelVersion: UInt8
        public let genericModelUID: UInt32
        public let genericModelVersion: UInt8
        public let generationMajor: UInt8
        public let generationMinor: UInt8
        public let deviceTypeCode: UInt8
        public let supportedSSMTypeCode: UInt8
    }

    /// Categories reported by HIID, independently of a saved fitting selection.
    /// These bytes do not identify receiver variant, physical dimensions or fit.
    public struct Acoustics: Equatable, Sendable {
        public let hookCode: UInt8
        public let earPieceCode: UInt8
        public let fittingLevelCode: UInt8
        public let tubingCode: UInt8
        public let ventCode: UInt8
    }

    public struct Hardware: Equatable, Sendable {
        public let styleUID: UInt32
        public let controlWheelCode: UInt8
        public let microphoneCode: UInt8
        public let ledCode: UInt8
        public let motionSensorCode: UInt8
        public let pushButtonCode: UInt8
        public let removableSpeakerCode: UInt8
        public let telecoilCode: UInt8
        public let nearlinkRadioCode: UInt8
        public let wirelessRFCode: UInt8
        public let batterySizeCode: UInt8
        public let batteryTypeCode: UInt8
        public let fixedBatteryCode: UInt8
        public let physicalSideCode: UInt8
        public let audiologicalStyleCode: UInt8
        /// Hardware fitting level, distinct from the acoustic fitting level.
        public let fittingLevelCode: UInt8
        public let hearingInstrumentInterfaceCode: UInt8

        public var removableSpeaker: Value {
            Value(rawCode: removableSpeakerCode, identifier: [0: "Undefined", 1: "No", 2: "Yes"][removableSpeakerCode])
        }

        public var audiologicalStyle: Value {
            let identifiers: [UInt8: String] = [0: "Undefined", 101: "BTE", 102: "MiniBTE", 103: "NanoBTE",
                104: "CIC", 105: "IIC", 106: "ITC", 107: "ITE", 108: "RITE", 109: "MiniRITE",
                110: "NanoRITE", 111: "BCImini", 112: "BCXmini", 113: "BCX", 114: "EIE_CIC"]
            return Value(rawCode: audiologicalStyleCode, identifier: identifiers[audiologicalStyleCode])
        }

        public var fittingLevel: Value {
            let identifiers: [UInt8: String] = [0: "Undefined", 1: "Level60", 2: "Level75", 3: "Level80",
                4: "Level85", 5: "Level90", 6: "Level100", 7: "Level105", 8: "Level45", 9: "Level55",
                10: "Level65", 11: "Level110", 12: "Level120", 20: "None"]
            return Value(rawCode: fittingLevelCode, identifier: identifiers[fittingLevelCode])
        }

        public var hearingInstrumentInterface: Value {
            let identifiers: [UInt8: String] = [0: "Undefined", 1: "None", 2: "C1", 3: "C4", 4: "I10", 5: "MiniFit"]
            return Value(rawCode: hearingInstrumentInterfaceCode, identifier: identifiers[hearingInstrumentInterfaceCode])
        }
    }

    public struct Profile: Equatable, Sendable {
        public let hiidMajor: UInt8
        public let hiidMinor: UInt8
        public let product: Product
        public let hardwarePlatformConfigurationUID: UInt32
        public let hardwarePlatformConfigurationVersion: UInt8
        public let hardware: Hardware
        public let acoustics: Acoustics
    }

    /// Input is the complete, reassembled raw HIID CBOR map. Required entries
    /// 1001, 1002 and 1003 must be byte strings of exactly 2, 28 and 20 bytes.
    /// Integer keys and their text forms refer to the same entry; duplicates fail.
    /// Other entries are bounded and skipped without being retained or decoded.
    public static func decodeHiid(_ payload: Data) throws -> Profile {
        guard payload.count <= 65_535 else { throw DecodeError.malformed }
        var reader = Reader(bytes: Array(payload))
        let root = try reader.header()
        guard root.major == 5, root.argument <= 256 else { throw DecodeError.malformed }
        var keys = Set<String>(), blocks: [String: [UInt8]] = [:]
        for _ in 0..<Int(root.argument) {
            let key = try reader.key()
            guard keys.insert(key).inserted else { throw DecodeError.malformed }
            if ["1001", "1002", "1003"].contains(key) {
                blocks[key] = try reader.byteString()
            } else {
                try reader.skip(depth: 0)
            }
        }
        guard reader.index == reader.bytes.count else { throw DecodeError.malformed }
        func block(_ key: UInt16, length: Int) throws -> [UInt8] {
            guard let bytes = blocks[String(key)] else { throw DecodeError.missingEntry(key) }
            guard bytes.count == length else { throw DecodeError.unexpectedEntryLength(key) }
            return bytes
        }
        let version = try block(1001, length: 2)
        guard version == [4, 5] else { throw DecodeError.unsupportedHIIDVersion }
        let product = try block(1002, length: 28), hardware = try block(1003, length: 20)
        func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
            bytes[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
        // HIID 4.5 uses unsigned big-endian primitives and identity conversion
        // for these two fixed device-info entry packs. Addresses are byte offsets.
        return Profile(hiidMajor: version[0], hiidMinor: version[1],
            product: Product(brandUID: uint32(product, at: 0), modelUID: uint32(product, at: 4),
                modelVersion: product[8], genericModelUID: uint32(product, at: 9), genericModelVersion: product[13],
                generationMajor: product[24], generationMinor: product[25], deviceTypeCode: product[26],
                supportedSSMTypeCode: product[27]),
            hardwarePlatformConfigurationUID: uint32(product, at: 14), hardwarePlatformConfigurationVersion: product[18],
            hardware: Hardware(styleUID: uint32(hardware, at: 0), controlWheelCode: hardware[4], microphoneCode: hardware[5],
                ledCode: hardware[6], motionSensorCode: hardware[7], pushButtonCode: hardware[8],
                removableSpeakerCode: hardware[9], telecoilCode: hardware[10], nearlinkRadioCode: hardware[11],
                wirelessRFCode: hardware[12], batterySizeCode: hardware[13], batteryTypeCode: hardware[14],
                fixedBatteryCode: hardware[15], physicalSideCode: hardware[16], audiologicalStyleCode: hardware[17],
                fittingLevelCode: hardware[18], hearingInstrumentInterfaceCode: hardware[19]),
            acoustics: Acoustics(hookCode: product[19], earPieceCode: product[20], fittingLevelCode: product[21],
                tubingCode: product[22], ventCode: product[23]))
    }

    /// Deliberately local to this versioned reader. No tagged, indefinite or
    /// executable deserialization is supported; input, item and depth limits apply.
    private struct Reader {
        let bytes: [UInt8]
        var index = 0
        var items = 0

        mutating func byte() throws -> UInt8 {
            guard index < bytes.count else { throw DecodeError.malformed }
            defer { index += 1 }
            return bytes[index]
        }

        mutating func header() throws -> (major: UInt8, info: UInt8, argument: UInt64) {
            items += 1
            guard items <= 4096 else { throw DecodeError.malformed }
            let initial = try byte(), info = initial & 31
            let count: Int
            switch info {
            case 0..<24: return (initial >> 5, info, UInt64(info))
            case 24: count = 1
            case 25: count = 2
            case 26: count = 4
            case 27: count = 8
            default: throw DecodeError.malformed
            }
            var value: UInt64 = 0
            for _ in 0..<count { value = (value << 8) | UInt64(try byte()) }
            return (initial >> 5, info, value)
        }

        mutating func advance(_ count: UInt64) throws -> Range<Int> {
            guard count <= UInt64(bytes.count - index) else { throw DecodeError.malformed }
            let range = index..<(index + Int(count))
            index = range.upperBound
            return range
        }

        mutating func key() throws -> String {
            let value = try header()
            switch value.major {
            case 0: return String(value.argument)
            case 3:
                let range = try advance(value.argument)
                guard let text = String(bytes: bytes[range], encoding: .utf8) else { throw DecodeError.malformed }
                return text
            default: throw DecodeError.malformed
            }
        }

        mutating func byteString() throws -> [UInt8] {
            let value = try header()
            guard value.major == 2 else { throw DecodeError.malformed }
            let range = try advance(value.argument)
            return Array(bytes[range])
        }

        mutating func skip(depth: Int) throws {
            guard depth <= 12 else { throw DecodeError.malformed }
            let value = try header()
            switch value.major {
            case 0, 1: break
            case 2, 3: _ = try advance(value.argument)
            case 4, 5:
                guard value.argument <= 1024 else { throw DecodeError.malformed }
                for _ in 0..<(Int(value.argument) * (value.major == 5 ? 2 : 1)) { try skip(depth: depth + 1) }
            case 7:
                guard [20, 21, 22, 25, 26, 27].contains(value.info) else { throw DecodeError.malformed }
            default: throw DecodeError.malformed
            }
        }
    }
}
