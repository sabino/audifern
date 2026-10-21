import Foundation
import Testing
@testable import CompanionCore

@Test func savedFittingAcquisitionAndDecodeShareTheExactResearchedIdentityGate() {
    func identity(model: String = "Intent 3", hiid: String = "4.5", release: String = "5.0.29",
                  map: String = "10.0.0") -> DeviceBackup.Identity {
        .init(peripheralID: UUID(), model: model, hiidVersion: hiid,
              releasePackageVersion: release, runtimeMemoryMapVersion: map)
    }
    #expect(SavedFitting.supports(identity()))
    #expect(SavedFitting.supports(identity(model: "Oticon Intent 3")))
    #expect(!SavedFitting.supports(identity(model: "Intent 1")))
    #expect(!SavedFitting.supports(identity(release: "5.0.30")))
    #expect(!SavedFitting.supports(identity(hiid: "4.6")))
    #expect(!SavedFitting.supports(identity(map: "10.0.1")))
    #expect(!SavedFitting.supports(.init(peripheralID: UUID())))
}

private func savedFittingSyntheticIdentification(modelUID: UInt32 = 8513,
    genericUID: UInt32 = 8460, model: String = "Intent 3", release: UInt8 = 29, map: UInt8 = 10) -> Data {
    var product = [UInt8](repeating: 0, count: 28)
    for (offset, value) in [(4, modelUID), (9, genericUID)] {
        for byte in 0..<4 { product[offset + byte] = UInt8(truncatingIfNeeded: value >> (24 - byte * 8)) }
    }
    var name = Data(repeating: 0, count: 54)
    name.replaceSubrange(18..<(18 + model.utf8.count), with: model.utf8)
    let fields: [(UInt16, Data)] = [(1001, Data([4, 5])), (1002, Data(product)),
        (1003, Data(repeating: 0, count: 20)), (1012, Data([map, 0, 0, 5, 0, release])), (2009, name)]
    return fields.reduce(Data([0xA5])) { bytes, field in
        bytes + Data([0x19, UInt8(field.0 >> 8), UInt8(field.0 & 255)])
            + (field.1.count < 24 ? Data([0x40 + UInt8(field.1.count)]) : Data([0x58, UInt8(field.1.count)])) + field.1
    }
}

@Test func savedFittingRawIdentityRejectsContradictoryOrIncompleteDecoderSelections() {
    let identity = DeviceBackup.Identity(peripheralID: UUID(), model: "Oticon Intent 3", hiidVersion: "4.5",
        releasePackageVersion: "5.0.29", runtimeMemoryMapVersion: "10.0.0")
    func supported(_ raw: Data?) -> Bool {
        SavedFitting.supports(DeviceBackup.Aid(side: .left, identity: identity, identification: raw))
    }
    #expect(supported(nil)) // Pre-existing archives remain readable.
    #expect(supported(savedFittingSyntheticIdentification()))
    #expect(!supported(savedFittingSyntheticIdentification(modelUID: 8511)))
    #expect(!supported(savedFittingSyntheticIdentification(genericUID: 8459)))
    #expect(!supported(savedFittingSyntheticIdentification(model: "Intent 1")))
    #expect(!supported(savedFittingSyntheticIdentification(release: 30)))
    #expect(!supported(savedFittingSyntheticIdentification(map: 11)))
    #expect(!supported(Data([0xA1, 0x19, 3, 0xE9, 0x42, 4, 5])))
}

@Test func backupRejectsOverlappingRawIdentityConflictsButAcceptsKnownModelAlias() throws {
    let identity = DeviceBackup.Identity(peripheralID: UUID(), model: "Oticon Intent 3", hiidVersion: "4.5",
        releasePackageVersion: "5.0.29", runtimeMemoryMapVersion: "10.0.0")
    let program = try ConsumerProgramSnapshot.Program(programID: 0, name: "Synthetic", category: 0,
        boostable: false, tinnitus: false)
    let consumer = try ConsumerProgramSnapshot(aids: [.init(side: .left, program: program)])
    func archive(_ raw: Data) throws -> DeviceBackup {
        try DeviceBackup(consumerControls: consumer, aids: [.init(side: .left, identity: identity, identification: raw)])
    }
    #expect(try archive(savedFittingSyntheticIdentification()).aids.count == 1)
    for raw in [savedFittingSyntheticIdentification(model: "Intent 1"),
                savedFittingSyntheticIdentification(release: 30), savedFittingSyntheticIdentification(map: 11)] {
        #expect(throws: DeviceBackup.BackupError.invalid) { try archive(raw) }
    }
}

@Test func savedAudiogramReviewRequiresExternalUnitConfirmationAndPreservesResponseConditions() throws {
    // A synthetic BL block with two ordinary AC responses, one no-response,
    // one uncertain point and an absent point carrying an ordinary tag.
    var data = Data([0x42, 0x4C, 0, 0, 0])
    data += Data(repeating: 0, count: 7) // three version shorts and prerelease
    data += Data([10, 20, 30, 40, 0x80] + Array(repeating: 0x80, count: 6))
    data += Data([0, 3, 1, 6, 0] + Array(repeating: 0x80, count: 6))
    data += Data(repeating: 0x80, count: 44) // absent BC/UCL
    data += Data(repeating: 0, count: 42) // real-ear fields
    data += Data(repeating: 0, count: 500 - data.count)
    let snapshot = try OticonBusinessData.decode(data)
    #expect(throws: OticonBusinessData.ReviewError.unitsUnconfirmed) {
        try OticonBusinessData.thresholdsForReview(snapshot, ear: .left, confirmedDBHL: false)
    }
    let points = try OticonBusinessData.thresholdsForReview(snapshot, ear: .left, confirmedDBHL: true)
    #expect(points.count == 2)
    #expect(points.allSatisfy { $0.key.ear == .left && $0.key.conduction == .air && !$0.noResponse })
    #expect(points[0].key.frequencyHz == 125 && points[0].levelDBHL == 10 && !points[0].key.masked)
    #expect(points[1].key.frequencyHz == 250 && points[1].levelDBHL == 20 && points[1].key.masked)
    let draft = try Audiogram(name: "Synthetic stored fitting", thresholds: points).validated()
    #expect(draft.examDate == nil)
    #expect(snapshot.airConduction.points[2].tag == .unmaskedNoResponse)
    #expect(snapshot.airConduction.points[2].level == 30)
}
