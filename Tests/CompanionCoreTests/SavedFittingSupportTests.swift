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
