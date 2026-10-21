import Foundation
import Testing
@testable import CompanionCore

private func businessSigned(_ values: [Int8]) -> Data { Data(values.map { UInt8(bitPattern: $0) }) }
private func businessInt16(_ value: Int16) -> Data {
    let raw = UInt16(bitPattern: value)
    return Data([UInt8(raw & 255), UInt8(raw >> 8)])
}
private func businessInt64(_ value: Int64) -> Data {
    let raw = UInt64(bitPattern: value)
    return Data((0..<8).map { UInt8(truncatingIfNeeded: raw >> ($0 * 8)) })
}
private let businessEmptyCurve = Data(repeating: 0x80, count: 22)
private let businessTestCurve = businessSigned([10, 15, 20, 25, 30, 35, 40, 45, 50, 55, -128])
    + businessSigned([0, 0, 1, 3, 4, 6, 7, 8, 9, 10, 99])

/// Independently constructed synthetic blocks; no captured values or resources.
private func businessBlockZero(rationales: [UInt8] = [3, 4]) -> Data {
    var data = Data([0x42, 0x4C, 0, 1, UInt8(rationales.count)]) + Data(rationales)
    data += businessInt16(27) + businessInt16(4) + businessInt16(2) + Data([1])
    data += businessTestCurve + businessEmptyCurve + businessEmptyCurve
    data += Data([1, 1, 0, 0]) + businessInt64(0) + businessInt64(0)
        + Data(repeating: 0x80, count: 22)
    return data
}
private func businessPad(_ data: Data) -> Data {
    precondition(data.count <= 500)
    return data + Data(repeating: 0, count: 500 - data.count)
}

@Test func businessVersionZeroDecodesRationalesSoftwareAndElevenFrequencySlots() throws {
    let result = try OticonBusinessData.decode(businessPad(businessBlockZero()))
    #expect(result.acousticsVerified)
    #expect(result.rationales.map(\.position) == [0, 1])
    #expect(result.rationales.map(\.code) == [3, 4])
    #expect(result.rationales.map(\.identifier) == ["FVM.FittingRationale.NALNL2", "FVM.FittingRationale.VACPlus"])
    #expect(result.rationales.map(\.label) == ["NAL-NL2", "VAC+"])
    #expect(result.softwareVersion.major == 27 && result.softwareVersion.minor == 4 && result.softwareVersion.patch == 2)
    #expect(result.softwareVersion.isPrerelease)
    #expect(result.softwareVersion.description == "27.4.2 (prerelease)")
    #expect(result.airConduction.points.map(\.frequencyHz) == [125, 250, 500, 750, 1000, 1500, 2000, 3000, 4000, 6000, 8000])
    #expect(result.airConduction.points[3].level == 25)
    #expect(result.airConduction.points[5].level == 35)
    #expect(result.boneConduction.points.allSatisfy { $0.level == nil && $0.tagCode == -128 })
    #expect(result.uncomfortableLevel.points.allSatisfy { $0.level == nil })
    #expect(result.decodedBlocks == [0] && !result.hasOpaqueTail)
}

@Test func businessTagSemanticsPreserveNoResponseUnknownAndAbsentSeparately() throws {
    let points = try OticonBusinessData.decode(businessPad(businessBlockZero())).airConduction.points
    #expect(points[0].tag == .unmasked && points[0].isOrdinaryResponse)
    #expect(points[2].tag == .unmaskedNoResponse && !points[2].isOrdinaryResponse)
    #expect(points[2].level == 20)
    #expect(points[3].tag == .masked && points[3].isOrdinaryResponse)
    #expect(points[4].tag == .maskedNoResponse && !points[4].isOrdinaryResponse)
    #expect(points[5].tag == .unknown && !points[5].isOrdinaryResponse)
    #expect(points[6].tag == .noStatus && !points[6].isOrdinaryResponse)
    #expect(points[7].tag == .alwaysResponse && !points[7].isOrdinaryResponse)
    #expect(points[8].tag == .couldNotTest && !points[8].isOrdinaryResponse)
    #expect(points[9].tag == .didNotTest && !points[9].isOrdinaryResponse)
    #expect(points[10].tag == nil && points[10].tagCode == 99 && points[10].level == nil)
    #expect(OticonBusinessData.MeasurementTag(rawValue: 2) == .unmaskedUnmeasurable)
    #expect(OticonBusinessData.MeasurementTag(rawValue: 5) == .maskedUnmeasurable)
    #expect(OticonBusinessData.MeasurementTag(rawValue: -128) == nil)
}

@Test func businessAllOptionalBlocksRespectLittleEndianAndPresenceFlags() throws {
    var data = businessBlockZero()
    data += Data([0x42, 0x4C, 0]) + businessSigned(Array(repeating: -2, count: 11)) + businessInt64(0x0102030405060708)
    data += Data([0x42, 0x4C, 0, 1]) + businessTestCurve
    data += Data([0x42, 0x4C, 0]) + businessSigned([-1, 3]) + businessInt16(-513)
    data += Data([0x42, 0x4C, 0, 1, 1])
    data += Data([0x4C, 0x42, 0, 1, 0])
    data += Data([0x4C, 0x42, 0, 1]) + businessInt16(-125) + Data([0x6E, 1])
    let result = try OticonBusinessData.decode(businessPad(data))
    #expect(result.decodedBlocks == [0, 1, 2, 3, 4, 5, 6])
    #expect(result.autoFitCorrection?.values == Array(repeating: Int8(-2), count: 11))
    #expect(result.autoFitCorrection?.modificationDateBinary == 0x0102030405060708)
    #expect(result.inSitu?.isUsed == true && result.inSitu?.audiogram.points.count == 11)
    #expect(result.adaptation?.startStep == -1 && result.adaptation?.endStep == 3 && result.adaptation?.timePerStep == -513)
    #expect(result.hasSSD == true && result.isBoneConductionExcluded == false)
    #expect(result.audibleContrastThreshold?.valueTenths == -125)
    #expect(result.audibleContrastThreshold?.modificationDaysSince2022 == 366)
    #expect(!result.hasOpaqueTail)
}

