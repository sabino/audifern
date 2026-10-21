import Foundation
import Testing
@testable import CompanionCore

// Synthetic data only. CRC values were calculated independently by polynomial
// long division, not by calling the production checksum implementation.
private let fittingBlob = Data([
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    6, 0, 1, 2, 3, 4, 5, 6,
    5, 0, 5, 0, 29, 0xFF, 0xA5,
    3, 0, 0xDE, 0xAD, 0xBE
])
private let fittingHeader = Data([
    0, 0, 4, 0, 0, 36, 0xF0, 0x2D,
    0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80
])

@Test func fittingReadRequiresMatchedHIIDAndAdvertisedContract() {
    for minor in [UInt8(0), 1] {
        let service = UTLProtocol.Service(id: 0x02000006, handle: 7, major: 1, minor: minor, status: 0xFF)
        #expect(OticonFittingRead.supports(service: service, hiidVersion: "4.5"))
        for hiid in ["3.7", "4.3", "4.6", "4.5.0", ""] {
            #expect(!OticonFittingRead.supports(service: service, hiidVersion: hiid))
        }
    }
    for service in [UTLProtocol.Service(id: 0x02000004, handle: 7, major: 1, minor: 1, status: 0xFF),
                    .init(id: 0x02000006, handle: 7, major: 1, minor: 2, status: 0xFF),
                    .init(id: 0x02000006, handle: 7, major: 2, minor: 0, status: 0xFF),
                    .init(id: 0x02000006, handle: 7, major: 1, minor: 1, status: 0)] {
        #expect(!OticonFittingRead.supports(service: service, hiidVersion: "4.5"))
    }
}

@Test func fittingReadRequestUsesLiteralKeyAndBigEndianRange() throws {
    #expect(OticonFittingRead.readOpcode == 0)
    #expect(try OticonFittingRead.readRequest(offset: 0, length: 16)
            == Data([1, 3, 0xF1, 0, 0, 0, 16]))
    #expect(try OticonFittingRead.readRequest(offset: 966, length: 950)
            == Data([1, 3, 0xF1, 3, 0xC6, 3, 0xB6]))
    #expect(try OticonFittingRead.readRequest(offset: 4015, length: 1)
            == Data([1, 3, 0xF1, 0x0F, 0xAF, 0, 1]))
    for (offset, length) in [(-1, 16), (0, 0), (0, -1), (0, 951), (4016, 1),
                             (4015, 2), (Int.max, 1), (1, Int.max), (Int.min, Int.min)] {
        #expect(throws: OticonFittingRead.DecodeError.invalidReadRange) {
            try OticonFittingRead.readRequest(offset: offset, length: length)
        }
    }
}

@Test func fittingReadResponseIsRawBytesWithExactRequestedLength() throws {
    #expect(try OticonFittingRead.decodeReadResponse(fittingHeader, expectedLength: 16) == fittingHeader)
    // A Data slice may start at a nonzero index; the codec cannot assume index 0.
    let slice = (Data([0xFF]) + fittingHeader).dropFirst()
    #expect(try OticonFittingRead.Header(data: slice).size == 36)
    for (data, length) in [(fittingHeader + Data([0]), 16), (Data(fittingHeader.dropLast()), 16),
                           (Data(), 0), (Data(repeating: 0, count: 951), 951)] {
        #expect(throws: OticonFittingRead.DecodeError.unexpectedResponseLength) {
            try OticonFittingRead.decodeReadResponse(data, expectedLength: length)
        }
    }
}

@Test func fittingHeaderDecodesPackedVersionAndPreservesReservedBytes() throws {
    let header = try OticonFittingRead.Header(data: fittingHeader)
    #expect(header.version == "0.1.0")
    #expect(header.isKnownFormat)
    #expect(header.size == 36)
    #expect(header.checksum == 0xF02D)
    #expect(header.bytes == fittingHeader)
    let maximum = Data([0xAB, 0xC5, 0x56, 0xAA, 0x0F, 0xA0, 0x12, 0x34]) + Data(repeating: 0, count: 8)
    let decoded = try OticonFittingRead.Header(data: maximum)
    #expect(decoded.version == "2748.341.682")
    #expect(decoded.size == 4000)
    #expect(!decoded.isKnownFormat)
    #expect(throws: OticonFittingRead.DecodeError.malformedHeader) { try OticonFittingRead.Header(data: Data()) }
    #expect(throws: OticonFittingRead.DecodeError.malformedHeader) { try OticonFittingRead.Header(data: fittingHeader + Data([0])) }
    var oversized = maximum; oversized[5] = 0xA1
    #expect(throws: OticonFittingRead.DecodeError.invalidPayloadSize) { try OticonFittingRead.Header(data: oversized) }
}

