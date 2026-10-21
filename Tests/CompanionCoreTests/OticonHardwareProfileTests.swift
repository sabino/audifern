import Foundation
import Testing
@testable import CompanionCore

// Independently constructed synthetic HIID 4.5 entries, not device captures.
private let hardwareTestProduct: [UInt8] = [
    0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF, 0x12,
    0x24, 0x68, 0xAC, 0xE0, 0x34, 0xFE, 0xDC, 0xBA, 0x98, 0x56,
    0x61, 0x62, 0x63, 0x64, 0x65, 7, 3, 0x71, 0x72
]
private let hardwareTestFeatures: [UInt8] = [
    0x10, 0x32, 0x54, 0x76, 0x21, 0x22, 0x23, 0x24, 0x25,
    2, 0x27, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 109, 8, 3
]

private func hardwareTestEntry(_ key: UInt16, _ bytes: [UInt8], textKey: Bool = false) -> Data {
    let keyBytes = textKey ? [UInt8(0x64)] + Array(String(key).utf8) : [0x19, UInt8(key >> 8), UInt8(key & 255)]
    let length = bytes.count < 24 ? [UInt8(0x40 + bytes.count)] : [0x58, UInt8(bytes.count)]
    return Data(keyBytes + length + bytes)
}

private func hardwareTestMap(product: [UInt8] = hardwareTestProduct, features: [UInt8] = hardwareTestFeatures,
                             version: [UInt8] = [4, 5], textKeys: Bool = false) -> Data {
    Data([0xA3]) + hardwareTestEntry(1001, version, textKey: textKeys)
        + hardwareTestEntry(1002, product, textKey: textKeys) + hardwareTestEntry(1003, features, textKey: textKeys)
}

@Test func hardwareProfileUsesExactByteOffsetsAndUnsignedBigEndian() throws {
    let p = try OticonHardwareProfile.decodeHiid(hardwareTestMap())
    #expect(p.hiidMajor == 4 && p.hiidMinor == 5)
    #expect(p.product.brandUID == 0x01234567)
    #expect(p.product.modelUID == 0x89ABCDEF)
    #expect(p.product.modelVersion == 0x12)
    #expect(p.product.genericModelUID == 0x2468ACE0 && p.product.genericModelVersion == 0x34)
    #expect(p.hardwarePlatformConfigurationUID == 0xFEDCBA98 && p.hardwarePlatformConfigurationVersion == 0x56)
    #expect(p.product.generationMajor == 7 && p.product.generationMinor == 3)
    #expect(p.product.deviceTypeCode == 0x71 && p.product.supportedSSMTypeCode == 0x72)
    #expect(p.acoustics.hookCode == 0x61 && p.acoustics.earPieceCode == 0x62)
    #expect(p.acoustics.fittingLevelCode == 0x63 && p.acoustics.tubingCode == 0x64 && p.acoustics.ventCode == 0x65)
    #expect(p.hardware.styleUID == 0x10325476)
    #expect([p.hardware.controlWheelCode, p.hardware.microphoneCode, p.hardware.ledCode,
             p.hardware.motionSensorCode, p.hardware.pushButtonCode] == [0x21, 0x22, 0x23, 0x24, 0x25])
    #expect([p.hardware.telecoilCode, p.hardware.nearlinkRadioCode, p.hardware.wirelessRFCode,
             p.hardware.batterySizeCode, p.hardware.batteryTypeCode, p.hardware.fixedBatteryCode,
             p.hardware.physicalSideCode] == [0x27, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D])
    #expect(p.hardware.removableSpeaker.identifier == "Yes")
    #expect(p.hardware.audiologicalStyle.identifier == "MiniRITE")
    #expect(p.hardware.fittingLevel.identifier == "Level45") // Explicit value 8, not a sorted-list index.
    #expect(p.hardware.hearingInstrumentInterface.identifier == "C4")
}

@Test func hardwareProfileNormalizesIntegerAndTextKeysAndSkipsPrivateEntries() throws {
    let numeric = try OticonHardwareProfile.decodeHiid(hardwareTestMap())
    #expect(try OticonHardwareProfile.decodeHiid(hardwareTestMap(textKeys: true)) == numeric)
    var map = hardwareTestMap()
    map[0] = 0xA4
    // Unrelated entry: a nested map containing a byte string and boolean.
    map += Data([0x19, 0x07, 0xD3, 0xA1, 0x42, 0xAA, 0xBB, 0x82, 0xF5, 0xF6])
    #expect(try OticonHardwareProfile.decodeHiid(map) == numeric)
}

