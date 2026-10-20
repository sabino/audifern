import XCTest
@testable import CompanionCore

final class OticonRemoteProtocolTests: XCTestCase {
    func testSignedVolumeAndMutePolarityDifferFromStandardVCS() throws {
        let vendor = try XCTUnwrap(OticonRemoteProtocol.Volume(data: Data([0xFF, 0])))
        XCTAssertEqual(vendor.level, -1)
        XCTAssertTrue(vendor.muted)
        let standard = try XCTUnwrap(BluetoothVolumeState(data: Data([255, 0, 7])))
        XCTAssertEqual(standard.volume, 255)
        XCTAssertFalse(standard.muted)
        XCTAssertEqual(standard.changeCounter, 7)
    }

    func testPayloadUsesSignedByteAndReportedRange() {
        XCTAssertEqual(OticonRemoteProtocol.volumePayload(level: -3, muted: false, reportedRange: -5...5), Data([0xFD, 1]))
        XCTAssertNil(OticonRemoteProtocol.volumePayload(level: 6, muted: false, reportedRange: -5...5))
        XCTAssertNil(OticonRemoteProtocol.volumePayload(level: 128, muted: false, reportedRange: 0...255))
    }

    func testRangesRejectTruncationAndReversedBounds() throws {
        let ranges = try XCTUnwrap(OticonRemoteProtocol.VolumeRanges(data: Data([0xF8, 4, 0xF0, 8, 0xFC, 2])))
        XCTAssertEqual(ranges.main, -8...4)
        XCTAssertEqual(ranges.streaming, -16...8)
        XCTAssertEqual(ranges.tinnitus, -4...2)
        XCTAssertNil(OticonRemoteProtocol.VolumeRanges(data: Data([1, 0, 0, 1, 0, 1])))
        XCTAssertNil(OticonRemoteProtocol.VolumeRanges(data: Data([0, 1])))
    }

    func testMalformedVolumeNeverBecomesControlState() {
        for data in [Data(), Data([1]), Data([1, 2]), Data([1, 0, 0])] {
            XCTAssertNil(OticonRemoteProtocol.Volume(data: data))
        }
        XCTAssertNil(BluetoothVolumeState(data: Data([0, 2, 1])))
        XCTAssertNil(BluetoothVolumeState(data: Data([0, 1])))
    }

    func testProgramBitmapAndOnlyReportedProgramsAreSelectable() {
        XCTAssertEqual(OticonRemoteProtocol.programIDs(bitmap: Data([0x05, 0x80])), [0, 2, 15])
        XCTAssertEqual(OticonRemoteProtocol.programPayload(id: 2, reportedPrograms: [0, 2]), Data([2]))
        XCTAssertNil(OticonRemoteProtocol.programPayload(id: 1, reportedPrograms: [0, 2]))
        XCTAssertNil(OticonRemoteProtocol.programIDs(bitmap: Data()))
    }
}
