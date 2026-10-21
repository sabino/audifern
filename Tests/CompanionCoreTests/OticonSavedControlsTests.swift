import Foundation
import Testing
@testable import CompanionCore

private let savedControlsIdentity = OticonFittedConfiguration.Identity(
    modelUID: 8513, genericModelUID: 8460, hiidVersion: "4.5",
    releasePackageVersion: "5.0.29", runtimeMemoryMapVersion: "10.0.0")

/// Independent synthetic bytes and explicit original-stream offsets. No saved
/// fitting values, extracted definition files or factory settings are included.
private struct SavedControlsFixture {
    var data: Data
    let general = 63 // version32 + directory-count4 + three nine-bit entries
    var listening: Int { general + 7447 }
    var television: Int { listening + 4405 }

    init() {
        data = Data(repeating: 0, count: (63 + 7447 + 4405 + 20 + 18 + 7) / 8)
        data.replaceSubrange(0..<4, with: [0xFF, 0xFF, 0xFF, 0xFF])
        put(3, width: 4, at: 32)
        for (i, entry) in [(0, 0), (6, 19), (4, 20)].enumerated() {
            put(entry.0, width: 4, at: 36 + i * 9)
            put(entry.1, width: 5, at: 40 + i * 9)
        }
        put(8, width: 4, at: general + 334) // configuration index9
        put(6, width: 4, at: general + 338)
        put(4, width: 3, at: general + 342)
        put(1, width: 1, at: general + 345) // retain source Off
        put(2, width: 3, at: general + 346)
        put(1, width: 3, at: general + 349)
        put(4, width: 3, at: general + 352)
        put(3, width: 3, at: general + 355)
        put(1, width: 1, at: listening + 1758) // frequency lowering Off
        put(5, width: 3, at: listening + 3692) // microphone Off
        put(1, width: 1, at: listening + 3695)
        put(4, width: 3, at: listening + 3696)
        put(250, width: 9, at: listening + 3699)
        put(2, width: 2, at: listening + 3708)
        put(5, width: 3, at: listening + 3725) // transient Off
        put(2, width: 2, at: listening + 3729) // wind Off
        put(2, width: 2, at: listening + 3735) // bass Low
        put(1, width: 1, at: listening + 4029) // level steering Off
        put(3, width: 2, at: listening + 4030) // Red
        put(5, width: 3, at: listening + 4032) // Bustling
        put(2, width: 3, at: television)
        put(1, width: 3, at: television + 4)
        put(200, width: 9, at: television + 7)
        put(1, width: 2, at: television + 16)
        put(1, width: 2, at: television + 18) // accessory bass Medium
    }

    mutating func put(_ value: Int, width: Int, at offset: Int) {
        for bit in 0..<width {
            let index = (offset + bit) / 8, mask = UInt8(1 << ((offset + bit) % 8))
            data[index] &= ~mask
            if value & (1 << bit) != 0 { data[index] |= mask }
        }
    }

    func fitting() throws -> OticonFittedConfiguration.Snapshot {
        try OticonFittedConfiguration.decode(blob: .init(fittingIDBytes: Data(repeating: 0, count: 16),
            selection: Data([0, 1, 2, 3, 4, 5]), prodRegs: data, businessData: Data()), identity: savedControlsIdentity)
    }
}

private func replacingSavedControls(_ fitting: OticonFittedConfiguration.Snapshot,
                                    identity: OticonFittedConfiguration.Identity? = nil,
                                    fields: [OticonFittedConfiguration.OpaqueBits]? = nil,
                                    consumed: Int? = nil) -> OticonFittedConfiguration.Snapshot {
    .init(identity: identity ?? fitting.identity, selection: fitting.selection, adaptation: fitting.adaptation,
          programLabels: fitting.programLabels, programs: fitting.programs, opaqueFields: fields ?? fitting.opaqueFields,
          consumedBitCount: consumed ?? fitting.consumedBitCount, paddingBitCount: fitting.paddingBitCount)
}

@Test func savedControlsDecodeSharedChoicesAcrossNonByteAlignedBlocks() throws {
    let fitting = try SavedControlsFixture().fitting()
    let controls = try OticonSavedControls.decode(fitting)
    #expect(fitting.opaqueFields[0].bitOffset % 8 != 0)
    #expect(controls.frequencyLowering.configurationIndex == 9)
    #expect(controls.frequencyLowering.prescribedConfigurationIndex == 6)
    #expect(controls.frequencyLowering.weight.code == 4 && controls.frequencyLowering.weight.label == "Medium raised")
    #expect(!controls.frequencyLowering.retainsSource)
    #expect(controls.streaming.microphoneBalance.label == "−6 dB")
    #expect(controls.streaming.mfiLoudness.label == "+3 dB")
    #expect(controls.streaming.televisionLoudness.label == "−9 dB")
    #expect(controls.streaming.remoteMicrophoneLoudness.label == "−3 dB")
}

@Test func savedControlsDecodeProgramInputsTinnitusAndSwitchPolarity() throws {
    let controls = try OticonSavedControls.decode(SavedControlsFixture().fitting())
    let program = try #require(controls.programs.first)
    #expect(program.slot == .p1 && program.frequencyLoweringEnabled == false)
    #expect(program.sensorFusionEnabled == true && program.bassBoost?.label == "Low")
    #expect(program.inputs.microphone.label == "Off" && program.inputs.auxiliary.label == "Off")
    #expect(program.inputs.wirelessSoundQuality.label == "Brightest")
    #expect(program.inputs.crosBalance == 5)
    #expect(program.inputs.crosSource.label == "Microphone and stream")
    #expect(program.tinnitus?.signalGeneratorEnabled == true)
    #expect(program.tinnitus?.levelSteeringEnabled == false)
    #expect(program.tinnitus?.noiseType.label == "Red" && program.tinnitus?.modulation.label == "Bustling")
    #expect(program.transientControl?.label == "Off" && program.windControl?.label == "Off")
}

