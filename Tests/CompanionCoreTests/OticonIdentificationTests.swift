import Foundation
import Testing
@testable import CompanionCore

private let syntheticHIIDVersion = Data([0x19, 0x03, 0xE9, 0x42, 4, 5])
private let syntheticHIIDSerial = Data([0x19, 0x07, 0xD3, 0x44, 0x80, 0, 0, 123])

@Test func identificationNumericHIIDMapReadsActualAidSerial() throws {
    // Synthetic HIID 4.5; entry 2003 is the four-byte serial, not ASCII.
    let identity = try OticonIdentification.decodeHiid(Data([0xA2]) + syntheticHIIDVersion + syntheticHIIDSerial)
    #expect(identity.hiidMajor == 4 && identity.hiidMinor == 5)
    #expect(identity.serialNumber == "00000123")
}

@Test func identificationTextMapKeysAndNewSerialAlphabet() throws {
    let payload = Data([0xA2, 0x64]) + Data("1001".utf8) + Data([0x42, 4, 6, 0x64])
        + Data("2003".utf8) + Data([0x44, 0x54, 0xB6, 0x04, 0x43])
    #expect(try OticonIdentification.decodeHiid(payload).serialNumber == "ABC123")
    #expect(try OticonIdentification.serialNumber(Data([0x5A, 0xE7, 0xC2, 0x53])) == "EFGHJK")
    #expect(try OticonIdentification.serialNumber(Data([0x7F, 0xFF, 0xFF, 0xFF])) == "ZZZZZZ")
}

@Test func identificationSerialAbsenceAndDecimalFormatting() throws {
    #expect(try OticonIdentification.serialNumber(Data([0, 0, 0, 0])) == nil)
    #expect(try OticonIdentification.serialNumber(Data([0, 0, 0, 1])) == "00000001")
    #expect(try OticonIdentification.serialNumber(Data([0x80, 0, 0, 1])) == "00000001")
    #expect(try OticonIdentification.serialNumber(Data([0x8F, 0xFF, 0xFF, 0xFF])) == "268435455")
    #expect(try OticonIdentification.decodeHiid(Data([0xA1]) + syntheticHIIDVersion).serialNumber == nil)
    #expect(throws: OticonIdentification.DecodeError.malformed) { try OticonIdentification.serialNumber(Data([1, 2, 3])) }
}

@Test func identificationSkipsUnrelatedPrivateFieldsAndNeverUsesProductionSerial() throws {
    // 2002 = production serial, 1008 = application/fitting block. Neither is returned.
    let unrelated = Data([0x19, 0x07, 0xD2, 0x44, 1, 2, 3, 4,
                          0x19, 0x03, 0xF0, 0x43, 9, 8, 7])
    let identity = try OticonIdentification.decodeHiid(Data([0xA4]) + unrelated + syntheticHIIDVersion + syntheticHIIDSerial)
    #expect(identity.serialNumber == "00000123")
    let absent = try OticonIdentification.decodeHiid(Data([0xA3]) + unrelated + syntheticHIIDVersion)
    #expect(absent.serialNumber == nil)
}

@Test func identificationOnlyAcceptsProvenVersionsAndServices() throws {
    for (major, minor) in [(3, 4), (3, 5), (3, 7), (4, 3), (4, 5), (4, 6)] {
        let payload = Data([0xA2, 0x19, 0x03, 0xE9, 0x42, UInt8(major), UInt8(minor)]) + syntheticHIIDSerial
        #expect(try OticonIdentification.decodeHiid(payload).serialNumber == "00000123")
    }
    for version in [[UInt8(3), 2], [4, 4], [4, 7], [5, 0]] {
        let payload = Data([0xA1, 0x19, 0x03, 0xE9, 0x42] + version)
        #expect(throws: OticonIdentification.DecodeError.unsupportedHIIDVersion) { try OticonIdentification.decodeHiid(payload) }
    }
    for minor in [UInt8(0), 1, 2] {
        #expect(OticonIdentification.supports(.init(id: OticonIdentification.serviceID, handle: 9, major: 1, minor: minor, status: 0xFF)))
    }
    for service in [UTLProtocol.Service(id: 1, handle: 9, major: 1, minor: 0, status: 0xFF),
                    .init(id: OticonIdentification.serviceID, handle: 9, major: 1, minor: 3, status: 0xFF),
                    .init(id: OticonIdentification.serviceID, handle: 9, major: 1, minor: 2, status: 0)] {
        #expect(!OticonIdentification.supports(service))
    }
    #expect(OticonIdentification.hiidInfoOpcode == 3)
}

@Test func identificationRejectsMalformedDuplicateAndTrailingData() throws {
    let valid = Data([0xA2]) + syntheticHIIDVersion + syntheticHIIDSerial
    let duplicate = Data([0xA2]) + syntheticHIIDVersion + Data([0x64]) + Data("1001".utf8) + Data([0x42, 4, 5])
    var invalid: [Data] = [Data(), Data([0xA0]), Data(valid.dropLast()), valid + Data([0]), duplicate]
    invalid.append(Data([0xA1, 0x19, 0x03, 0xE9, 0x41, 4])) // one-byte version
    let textSerial = Data([0x19, 0x07, 0xD3, 0x64, 49, 50, 51, 52])
    let shortSerial = Data([0x19, 0x07, 0xD3, 0x43, 1, 2, 3])
    invalid.append(Data([0xA2]) + syntheticHIIDVersion + textSerial)
    invalid.append(Data([0xA2]) + syntheticHIIDVersion + shortSerial)
    invalid.append(Data([0xBF, 0xFF]))
    invalid.append(Data([0xC0]) + valid)
    for data in invalid {
        #expect(throws: OticonIdentification.DecodeError.malformed) { try OticonIdentification.decodeHiid(data) }
    }
}

@Test func identificationCBORWalkerHasPayloadAndNestingBounds() throws {
    let hugeCount = Data([0xBA, 0xFF, 0xFF, 0xFF, 0xFF])
    let nested = Data([0xA2]) + syntheticHIIDVersion + Data([0])
        + Data(repeating: 0x81, count: 20) + Data([0])
    for data in [hugeCount, nested, Data(repeating: 0, count: 65_536)] {
        #expect(throws: OticonIdentification.DecodeError.malformed) { try OticonIdentification.decodeHiid(data) }
    }
}
