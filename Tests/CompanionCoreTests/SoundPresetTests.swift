import Foundation
import XCTest
@testable import CompanionCore

final class SoundPresetTests: XCTestCase {
    private func aid(side: SoundPreset.Side = .left) throws -> SoundPreset.Aid {
        try .init(side: side, model: "Test model", programID: 0, volume: -2, muted: false,
                  microphoneSteps: Array(repeating: -4, count: 8), microphoneStepDB: 0.2)
    }

    func testSnapshotRoundTripKeepsSeparateSidesAndAudiogramReference() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let preset = try SoundPreset(name: " Desk ", createdAt: date, updatedAt: date,
                                     audiogramID: UUID(), aids: [aid(), aid(side: .right)])
        let archive = try SoundPresetArchive(presets: [preset])
        XCTAssertEqual(try SoundPresetArchive.decode(archive.encoded()), archive)
        XCTAssertEqual(preset.name, "Desk")
    }

    func testRejectsDuplicateSidesAndInvalidWireValues() throws {
        XCTAssertThrowsError(try SoundPreset(name: "Duplicate", aids: [aid(), aid()]))
        XCTAssertThrowsError(try SoundPreset.Aid(side: .left, model: "Model", programID: 256, volume: 0, muted: false))
        XCTAssertThrowsError(try SoundPreset.Aid(side: .left, model: "Model", programID: 0, volume: 128, muted: false))
        XCTAssertThrowsError(try SoundPreset.Aid(side: .left, model: "Model", programID: 0, volume: 0, muted: false,
                                               microphoneSteps: [0, 1], microphoneStepDB: 0.2))
    }

    func testDecodedArchiveMustValidateRatherThanTrustCodable() throws {
        let preset = try SoundPreset(name: "Snapshot", aids: [aid()])
        let data = try SoundPresetArchive(presets: [preset]).encoded()
        let badVersion = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 99")
        XCTAssertThrowsError(try SoundPresetArchive.decode(Data(badVersion.utf8)))
        var invalid = preset; invalid.aids[0].microphoneSteps = [999]
        XCTAssertThrowsError(try SoundPresetArchive(presets: [invalid]))
        XCTAssertThrowsError(try SoundPresetArchive(presets: [preset, preset]))
    }
}