@Test func fittingCRCUsesAugmentedPolynomialAndMeaningfulBytesOnly() {
    #expect(OticonFittingRead.checksum(Data()) == 0x1D0F)
    #expect(OticonFittingRead.checksum(Data("123456789".utf8)) == 0xE5CC)
    #expect(OticonFittingRead.checksum(Data([0])) == 0xCC9C)
    #expect(OticonFittingRead.checksum(Data([0xFF])) == 0xD26C)
    #expect(OticonFittingRead.checksum(Data((0...255).map { UInt8($0) })) == 0x3C8E)
    #expect(OticonFittingRead.checksum(fittingBlob) == 0xF02D)
}

@Test func fittingRecordRequiresLengthChecksumAndStableFullHeader() throws {
    #expect(try OticonFittingRead.validateRecord(header: fittingHeader, payload: fittingBlob,
                                               repeatedHeader: fittingHeader) == fittingHeader + fittingBlob)
    var changedHeader = fittingHeader; changedHeader[15] ^= 1
    #expect(throws: OticonFittingRead.DecodeError.headerChanged) {
        try OticonFittingRead.validateRecord(header: fittingHeader, payload: fittingBlob, repeatedHeader: changedHeader)
    }
    #expect(throws: OticonFittingRead.DecodeError.payloadLengthMismatch) {
        try OticonFittingRead.validateRecord(header: fittingHeader, payload: Data(fittingBlob.dropLast()))
    }
    // Fixed vector padding is not part of Size or the checksum or this record.
    #expect(throws: OticonFittingRead.DecodeError.payloadLengthMismatch) {
        try OticonFittingRead.validateRecord(header: fittingHeader, payload: fittingBlob + Data(repeating: 0, count: 3964))
    }
    var corrupt = fittingBlob; corrupt[20] ^= 1
    #expect(throws: OticonFittingRead.DecodeError.checksumMismatch) {
        try OticonFittingRead.validateRecord(header: fittingHeader, payload: corrupt)
    }
    var unknown = fittingHeader; unknown[3] = 1
    #expect(try OticonFittingRead.validateRecord(header: unknown, payload: fittingBlob) == unknown + fittingBlob)
    #expect(throws: OticonFittingRead.DecodeError.unsupportedFormat) {
        try OticonFittingRead.decodeBlob(fittingBlob, header: OticonFittingRead.Header(data: unknown), hiidVersion: "4.5")
    }
}

@Test func fittingPayloadChunksCoverExactlyDeclaredBytes() throws {
    let chunks = try OticonFittingRead.payloadChunks(size: 4000)
    #expect(chunks.map(\.offset) == [16, 966, 1916, 2866, 3816])
    #expect(chunks.map(\.length) == [950, 950, 950, 950, 200])
    #expect(try OticonFittingRead.payloadChunks(size: 0).isEmpty)
    #expect(try OticonFittingRead.payloadChunks(size: 951).map(\.length) == [950, 1])
    for size in [-1, 4001, Int.max] {
        #expect(throws: OticonFittingRead.DecodeError.invalidPayloadSize) { try OticonFittingRead.payloadChunks(size: size) }
    }
}

@Test func fittingBlobKeepsGuidOrderAndSeparatesLittleEndianSections() throws {
    let header = try OticonFittingRead.Header(data: fittingHeader)
    let blob = try OticonFittingRead.decodeBlob(fittingBlob, header: header, hiidVersion: "4.5")
    #expect(blob.fittingIDBytes == Data((0..<16).map { UInt8($0) }))
    #expect(blob.selection == Data([1, 2, 3, 4, 5, 6]))
    #expect(blob.prodRegs == Data([5, 0, 29, 0xFF, 0xA5]))
    #expect(blob.prodRegsVersionBytes == Data([5, 0, 29, 0xFF]))
    #expect(blob.businessData == Data([0xDE, 0xAD, 0xBE]))
    #expect(throws: OticonFittingRead.DecodeError.unsupportedHIIDVersion) {
        try OticonFittingRead.decodeBlob(fittingBlob, header: header, hiidVersion: "4.6")
    }
}

@Test func fittingBlobRejectsTruncationSwappedLengthsAndTrailingData() throws {
    var swapped = fittingBlob; swapped[16] = 0; swapped[17] = 6
    var shortSelection = fittingBlob; shortSelection[16] = 5
    var oversizedSection = fittingBlob; oversizedSection[24] = 0xFF; oversizedSection[25] = 0xFF
    for invalid in [Data(), Data(fittingBlob.prefix(15)), Data(fittingBlob.dropLast()),
                    swapped, shortSelection, oversizedSection, fittingBlob + Data([0])] {
        let crc = OticonFittingRead.checksum(invalid)
        let header = Data([0, 0, 4, 0, UInt8(invalid.count >> 8), UInt8(invalid.count & 0xFF),
                           UInt8(crc >> 8), UInt8(crc & 0xFF)]) + Data(repeating: 0, count: 8)
        #expect(throws: OticonFittingRead.DecodeError.malformedBlob) {
            try OticonFittingRead.decodeBlob(invalid, header: OticonFittingRead.Header(data: header), hiidVersion: "4.5")
        }
    }
}