@Test func businessAbsentOptionalSectionsDoNotConsumeFollowingHeaders() throws {
    var data = businessBlockZero()
    data += Data([0x42, 0x4C, 0]) + Data(repeating: 0x80, count: 11) + businessInt64(0)
    data += Data([0x42, 0x4C, 0, 0x42, 0x4C, 0, 0x42, 0x4C, 0, 0])
    data += Data([0x4C, 0x42, 0, 0, 0x4C, 0x42, 0, 0])
    let result = try OticonBusinessData.decode(businessPad(data))
    #expect(result.decodedBlocks == [0, 1, 2, 3, 4, 5, 6])
    #expect(result.inSitu == nil && result.adaptation == nil && result.hasSSD == nil)
    #expect(result.isBoneConductionExcluded == nil && result.audibleContrastThreshold == nil)
    #expect(!result.hasOpaqueTail)
}

@Test func businessUnknownRationaleAndTailRemainOpaque() throws {
    let result = try OticonBusinessData.decode(businessPad(businessBlockZero(rationales: [0xFE]) + Data([0xDE, 0xAD])))
    #expect(result.rationales[0].code == 0xFE && result.rationales[0].label == nil && result.rationales[0].identifier == nil)
    #expect(result.hasOpaqueTail && result.tail.prefix(2) == Data([0xDE, 0xAD]))
    let original = businessPad(businessBlockZero())
    let sliced = (Data([0xFF]) + original).dropFirst()
    #expect(try OticonBusinessData.decode(sliced) == OticonBusinessData.decode(original))
}

@Test func businessLBLookingTailRemainsExactAfterAnyMissingBLPrerequisite() throws {
    let block0 = businessBlockZero()
    let block1 = Data([0x42, 0x4C, 0]) + Data(repeating: 0x80, count: 11) + businessInt64(0)
    let block2 = Data([0x42, 0x4C, 0, 1]) + businessEmptyCurve
    let block3 = Data([0x42, 0x4C, 0, 0, 1]) + businessInt16(1)
    let prefixes = [block0, block0 + block1, block0 + block1 + block2, block0 + block1 + block2 + block3]
    for (lastBlock, prefix) in prefixes.enumerated() {
        // The first tail used to disappear as a false block5, leaving an
        // apparently all-zero tail. The second used to throw a false version
        // error despite the prerequisite BL sequence already having ended.
        for opaque in [Data([0x4C, 0x42, 0, 0]), Data([0x4C, 0x42, 7, 0xA5])] {
            let raw = businessPad(prefix + opaque)
            let result = try OticonBusinessData.decode(raw)
            #expect(result.decodedBlocks == Array(0...lastBlock))
            #expect(result.isBoneConductionExcluded == nil && result.audibleContrastThreshold == nil)
            #expect(result.hasOpaqueTail)
            #expect(result.tail == Data(raw.dropFirst(prefix.count)))
        }
    }
}

@Test func businessExactLengthAndRecognizedBlockVersionsAreRequired() throws {
    let valid = businessPad(businessBlockZero())
    for invalid in [Data(), Data(valid.dropLast()), valid + Data([0])] {
        #expect(throws: OticonBusinessData.DecodeError.invalidLength) { try OticonBusinessData.decode(invalid) }
    }
    var badSignature = valid; badSignature[0] = 0x4C
    #expect(throws: OticonBusinessData.DecodeError.invalidSignature) { try OticonBusinessData.decode(badSignature) }
    var badVersion = valid; badVersion[2] = 1
    #expect(throws: OticonBusinessData.DecodeError.unsupportedVersion(block: 0, version: 1)) { try OticonBusinessData.decode(badVersion) }
    let unknownOptional = businessPad(businessBlockZero() + Data([0x42, 0x4C, 7]))
    #expect(throws: OticonBusinessData.DecodeError.unsupportedVersion(block: 1, version: 7)) { try OticonBusinessData.decode(unknownOptional) }
}

@Test func businessRejectsInvalidBooleansAndOutOfRangeStoredAudiograms() throws {
    let valid = businessPad(businessBlockZero())
    var badBoolean = valid; badBoolean[3] = 2
    #expect(throws: OticonBusinessData.DecodeError.invalidBoolean) { try OticonBusinessData.decode(badBoolean) }
    var invalidLevel = valid; invalidLevel[14] = 0x7F
    #expect(throws: OticonBusinessData.DecodeError.invalidAudiogram) { try OticonBusinessData.decode(invalidLevel) }
    var missingNormalTag = valid; missingNormalTag[14] = 0x80
    let missingPoint = try OticonBusinessData.decode(missingNormalTag).airConduction.points[0]
    #expect(missingPoint.level == nil && missingPoint.tag == .unmasked && !missingPoint.isOrdinaryResponse)
}
