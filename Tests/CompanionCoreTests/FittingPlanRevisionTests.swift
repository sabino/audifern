import Foundation
import XCTest
@testable import CompanionCore

final class FittingPlanRevisionTests: XCTestCase {
    func testRevisionVerifiesPayloadAndHasOnlyLocalPreparationAuthority() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let plan = FittingWorkspaceDraft(name: "Synthetic revision", updatedAt: date, model: .intent3, rationale: .vacPlus)
        let revision = try FittingPlanRevision(plan, savedAt: date)
        let decoded = try FittingPlanRevision.decode(revision.encoded())
        XCTAssertEqual(decoded.id, revision.id)
        XCTAssertEqual(try decoded.verifiedPlan(), plan)
        XCTAssertEqual(decoded.scope, "local-fitting-plan-revision")
        XCTAssertFalse(try decoded.verifiedPlan().capabilities.canWriteFittedPrograms)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: revision.encoded()) as? [String: Any])
        object["payload"] = try FittingWorkspaceDraft(name: "Changed payload").encoded().base64EncodedString()
        XCTAssertThrowsError(try FittingPlanRevision.decode(JSONSerialization.data(withJSONObject: object))) {
            XCTAssertEqual($0 as? FittingPlanRevision.RevisionError, .digestMismatch)
        }
        for (key, value) in [("scope", "clinical-fitting" as Any), ("schemaVersion", 2 as Any)] {
            var invalid = try XCTUnwrap(JSONSerialization.jsonObject(with: revision.encoded()) as? [String: Any])
            invalid[key] = value
            XCTAssertThrowsError(try FittingPlanRevision.decode(JSONSerialization.data(withJSONObject: invalid)))
        }
        XCTAssertThrowsError(try FittingPlanRevision.decode(Data(repeating: 0, count: FittingPlanRevision.maximumBytes + 1)))
    }

    func testComparisonIgnoresSaveTimeAndFindsEveryPreparationSection() {
        let before = FittingWorkspaceDraft(updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        var after = before; after.updatedAt = after.updatedAt.addingTimeInterval(90)
        XCTAssertTrue(FittingPlanComparison(before, after).isUnchanged)
        after.name = "Different name"; after.model = .intent3; after.ears = .left
        after.patientLabel = "Example"; after.leftAcoustics.receiver = "Left speaker"
        after.rightAcoustics.coupling = .openDome; after.audiogramID = UUID()
        after.rationale = .vacPlus; after.adaptation = .step2; after.programs = [.init(name: "Music", purpose: .music)]
        XCTAssertEqual(FittingPlanComparison(before, after).changedSections, FittingPlanComparison.Section.allCases)
        XCTAssertEqual(FittingPlanComparison(after, before).changedSections, FittingPlanComparison.Section.allCases)
    }

    func testComparisonTracksProgramContentOrderAndIdentity() {
        var before = FittingWorkspaceDraft(programs: [.init(name: "Everyday"), .init(name: "Music", purpose: .music)])
        var after = before; after.programs.reverse()
        XCTAssertEqual(FittingPlanComparison(before, after).changedSections, [.programs])
        after = before; after.programs[0].notes = "Synthetic notes"
        XCTAssertEqual(FittingPlanComparison(before, after).changedSections, [.programs])
        after = before; after.id = UUID()
        XCTAssertEqual(FittingPlanComparison(before, after).changedSections, [.plan])
        before.programs[0].id = UUID()
        XCTAssertEqual(FittingPlanComparison(before, after).changedSections, [.plan, .programs])
    }

    func testArchiveKeepsSubsecondChronologyForSuccessiveSaves() throws {
        let plan = FittingWorkspaceDraft()
        let first = try FittingPlanRevision(plan, savedAt: Date(timeIntervalSince1970: 1_800_000_000.125))
        let second = try FittingPlanRevision(plan, savedAt: Date(timeIntervalSince1970: 1_800_000_000.375))
        let a = try FittingPlanRevision.decode(first.encoded())
        let b = try FittingPlanRevision.decode(second.encoded())
        XCTAssertEqual(a.savedAt, first.savedAt)
        XCTAssertEqual(b.savedAt, second.savedAt)
        XCTAssertLessThan(a.savedAt, b.savedAt)
    }
}
