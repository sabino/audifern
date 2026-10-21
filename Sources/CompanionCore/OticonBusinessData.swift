import Foundation

/// Inert decoding of the fixed 500-byte BL/LB version-zero fitting metadata.
/// It contains saved fitting information, not a new measurement or prescription.
public enum OticonBusinessData {
    public static let byteCount = 500
    public static let frequencies = [125, 250, 500, 750, 1000, 1500, 2000, 3000, 4000, 6000, 8000]

    public enum DecodeError: Error, Equatable {
        case invalidLength, invalidSignature, truncated, invalidBoolean, invalidAudiogram
        case unsupportedVersion(block: Int, version: UInt8)
    }

    public enum ReviewError: Error, Equatable { case unitsUnconfirmed }

    /// The stored format omits audiometry method/units and can contain uncorrected
    /// ABR/nHL values. Only an explicit external confirmation permits a dB HL
    /// draft. Uncertain, NR, unmeasurable, UCL and in-situ points stay in the raw
    /// snapshot instead of becoming ordinary air/bone thresholds.
    public static func thresholdsForReview(_ snapshot: Snapshot, ear: AudiogramEar,
                                          confirmedDBHL: Bool) throws -> [AudiogramThreshold] {
        guard confirmedDBHL else { throw ReviewError.unitsUnconfirmed }
        return [(AudiogramConduction.air, snapshot.airConduction), (.bone, snapshot.boneConduction)]
            .flatMap { conduction, curve in
                curve.points.compactMap { point -> AudiogramThreshold? in
                    guard point.isOrdinaryResponse, let level = point.level else { return nil }
                    return AudiogramThreshold(key: AudiogramThresholdKey(ear: ear, conduction: conduction,
                        frequencyHz: point.frequencyHz, masked: point.tag == .masked), levelDBHL: Double(level))
                }
            }
    }

    public enum MeasurementTag: Int8, Codable, Sendable {
        case unmasked = 0, unmaskedNoResponse, unmaskedUnmeasurable
        case masked, maskedNoResponse, maskedUnmeasurable, unknown, noStatus
        case alwaysResponse, couldNotTest, didNotTest
    }

    public struct Point: Equatable, Sendable {
        public let frequencyHz: Int
        /// Signed saved Audiogram.Values entry; nil represents the -128 sentinel.
        public let level: Int?
        public let tagCode: Int8
        public var tag: MeasurementTag? { MeasurementTag(rawValue: tagCode) }
        /// Missing, unknown and no-response tags never become normal thresholds.
        public var isOrdinaryResponse: Bool { level != nil && (tag == .unmasked || tag == .masked) }
    }

    public struct Curve: Equatable, Sendable {
        public let points: [Point]
    }

    public struct Rationale: Equatable, Sendable {
        /// Zero-based ProgramSetups position, not an active program count or ID.
        public let position: Int
        public let code: UInt8
        public var identifier: String? { rationaleNames[Int(code)]?.0 }
        public var label: String? { rationaleNames[Int(code)]?.1 }
    }

    public struct SoftwareVersion: Equatable, Sendable {
        public let major: Int
        public let minor: Int
        public let patch: Int
        public let isPrerelease: Bool
        public var description: String { "\(major).\(minor).\(patch)" + (isPrerelease ? " (prerelease)" : "") }
    }

    public struct RealEar: Equatable, Sendable {
        public let originRECD: Int8
        public let originREUG: Int8
        public let freeFieldAngleCode: Int8
        public let measurementSetupCode: Int8
        /// Raw DateTime.ToBinary() values; no timezone or calendar is inferred.
        public let modificationDateRECDBinary: Int64
        public let modificationDateREUGBinary: Int64
        public let measuredRECD: [Int8]
        public let measuredREUG: [Int8]
    }

    public struct Correction: Equatable, Sendable {
        public let values: [Int8]
        public let modificationDateBinary: Int64
    }

