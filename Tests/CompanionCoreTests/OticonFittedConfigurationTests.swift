import Foundation
import Testing
@testable import CompanionCore

private let fittedIdentity = OticonFittedConfiguration.Identity(
    modelUID: 8513, genericModelUID: 8460, hiidVersion: "4.5",
    releasePackageVersion: "5.0.29", runtimeMemoryMapVersion: "10.0.0")

// Entirely invented bytes. Fixed field offsets exercise the reader independently
// of its cursor, skip blocks, scalar readers and model-selection implementation.
private struct SyntheticFitting {
    var data: Data
    let generalOffset: Int
    let labelOffset: Int
    let firstProgramOffset: Int
    let gainOffset: Int

    init(accessories: Bool = false) {
        let directory: [(Int, Int)] = accessories ? [(0, 0), (6, 19), (4, 20)] : [(0, 0)]
        generalOffset = 32 + 4 + directory.count * 9
        labelOffset = generalOffset + 3002
        firstProgramOffset = generalOffset + 7447
        gainOffset = firstProgramOffset + 1762
        let bitCount = firstProgramOffset + 4405 + (accessories ? 38 : 0)
        data = Data(repeating: 0, count: (bitCount + 7) / 8)
        data.replaceSubrange(0..<4, with: [0xFF, 0xFF, 0xFF, 0xFF])
        set(directory.count, width: 4, at: 32)
        for (index, entry) in directory.enumerated() {
            set(entry.0, width: 4, at: 36 + index * 9)
            set(entry.1, width: 5, at: 40 + index * 9)
        }
        set(75, width: 8, at: generalOffset + 4) // Current step 1 + 75/100.
        setString("Ação", at: labelOffset)
        set(78, width: 8, at: firstProgramOffset) // Adaptation [0][0] = 0.
        set(79, width: 8, at: firstProgramOffset + 768 + 95 * 8)
        set(1, width: 1, at: firstProgramOffset + 1536) // Feedback enabled.
        set(93, width: 8, at: gainOffset) // First map coordinate = 93 - 78.
        set(99, width: 8, at: gainOffset + 26 * 8) // Row 1, channel 2.
        set(150, width: 8, at: gainOffset + 768 + 192) // First MPO = 72.
        set(255, width: 8, at: gainOffset + 768 + 192 + 23 * 8)
        set(2, width: 2, at: gainOffset + 1928) // Fast compression ordinal.
    }

    mutating func set(_ value: Int, width: Int, at offset: Int) {
        for bit in 0..<width {
            let index = (offset + bit) / 8
            let mask = UInt8(1 << ((offset + bit) % 8))
            data[index] &= ~mask
            if value & (1 << bit) != 0 { data[index] |= mask }
        }
    }

    mutating func setString(_ value: String, at offset: Int) {
        let bytes = Array(value.utf8)
        set(bytes.count, width: 5, at: offset)
        for (index, byte) in bytes.enumerated() { set(Int(byte), width: 8, at: offset + 5 + index * 8) }
    }

    func blob(selection: Data = Data([0, 1, 2, 3, 4, 5])) -> OticonFittingRead.Blob {
        OticonFittingRead.Blob(fittingIDBytes: Data(repeating: 0, count: 16),
                              selection: selection, prodRegs: data, businessData: Data())
    }
}

@Test func fittedConfigurationDecodesSyntheticMatrixOrderAndScalarOffsets() throws {
    let fixture = SyntheticFitting()
    let result = try OticonFittedConfiguration.decode(blob: fixture.blob(), identity: fittedIdentity)
    #expect(result.programs.count == 1)
    #expect(result.userPrograms.count == 1)
    #expect(result.accessoryPrograms.isEmpty)
    #expect(result.selection.earPieceCode == 0)
    #expect(result.selection.fittedSideCode == 5)
    #expect(result.adaptation.mode == .manual)
    #expect(result.adaptation.startStep == 1)
    #expect(result.adaptation.currentStep == 1.75)
    #expect(result.adaptation.endStep == 1)
    #expect(result.programLabels[0] == "Ação")
    let program = try #require(result.userPrograms.first)
    #expect(program.slot == .p1)
    #expect(program.category == .listening)
    #expect(program.displayName == "Ação")
    let gain = try #require(program.gain)
    #expect(gain.map.count == 4)
    #expect(gain.map.allSatisfy { $0.count == 24 })
    #expect(gain.map[0][0] == 15)
    #expect(gain.map[1][2] == 21)
    #expect(gain.map[3][23] == -78)
    #expect(gain.mpo.count == 24)
    #expect(gain.mpo[0] == 72)
    #expect(gain.mpo[23] == 177)
    #expect(gain.kneePoints.count == 4)
    #expect(gain.compressionSpeedOrdinal == 2)
    #expect(program.adaptation?.currentStepChange[0][0] == 0)
    #expect(program.adaptation?.prescribedStepChange[3][23] == 1)
    #expect(program.feedback?.isEnabled == true)
    #expect(result.consumedBitCount == 11897)
    #expect(result.paddingBitCount == 7)
    #expect(!result.opaqueFields.isEmpty)
}