@Test func savedControlsSeparateAccessoryFieldsFromListeningTemplateFields() throws {
    let controls = try OticonSavedControls.decode(SavedControlsFixture().fitting())
    let television = try #require(controls.programs.first { $0.slot == .television })
    #expect(television.inputs.microphone.label == "−6 dB")
    #expect(television.inputs.wirelessSoundQuality.label == "Fuller")
    #expect(television.inputs.crosBalance == 0 && television.inputs.crosSource.label == "Stream only")
    #expect(television.bassBoost?.label == "Medium")
    #expect(television.tinnitus == nil && television.frequencyLoweringEnabled == nil && television.sensorFusionEnabled == nil)
    #expect(television.transientControl == nil && television.windControl == nil)
    let telephone = try #require(controls.programs.first { $0.slot == .automaticPhone })
    #expect(telephone.bassBoost == nil && telephone.tinnitus == nil)
}

@Test func savedControlsRetainUnknownOrdinalsWithoutInventingLabels() throws {
    var fixture = SavedControlsFixture()
    fixture.put(7, width: 3, at: fixture.general + 342)
    fixture.put(7, width: 3, at: fixture.general + 349)
    fixture.put(6, width: 3, at: fixture.listening + 3692)
    fixture.put(3, width: 2, at: fixture.listening + 3708)
    fixture.put(6, width: 3, at: fixture.listening + 4032)
    let controls = try OticonSavedControls.decode(fixture.fitting())
    #expect(controls.frequencyLowering.weight.code == 7 && controls.frequencyLowering.weight.label == nil)
    #expect(controls.streaming.mfiLoudness.code == 7 && controls.streaming.mfiLoudness.label == nil)
    #expect(controls.programs[0].inputs.microphone.code == 6 && controls.programs[0].inputs.microphone.label == nil)
    #expect(controls.programs[0].inputs.crosSource.code == 3 && controls.programs[0].inputs.crosSource.label == nil)
    #expect(controls.programs[0].tinnitus?.modulation.code == 6 && controls.programs[0].tinnitus?.modulation.label == nil)
}

@Test func savedControlsRejectUndefinedNumericCoordinatesWithoutChangingOpaqueBytes() throws {
    for (field, width, value) in [(334, 4, 15), (338, 4, 15)] {
        var fixture = SavedControlsFixture()
        fixture.put(value, width: width, at: fixture.general + field)
        let fitting = try fixture.fitting(), before = fitting.opaqueFields
        #expect(throws: OticonSavedControls.DecodeError.invalidValue) { try OticonSavedControls.decode(fitting) }
        #expect(fitting.opaqueFields == before)
    }
    var fixture = SavedControlsFixture()
    fixture.put(511, width: 9, at: fixture.listening + 3699)
    #expect(throws: OticonSavedControls.DecodeError.invalidValue) { try OticonSavedControls.decode(fixture.fitting()) }
}

@Test func savedControlsRequireExactIdentityAndDescriptorGeometry() throws {
    let fitting = try SavedControlsFixture().fitting()
    let unsupported = OticonFittedConfiguration.Identity(modelUID: 8513, genericModelUID: 8460,
        hiidVersion: "4.5", releasePackageVersion: "5.0.30", runtimeMemoryMapVersion: "10.0.0")
    #expect(throws: OticonSavedControls.DecodeError.unsupportedIdentity) {
        try OticonSavedControls.decode(replacingSavedControls(fitting, identity: unsupported))
    }
    let field = fitting.opaqueFields[0]
    var withDuplicate = fitting.opaqueFields; withDuplicate.append(field)
    for fields in [Array(fitting.opaqueFields.dropFirst()), withDuplicate] {
        #expect(throws: OticonSavedControls.DecodeError.missingOrDuplicateBlock) {
            try OticonSavedControls.decode(replacingSavedControls(fitting, fields: fields))
        }
    }
    var highPadding = field.packedBits; highPadding[highPadding.count - 1] |= 0x80
    for replacement in [OticonFittedConfiguration.OpaqueBits(name: field.name, bitOffset: field.bitOffset + 1,
                            bitCount: field.bitCount, packedBits: field.packedBits),
                        .init(name: field.name, bitOffset: field.bitOffset, bitCount: field.bitCount - 1, packedBits: field.packedBits),
                        .init(name: field.name, bitOffset: field.bitOffset, bitCount: field.bitCount, packedBits: highPadding),
                        .init(name: field.name, bitOffset: field.bitOffset, bitCount: field.bitCount, packedBits: field.packedBits + Data([0]))] {
        var fields = fitting.opaqueFields; fields[0] = replacement
        #expect(throws: OticonSavedControls.DecodeError.malformedBlock) {
            try OticonSavedControls.decode(replacingSavedControls(fitting, fields: fields))
        }
    }
    #expect(throws: OticonSavedControls.DecodeError.malformedBlock) {
        try OticonSavedControls.decode(replacingSavedControls(fitting, consumed: fitting.consumedBitCount + 1))
    }
}

@Test func savedControlsHandleDataSlicesInPackedOpaqueBlocks() throws {
    let fitting = try SavedControlsFixture().fitting()
    let baseline = try OticonSavedControls.decode(fitting)
    var fields = fitting.opaqueFields
    let field = fields[0]
    fields[0] = .init(name: field.name, bitOffset: field.bitOffset, bitCount: field.bitCount,
                      packedBits: (Data([0]) + field.packedBits).dropFirst())
    #expect(try OticonSavedControls.decode(replacingSavedControls(fitting, fields: fields)) == baseline)
}
