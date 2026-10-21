import Foundation
import Testing
@testable import CompanionCore

private let acousticIdentity = OticonFittedConfiguration.Identity(
    modelUID: 8513, genericModelUID: 8460, hiidVersion: "4.5",
    releasePackageVersion: "5.0.29", runtimeMemoryMapVersion: "10.0.0")

private func acousticSelection(earpiece: UInt8 = 0, hook: UInt8 = 0, vent: UInt8 = 0,
                               tubing: UInt8 = 0, level: UInt8 = 0, side: UInt8 = 0) -> OticonFittedConfiguration.Selection {
    .init(earPieceCode: earpiece, hookCode: hook, ventCode: vent, tubingCode: tubing,
          fittingLevelAcousticsCode: level, fittedSideCode: side)
}

private func acousticValues(_ labels: OticonSavedAcoustics.Labels) -> [OticonSavedAcoustics.Value] {
    [labels.earpiece, labels.hook, labels.vent, labels.tubing, labels.fittingLevel, labels.fittedSide]
}

@Test func savedAcousticsUsesExplicitWireValuesRatherThanUIPositions() throws {
    // Invented combination chosen to exercise nonsequential enumeration values;
    // it is not a captured fitting or a claim of acoustic compatibility.
    let labels = try OticonSavedAcoustics.decode(acousticSelection(
        earpiece: 17, hook: 8, vent: 31, tubing: 7, level: 4, side: 2), identity: acousticIdentity)
    #expect(labels.earpiece.identifier == "CustomEarpieceIIC")
    #expect(labels.earpiece.label == "Custom earpiece, IIC")
    #expect(labels.hook.identifier == "CordaMiniFitHook")
    #expect(labels.vent.identifier == "CollectionVent1Point2mm")
    #expect(labels.vent.label == "Collection vent, nominal 1.2 mm")
    #expect(labels.tubing.identifier == "None")
    #expect(labels.fittingLevel.identifier == "Level85")
    #expect(labels.fittingLevel.label == "Level 85")
    #expect(labels.fittedSide.identifier == "Right")
    #expect(acousticValues(labels).map(\.rawCode) == [17, 8, 31, 7, 4, 2])
    let lowLevel = try OticonSavedAcoustics.decode(acousticSelection(level: 8), identity: acousticIdentity)
    #expect(lowLevel.fittingLevel.identifier == "Level45")
}

@Test func savedAcousticsDistinguishesUnspecifiedNoneAndClosedVent() throws {
    let unspecified = try OticonSavedAcoustics.decode(acousticSelection(), identity: acousticIdentity)
    #expect(unspecified.earpiece.identifier == "Undefined")
    #expect(unspecified.earpiece.label == "Not specified")
    #expect(unspecified.vent.identifier == "Undefined")
    #expect(unspecified.fittedSide.identifier == "None")
    #expect(unspecified.fittedSide.label == "Unassigned")
    let none = try OticonSavedAcoustics.decode(acousticSelection(
        earpiece: 20, hook: 1, vent: 30, tubing: 7, level: 20), identity: acousticIdentity)
    #expect(acousticValues(none).allSatisfy { $0.identifier == "None" })
    let closed = try OticonSavedAcoustics.decode(acousticSelection(vent: 1), identity: acousticIdentity)
    #expect(closed.vent.identifier == "ClosedVent")
    #expect(closed.vent.identifier != none.vent.identifier)
}

@Test func savedAcousticsPreservesUnknownCodesWithoutChoosingDefaults() throws {
    for selection in [acousticSelection(earpiece: 255, hook: 255, vent: 255, tubing: 255, level: 255, side: 255),
                      acousticSelection(earpiece: 4, hook: 10, vent: 65, tubing: 8, level: 13, side: 3)] {
        let labels = try OticonSavedAcoustics.decode(selection, identity: acousticIdentity)
        #expect(acousticValues(labels).allSatisfy { !$0.isRecognized && $0.identifier == nil && $0.label == nil })
        #expect(labels.earpiece.rawCode == selection.earPieceCode)
        #expect(labels.fittedSide.rawCode == selection.fittedSideCode)
    }
}

@Test func savedAcousticsRecognizedDomainsRemainDistinctAndBounded() throws {
    var counts = [Int](repeating: 0, count: 6)
    var identifiers = [Set<String>](repeating: [], count: 6)
    for code in UInt8.min...UInt8.max {
        let labels = try OticonSavedAcoustics.decode(acousticSelection(
            earpiece: code, hook: code, vent: code, tubing: code, level: code, side: code), identity: acousticIdentity)
        for (index, value) in acousticValues(labels).enumerated() {
            #expect(value.rawCode == code)
            if let identifier = value.identifier {
                counts[index] += 1
                #expect(identifiers[index].insert(identifier).inserted)
                #expect(value.label?.isEmpty == false)
            } else {
                #expect(value.label == nil)
            }
        }
    }
    #expect(counts == [23, 10, 65, 8, 14, 3])
}

@Test func savedAcousticsRequiresTheExactResearchedProfile() throws {
    for identity in [
        OticonFittedConfiguration.Identity(modelUID: 8512, genericModelUID: 8460, hiidVersion: "4.5", releasePackageVersion: "5.0.29", runtimeMemoryMapVersion: "10.0.0"),
        .init(modelUID: 8513, genericModelUID: 8461, hiidVersion: "4.5", releasePackageVersion: "5.0.29", runtimeMemoryMapVersion: "10.0.0"),
        .init(modelUID: 8513, genericModelUID: 8460, hiidVersion: "4.6", releasePackageVersion: "5.0.29", runtimeMemoryMapVersion: "10.0.0"),
        .init(modelUID: 8513, genericModelUID: 8460, hiidVersion: "4.5", releasePackageVersion: "5.0.30", runtimeMemoryMapVersion: "10.0.0"),
        .init(modelUID: 8513, genericModelUID: 8460, hiidVersion: "4.5", releasePackageVersion: "5.0.29", runtimeMemoryMapVersion: "10.0.1")
    ] {
        #expect(throws: OticonSavedAcoustics.DecodeError.unsupportedIdentity) {
            try OticonSavedAcoustics.decode(acousticSelection(), identity: identity)
        }
    }
}