    public struct InSitu: Equatable, Sendable {
        public let isUsed: Bool
        public let audiogram: Curve
    }

    public struct Adaptation: Equatable, Sendable {
        public let startStep: Int8
        public let endStep: Int8
        /// The stored integer; this codec does not infer its time unit.
        public let timePerStep: Int16
    }

    public struct AudibleContrastThreshold: Equatable, Sendable {
        public let valueTenths: Int16
        public let modificationDaysSince2022: UInt16
    }

    public struct Snapshot: Equatable, Sendable {
        public let acousticsVerified: Bool
        public let rationales: [Rationale]
        public let softwareVersion: SoftwareVersion
        public let airConduction: Curve
        public let boneConduction: Curve
        public let uncomfortableLevel: Curve
        public let realEar: RealEar
        public let autoFitCorrection: Correction?
        public let inSitu: InSitu?
        public let adaptation: Adaptation?
        public let hasSSD: Bool?
        public let isBoneConductionExcluded: Bool?
        public let audibleContrastThreshold: AudibleContrastThreshold?
        public let decodedBlocks: [Int]
        /// Preserve unparsed bytes. The known serializer zero-pads its 500 bytes.
        public let tail: Data
        public var hasOpaqueTail: Bool { tail.contains { $0 != 0 } }
    }

    public static func decode(_ data: Data) throws -> Snapshot {
        guard data.count == byteCount else { throw DecodeError.invalidLength }
        var r = Reader(bytes: Array(data))
        guard try r.header(block: 0, signature: [0x42, 0x4C]) else { throw DecodeError.invalidSignature }
        let verified = try r.boolean()
        let count = Int(try r.byte())
        var rationales: [Rationale] = []
        for position in 0..<count { rationales.append(Rationale(position: position, code: try r.byte())) }
        let software = try SoftwareVersion(major: Int(r.int16()), minor: Int(r.int16()),
                                           patch: Int(r.int16()), isPrerelease: r.boolean())
        let air = try r.curve(), bone = try r.curve(), ucl = try r.curve()
        let realEar = try RealEar(originRECD: r.signedByte(), originREUG: r.signedByte(),
            freeFieldAngleCode: r.signedByte(), measurementSetupCode: r.signedByte(),
            modificationDateRECDBinary: r.int64(), modificationDateREUGBinary: r.int64(),
            measuredRECD: r.signedBytes(11), measuredREUG: r.signedBytes(11))
        var blocks = [0], correction: Correction?, inSitu: InSitu?, adaptation: Adaptation?
        var hasSSD: Bool?, bcExcluded: Bool?, act: AudibleContrastThreshold?
        for block in 1..<5 {
            guard try r.header(block: block, signature: [0x42, 0x4C]) else { break }
            blocks.append(block)
            switch block {
            case 1:
                correction = try Correction(values: r.signedBytes(11), modificationDateBinary: r.int64())
            case 2:
                // Missing optional data is immediately followed by the next BL
                // header; it is not encoded as an all-zero audiogram.
                if !r.starts(with: [0x42, 0x4C]) {
                    inSitu = try InSitu(isUsed: r.boolean(), audiogram: r.curve())
                }
            case 3:
                if !r.starts(with: [0x42, 0x4C]) {
                    adaptation = try Adaptation(startStep: r.signedByte(), endStep: r.signedByte(), timePerStep: r.int16())
                }
            case 4:
                if try r.boolean() { hasSSD = try r.boolean() }
            default: break
            }
        }
        // The writer emits every preceding BL header before the LB phase.
        // After a gap, even LB-looking bytes belong to the preserved opaque tail.
        if blocks.last == 4 {
            for block in 5..<7 {
                guard try r.header(block: block, signature: [0x4C, 0x42]) else { break }
                blocks.append(block)
                if try r.boolean() {
                    if block == 5 { bcExcluded = try r.boolean() }
                    else { act = try AudibleContrastThreshold(valueTenths: r.int16(), modificationDaysSince2022: r.uint16()) }
                }
            }
        }
        return Snapshot(acousticsVerified: verified, rationales: rationales, softwareVersion: software,
            airConduction: air, boneConduction: bone, uncomfortableLevel: ucl, realEar: realEar,
            autoFitCorrection: correction, inSitu: inSitu, adaptation: adaptation,
            hasSSD: hasSSD, isBoneConductionExcluded: bcExcluded, audibleContrastThreshold: act,
            decodedBlocks: blocks, tail: Data(r.bytes.dropFirst(r.index)))
    }