@Test func hardwareProfilePreservesUnknownAndUnspecifiedSelectorCodes() throws {
    var recognized = [0, 0, 0, 0]
    for raw in UInt8.min...UInt8.max {
        var features = hardwareTestFeatures
        for offset in [9, 17, 18, 19] { features[offset] = raw }
        let hardware = try OticonHardwareProfile.decodeHiid(hardwareTestMap(features: features)).hardware
        let values = [hardware.removableSpeaker, hardware.audiologicalStyle, hardware.fittingLevel,
                      hardware.hearingInstrumentInterface]
        for (index, value) in values.enumerated() {
            #expect(value.rawCode == raw)
            if value.isRecognized { recognized[index] += 1 }
            if raw == 0 { #expect(value.identifier == "Undefined") }
            if raw == 255 { #expect(value.identifier == nil) }
        }
    }
    #expect(recognized == [3, 15, 14, 6])
    var features = hardwareTestFeatures
    features[18] = 20
    features[19] = 1
    let hardware = try OticonHardwareProfile.decodeHiid(hardwareTestMap(features: features)).hardware
    #expect(hardware.fittingLevel.identifier == "None" && hardware.hearingInstrumentInterface.identifier == "None")
}

@Test func hardwareProfileRequiresAllThreeExactVersionedEntries() throws {
    for (key, bytes) in [(UInt16(1001), [UInt8(4), 5]), (1002, hardwareTestProduct), (1003, hardwareTestFeatures)] {
        let missing = Data([0xA2]) + [(UInt16(1001), [UInt8(4), 5]), (1002, hardwareTestProduct), (1003, hardwareTestFeatures)]
            .filter { $0.0 != key }.reduce(Data()) { $0 + hardwareTestEntry($1.0, $1.1) }
        #expect(throws: OticonHardwareProfile.DecodeError.missingEntry(key)) {
            try OticonHardwareProfile.decodeHiid(missing)
        }
        for altered in [Array(bytes.dropLast()), bytes + [0]] {
            let malformed = Data([0xA3]) + [(UInt16(1001), [UInt8(4), 5]), (1002, hardwareTestProduct), (1003, hardwareTestFeatures)]
                .reduce(Data()) { $0 + hardwareTestEntry($1.0, $1.0 == key ? altered : $1.1) }
            #expect(throws: OticonHardwareProfile.DecodeError.unexpectedEntryLength(key)) {
                try OticonHardwareProfile.decodeHiid(malformed)
            }
        }
    }
    for version in [[UInt8(3), 5], [4, 3], [4, 6], [5, 0]] {
        #expect(throws: OticonHardwareProfile.DecodeError.unsupportedHIIDVersion) {
            try OticonHardwareProfile.decodeHiid(hardwareTestMap(version: version))
        }
    }
}

@Test func hardwareProfileRejectsMalformedDuplicateAndUnboundedCBOR() throws {
    let valid = hardwareTestMap()
    var duplicate = valid
    duplicate[0] = 0xA4
    duplicate += hardwareTestEntry(1002, hardwareTestProduct, textKey: true)
    var nested = valid
    nested[0] = 0xA4
    nested += Data([0]) + Data(repeating: 0x81, count: 20) + Data([0])
    var tooManyItems = valid
    tooManyItems[0] = 0xA4
    tooManyItems += Data([0, 0x99, 0x04, 0x00])
    for _ in 0..<1024 { tooManyItems += Data([0x83, 0, 0, 0]) }
    let wrongValueType = Data([0xA1, 0x19, 0x03, 0xE9, 0x62, 4, 5])
    for invalid in [Data(), Data(valid.dropLast()), valid + Data([0]), duplicate, nested, tooManyItems,
                    wrongValueType, Data([0xBF, 0xFF]), Data([0xC0]) + valid,
                    Data([0xBA, 0xFF, 0xFF, 0xFF, 0xFF]), Data(repeating: 0, count: 65_536)] {
        #expect(throws: OticonHardwareProfile.DecodeError.malformed) { try OticonHardwareProfile.decodeHiid(invalid) }
    }
}