@Test func fittedConfigurationSeparatesUserAndAccessoryRecordsAndTemplatePresence() throws {
    let result = try OticonFittedConfiguration.decode(blob: SyntheticFitting(accessories: true).blob(),
                                                     identity: fittedIdentity)
    #expect(result.userPrograms.map(\.slot) == [.p1])
    #expect(result.accessoryPrograms.map(\.slot) == [.television, .automaticPhone])
    #expect(result.accessoryPrograms.map(\.category) == [.television, .telephone])
    #expect(result.accessoryPrograms.allSatisfy { $0.gain == nil && $0.adaptation == nil })
    #expect(result.accessoryPrograms[0].opaqueFields.map(\.bitCount) == [18, 2])
    #expect(result.accessoryPrograms[1].opaqueFields.map(\.bitCount) == [18])
    #expect(result.consumedBitCount == 11953)
    #expect(result.paddingBitCount == 7)
}

@Test func fittedConfigurationRequiresTheResearchedIdentityAndNullVersion() throws {
    let fixture = SyntheticFitting()
    let wrongIdentities = [
        OticonFittedConfiguration.Identity(modelUID: 8512, genericModelUID: 8460, hiidVersion: "4.5", releasePackageVersion: "5.0.29", runtimeMemoryMapVersion: "10.0.0"),
        .init(modelUID: 8513, genericModelUID: 0, hiidVersion: "4.5", releasePackageVersion: "5.0.29", runtimeMemoryMapVersion: "10.0.0"),
        .init(modelUID: 8513, genericModelUID: 8460, hiidVersion: "4.6", releasePackageVersion: "5.0.29", runtimeMemoryMapVersion: "10.0.0"),
        .init(modelUID: 8513, genericModelUID: 8460, hiidVersion: "4.5", releasePackageVersion: "5.0.30", runtimeMemoryMapVersion: "10.0.0"),
        .init(modelUID: 8513, genericModelUID: 8460, hiidVersion: "4.5", releasePackageVersion: "5.0.29", runtimeMemoryMapVersion: "11.0.0")
    ]
    for identity in wrongIdentities {
        #expect(!identity.isSupported)
        #expect(throws: OticonFittedConfiguration.DecodeError.unsupportedIdentity) {
            try OticonFittedConfiguration.decode(blob: fixture.blob(), identity: identity)
        }
    }
    var versioned = fixture; versioned.data[0] = 5
    #expect(throws: OticonFittedConfiguration.DecodeError.unsupportedVersion) {
        try OticonFittedConfiguration.decode(blob: versioned.blob(), identity: fittedIdentity)
    }
    #expect(throws: OticonFittedConfiguration.DecodeError.malformedSelection) {
        try OticonFittedConfiguration.decode(blob: fixture.blob(selection: Data(repeating: 0, count: 5)), identity: fittedIdentity)
    }
}

@Test func fittedConfigurationRejectsUnknownAndDuplicateDirectoryEntries() throws {
    for (offset, width, value) in [(32, 4, 0), (32, 4, 12), (36, 4, 15), (40, 5, 31)] {
        var invalid = SyntheticFitting()
        invalid.set(value, width: width, at: offset)
        #expect(throws: OticonFittedConfiguration.DecodeError.invalidProgramDirectory) {
            try OticonFittedConfiguration.decode(blob: invalid.blob(), identity: fittedIdentity)
        }
    }
    var duplicate = SyntheticFitting(accessories: true)
    duplicate.set(0, width: 4, at: 45)
    #expect(throws: OticonFittedConfiguration.DecodeError.invalidProgramDirectory) {
        try OticonFittedConfiguration.decode(blob: duplicate.blob(), identity: fittedIdentity)
    }
}

@Test func fittedConfigurationRejectsInvalidScalarsStringsAndReservedBits() throws {
    let original = SyntheticFitting()
    for (offset, width, value) in [(original.generalOffset, 2, 3),
                                  (original.generalOffset + 2, 2, 3),
                                  (original.generalOffset + 4, 8, 201),
                                  (original.gainOffset + 1928, 2, 3),
                                  (original.labelOffset + 1715, 1, 1)] {
        var invalid = original
        invalid.set(value, width: width, at: offset)
        #expect(throws: OticonFittedConfiguration.DecodeError.invalidValue) {
            try OticonFittedConfiguration.decode(blob: invalid.blob(), identity: fittedIdentity)
        }
    }
    var badUTF8 = original
    badUTF8.set(0xFF, width: 8, at: original.labelOffset + 5)
    var badStringPadding = original
    badStringPadding.set(1, width: 8, at: original.labelOffset + 5 + 29 * 8)
    for invalid in [badUTF8, badStringPadding] {
        #expect(throws: OticonFittedConfiguration.DecodeError.invalidString) {
            try OticonFittedConfiguration.decode(blob: invalid.blob(), identity: fittedIdentity)
        }
    }
}

@Test func fittedConfigurationRejectsTruncationNonzeroPaddingAndExtraBytes() throws {
    let original = SyntheticFitting()
    var short = original; short.data.removeLast()
    #expect(throws: OticonFittedConfiguration.DecodeError.truncated) {
        try OticonFittedConfiguration.decode(blob: short.blob(), identity: fittedIdentity)
    }
    var nonzeroPadding = original
    nonzeroPadding.data[nonzeroPadding.data.count - 1] |= 0x80
    var extra = original; extra.data.append(0)
    for invalid in [nonzeroPadding, extra] {
        #expect(throws: OticonFittedConfiguration.DecodeError.invalidPadding) {
            try OticonFittedConfiguration.decode(blob: invalid.blob(), identity: fittedIdentity)
        }
    }
}
