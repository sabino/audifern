import Foundation
import Testing
@testable import CompanionCore

private func consumerEQMetadata(_ frequencies: [Double]?) -> Data {
    var bytes = Data([frequencies == nil ? 0xA1 : 0xA2, 0x68]) + Data("stepsize".utf8) + Data([0xF9, 0x34, 0])
    if let frequencies {
        bytes += Data([0x65]) + Data("freqs".utf8) + Data([0x80 + UInt8(frequencies.count)])
        for frequency in frequencies {
            bytes.append(0xFB)
            for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: frequency.bitPattern >> shift)) }
        }
    }
    return bytes
}

@Test func consumerChannelEQPreservesSevenUntouchedCoefficientsAndUsesEachReportedRange() throws {
    let original = [-9, 2, 11, 5, -1, 8, 7, -6]
    let equalizer = try OticonEqualizer.State(rawSteps: original,
        minimumSteps: [-10, -4, -6, -8, -2, -9, -8, -7],
        maximumSteps: [3, 6, 12, 10, 5, 11, 9, 8], stepDB: 0.25)
    #expect(try equalizer.steps(forChannelDB: equalizer.channelDB) == original)
    for channel in 0..<8 {
        var edited = equalizer.channelDB
        edited[channel] += equalizer.stepDB
        var expected = original
        expected[channel] += 1
        #expect(try equalizer.steps(forChannelDB: edited) == expected)
    }
    #expect(equalizer.channelRangesDB[0] == -2.5...0.75)
    #expect(equalizer.channelRangesDB[2] == -1.5...3)
    var invalid = equalizer.channelDB
    invalid[0] = 1
    #expect(throws: OticonEqualizer.EQError.outOfRange) { try equalizer.steps(forChannelDB: invalid) }
}

@Test func consumerChannelEQRejectsMalformedAndNonfiniteRequestsBeforeQuantization() throws {
    let equalizer = try OticonEqualizer.State(rawSteps: .init(repeating: 0, count: 8),
        minimumSteps: .init(repeating: -12, count: 8), maximumSteps: .init(repeating: 12, count: 8), stepDB: 0.5)
    for count in [0, 3, 7, 9] {
        #expect(throws: OticonEqualizer.EQError.malformed) {
            try equalizer.steps(forChannelDB: .init(repeating: 0, count: count))
        }
    }
    for value in [Double.nan, .infinity, -.infinity] {
        var values = equalizer.channelDB
        values[6] = value
        #expect(throws: OticonEqualizer.EQError.malformed) { try equalizer.steps(forChannelDB: values) }
    }
    var values = equalizer.channelDB
    values[7] = Double.greatestFiniteMagnitude
    #expect(throws: OticonEqualizer.EQError.outOfRange) { try equalizer.steps(forChannelDB: values) }
    #expect(try equalizer.steps(forChannelDB: [0.25, 0.75, 1.25, 1.75, -0.25, -0.75, -1.25, -1.75])
            == [0, 2, 2, 4, 0, -2, -2, -4])
}

@Test func consumerEQKeepsReportedFrequencyOrderAndPreservesValidControlsWithoutLabels() throws {
    let frequencies = [250.0, 500, 1000, 2000, 3000, 4000, 6000, 8000]
    let metadata = try UTLAdvanced.equalizerMetadata(consumerEQMetadata(frequencies))
    #expect(metadata.stepDB == 0.25 && metadata.frequenciesHz == frequencies)
    #expect(try UTLAdvanced.equalizerInfo(consumerEQMetadata(frequencies)) == 0.25)
    #expect(try UTLAdvanced.equalizerMetadata(consumerEQMetadata(nil)).frequenciesHz == nil)
    var legacyInfo = consumerEQMetadata(frequencies)
    // Same synthetic frequency map without a step field. Version1 readers use
    // the historical scale; version2 still requires its reported scale.
    legacyInfo = Data([0xA1]) + legacyInfo.dropFirst(13)
    let legacy = try UTLAdvanced.equalizerMetadata(legacyInfo, legacyConsumerScale: true)
    #expect(legacy.stepDB == OticonEqualizer.defaultStepDB && legacy.frequenciesHz == frequencies)
    #expect(throws: OticonEqualizer.EQError.malformed) { try UTLAdvanced.equalizerMetadata(legacyInfo) }
    var duplicate = frequencies; duplicate[1] = duplicate[0]
    var unordered = frequencies; unordered.swapAt(2, 3)
    var nonfinite = frequencies; nonfinite[3] = .nan
    var outside = frequencies; outside[7] = 50_000
    for invalid in [Array(frequencies.dropLast()), frequencies + [9000], duplicate, unordered, outside] {
        let metadata = try UTLAdvanced.equalizerMetadata(consumerEQMetadata(invalid))
        #expect(metadata.stepDB == 0.25 && metadata.frequenciesHz == nil)
    }
    // The shared wire decoder rejects nonfinite CBOR numbers before metadata
    // extraction. Optional labels cannot bypass that existing format boundary.
    #expect(throws: (any Error).self) { try UTLAdvanced.equalizerMetadata(consumerEQMetadata(nonfinite)) }
}

@Test func consumerSnapshotsPreserveOptionalFrequencyLabelsAndKeepOldArchivesReadable() throws {
    let frequencies = [250.0, 500, 1000, 2000, 3000, 4000, 6000, 8000]
    let equalizer = try OticonEqualizer.State(rawSteps: .init(repeating: 0, count: 8),
        minimumSteps: .init(repeating: -12, count: 8), maximumSteps: .init(repeating: 12, count: 8),
        stepDB: 0.25, frequenciesHz: frequencies)
    let program = try ConsumerProgramSnapshot.Program(programID: 0, name: "Synthetic", category: 0,
        boostable: false, tinnitus: false)
    let snapshot = try ConsumerProgramSnapshot(aids: [.init(side: .left, program: program,
        microphoneEqualizer: .init(state: equalizer))])
    #expect(try ConsumerProgramSnapshot.decode(snapshot.encoded()).aids[0].microphoneEqualizer?.frequenciesHz == frequencies)
    var root = try #require(JSONSerialization.jsonObject(with: snapshot.encoded()) as? [String: Any])
    var aids = try #require(root["aids"] as? [[String: Any]])
    var eq = try #require(aids[0]["microphoneEqualizer"] as? [String: Any])
    eq.removeValue(forKey: "frequenciesHz")
    aids[0]["microphoneEqualizer"] = eq; root["aids"] = aids
    #expect(try ConsumerProgramSnapshot.decode(JSONSerialization.data(withJSONObject: root)).aids[0].microphoneEqualizer?.frequenciesHz == nil)
    eq["frequenciesHz"] = Array(repeating: 500, count: 8)
    aids[0]["microphoneEqualizer"] = eq; root["aids"] = aids
    #expect(throws: ConsumerProgramSnapshot.SnapshotError.invalid) {
        try ConsumerProgramSnapshot.decode(JSONSerialization.data(withJSONObject: root))
    }
}