    /// Stable wire codes, with display names authored for this reader.
    private static let rationaleNames: [Int: (String, String)] = [
        0: ("ZEN_ACTIVE", "ZEN Active"),
        1: ("FVM.FittingRationale.DSL50aAdult", "DSL v5 Adult"),
        2: ("FVM.FittingRationale.DSL50aPaed", "DSL v5 Pediatric"),
        3: ("FVM.FittingRationale.NALNL2", "NAL-NL2"),
        4: ("FVM.FittingRationale.VACPlus", "VAC+"),
        5: ("FVM.FittingRationale.NALNL1", "NAL-NL1"),
        6: ("FVM.FittingRationale.BernafitNL", "Bernafit NL"),
        7: ("FVM.FittingRationale.BernafitComfort", "Bernafit Comfort"),
        8: ("FVM.FittingRationale.NALNL1BC", "NAL-NL1 BC"),
        9: ("FVM.FittingRationale.DSESP", "DSE SP"),
        10: ("FVM.FittingRationale.DSElin", "DSE linear"),
        11: ("FVM.FittingRationale.DSLBCAdult", "DSL BC Adult"),
        12: ("FVM.FittingRationale.DSLBCPaed", "DSL BC Pediatric"),
        13: ("FVM.FittingRationale.NALNL3", "NAL-NL3")
    ]

    private struct Reader {
        let bytes: [UInt8]
        var index = 0

        func starts(with prefix: [UInt8]) -> Bool {
            bytes.count - index >= prefix.count && Array(bytes[index..<(index + prefix.count)]) == prefix
        }
        mutating func byte() throws -> UInt8 {
            guard index < bytes.count else { throw DecodeError.truncated }
            defer { index += 1 }
            return bytes[index]
        }
        mutating func boolean() throws -> Bool {
            let value = try byte()
            guard value <= 1 else { throw DecodeError.invalidBoolean }
            return value == 1
        }
        mutating func signedByte() throws -> Int8 { Int8(bitPattern: try byte()) }
        mutating func signedBytes(_ count: Int) throws -> [Int8] {
            var values: [Int8] = []
            for _ in 0..<count { values.append(try signedByte()) }
            return values
        }
        mutating func uint16() throws -> UInt16 {
            let low = UInt16(try byte()), high = UInt16(try byte())
            return low | (high << 8)
        }
        mutating func int16() throws -> Int16 { Int16(bitPattern: try uint16()) }
        mutating func int64() throws -> Int64 {
            var result: UInt64 = 0
            for shift in stride(from: 0, through: 56, by: 8) { result |= UInt64(try byte()) << shift }
            return Int64(bitPattern: result)
        }
        mutating func header(block: Int, signature: [UInt8]) throws -> Bool {
            guard starts(with: signature) else { return false }
            index += signature.count
            let version = try byte()
            guard version == 0 else { throw DecodeError.unsupportedVersion(block: block, version: version) }
            return true
        }
        mutating func curve() throws -> Curve {
            let values = try signedBytes(frequencies.count), tags = try signedBytes(frequencies.count)
            guard values.allSatisfy({ $0 == -128 || (-10...120).contains(Int($0)) }) else { throw DecodeError.invalidAudiogram }
            return Curve(points: frequencies.indices.map {
                Point(frequencyHz: frequencies[$0], level: values[$0] == -128 ? nil : Int(values[$0]), tagCode: tags[$0])
            })
        }
    }
}
