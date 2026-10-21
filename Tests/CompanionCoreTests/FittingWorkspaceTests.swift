import Foundation
import XCTest
@testable import CompanionCore

/// Independently authored synthetic planning fixtures. No device or patient data.
final class FittingWorkspaceTests: XCTestCase {
    private func exam(ears: [AudiogramEar] = [.left, .right], noResponse: Bool = false,
                      conduction: AudiogramConduction = .air) -> Audiogram {
        Audiogram(name: "Synthetic exam", thresholds: ears.map {
            .init(key: .init(ear: $0, conduction: conduction, frequencyHz: 1000), levelDBHL: 30, noResponse: noResponse)
        })
    }

    private func completePlan(exam: Audiogram) -> FittingWorkspaceDraft {
        let acoustics = FittingWorkspaceAcoustics(receiver: "Recorded speaker", coupling: .ventedDome,
            ventDescription: "Recorded vent", checkedAgainstRecord: true)
        return .init(name: "Synthetic plan", updatedAt: Date(timeIntervalSince1970: 1_800_000_000), model: .intent3,
            patientLabel: "Example", birthDate: "1980-03-04", experience: .experienced,
            listeningGoals: "Discuss conversation comfort", leftAcoustics: acoustics, rightAcoustics: acoustics,
            audiogramID: exam.id, rationale: .vacPlus, adaptation: .step2,
            programs: [.init(name: "Conversation", purpose: .conversation, notes: "Discuss a busy room")])
    }

    func testPartialPlanRoundTripsWithoutInventingMissingInputs() throws {
        let plan = FittingWorkspaceDraft(updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let restored = try FittingWorkspaceDraft.decode(plan.encoded())
        XCTAssertEqual(restored, plan)
        XCTAssertEqual(restored.model, .notSelected)
        XCTAssertNil(restored.rationale)
        XCTAssertNil(restored.audiogramID)
        XCTAssertEqual(restored.leftAcoustics.coupling, .notRecorded)
        XCTAssertEqual(restored.leftAcoustics.receiver, "")
        XCTAssertFalse(restored.leftAcoustics.checkedAgainstRecord)
        XCTAssertEqual(restored.adaptation, .notSelected)
        XCTAssertTrue(restored.programs.isEmpty)
        XCTAssertEqual(restored.readiness(audiograms: []).completedCount, 0)
    }

    func testIntentProfileHasOnlyMappedRationalesAndNeverEnablesClinicalActions() {
        XCTAssertEqual(FittingWorkspaceModel.intent3.rationales, [.vacPlus, .nalNL1, .nalNL2, .dslAdult, .dslPediatric])
        for model in FittingWorkspaceModel.allCases {
            let capabilities = FittingWorkspaceCapabilities(model: model)
            XCTAssertFalse(capabilities.canGenerateClinicalGains)
            XCTAssertFalse(capabilities.canWriteFittedPrograms)
            XCTAssertFalse(capabilities.canRestoreClinicalFitting)
            if model != .intent3 { XCTAssertTrue(capabilities.rationales.isEmpty) }
        }
        XCTAssertFalse(FittingWorkspaceRationale.allCases.map(\.rawValue).contains("nalNL3"))
    }

    func testCompletePreparationRemainsAPlanAndDoesNotProgram() throws {
        let exam = exam()
        let plan = completePlan(exam: exam)
        let readiness = plan.readiness(audiograms: [exam])
        XCTAssertTrue(readiness.preparationComplete)
        XCTAssertEqual(readiness.completedCount, 6)
        XCTAssertFalse(readiness.canProgramHearingAids)
        XCTAssertEqual(try FittingWorkspaceDraft.decode(plan.encoded()), plan)
        let data = try plan.encoded()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["scope"] as? String, "local-fitting-plan")
        XCTAssertEqual(object["clinicalFittingIncluded"] as? Bool, false)
        for absent in ["gain", "MPO", "wirePayload", "serialNumber", "authentication", "programID"] {
            XCTAssertNil(object[absent])
        }
    }

    func testImportedScopeVersionAndClinicalClaimCannotEscalateCapabilities() throws {
        let valid = try FittingWorkspaceDraft().encoded()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        for (key, value) in [("schemaVersion", 2 as Any), ("scope", "clinical-fitting" as Any), ("clinicalFittingIncluded", true as Any)] {
            var changed = object; changed[key] = value
            XCTAssertThrowsError(try FittingWorkspaceDraft.decode(JSONSerialization.data(withJSONObject: changed))) {
                XCTAssertEqual($0 as? FittingWorkspaceDraft.ValidationError, .unsupportedFormat)
            }
        }
        var extra = object
        extra["canWriteFittedPrograms"] = true
        let restored = try FittingWorkspaceDraft.decode(JSONSerialization.data(withJSONObject: extra))
        XCTAssertFalse(restored.capabilities.canWriteFittedPrograms)
    }

    func testRationaleCannotLeakAcrossModelProfiles() throws {
        var plan = FittingWorkspaceDraft(model: .intent3, rationale: .nalNL2)
        _ = try plan.validated()
        plan.model = .otherOticon
        XCTAssertThrowsError(try plan.encoded()) {
            XCTAssertEqual($0 as? FittingWorkspaceDraft.ValidationError, .unsupportedRationale)
        }
        plan.rationale = nil
        _ = try plan.validated()
        XCTAssertFalse(plan.readiness(audiograms: []).steps.first { $0.id == .rationale }!.completed)
    }

    func testAcousticReadinessUsesOnlySelectedEarsAndExplicitRecordCheck() throws {
        var plan = FittingWorkspaceDraft(ears: .left)
        plan.leftAcoustics.receiver = "Recorded speaker"
        plan.leftAcoustics.coupling = .customMold
        func complete(_ plan: FittingWorkspaceDraft) -> Bool {
            plan.readiness(audiograms: []).steps.first { $0.id == .acoustics }!.completed
        }
        XCTAssertFalse(complete(plan))
        plan.leftAcoustics.checkedAgainstRecord = true
        XCTAssertTrue(complete(plan))
        XCTAssertEqual(plan.rightAcoustics, .init())
        plan.ears = .both
        XCTAssertFalse(complete(plan))
        plan.rightAcoustics.checkedAgainstRecord = true
        XCTAssertFalse(complete(plan), "A checked box must not invent a receiver or earpiece")
    }

    func testLinkedExamMustResolveAndHaveMeasuredAirValuesForSelectedEars() {
        let left = exam(ears: [.left])
        var plan = FittingWorkspaceDraft(audiogramID: left.id)
        func linked(_ plan: FittingWorkspaceDraft, _ exams: [Audiogram]) -> Bool {
            plan.readiness(audiograms: exams).steps.first { $0.id == .audiogram }!.completed
        }
        XCTAssertFalse(linked(plan, []))
        XCTAssertFalse(linked(plan, [left]))
        plan.ears = .left
        XCTAssertTrue(linked(plan, [left]))
        for other in [exam(ears: [.left], noResponse: true), exam(ears: [.left], conduction: .bone)] {
            plan.audiogramID = other.id
            XCTAssertFalse(linked(plan, [other]))
        }
        var invalid = left
        invalid.thresholds[0].levelDBHL = .nan
        plan.audiogramID = invalid.id
        XCTAssertFalse(linked(plan, [invalid]))
        XCTAssertEqual(left.thresholds[0].levelDBHL, 30, "Readiness must not complete or transform the exam")
    }

    func testProgramIdeasRejectDuplicatesOverLimitAndEmptyNames() throws {
        let idea = FittingProgramPlan(name: "Music", purpose: .music)
        var plan = FittingWorkspaceDraft(programs: [idea, idea])
        XCTAssertThrowsError(try plan.validated())
        plan.programs = (0...FittingWorkspaceDraft.maximumProgramIdeas).map { .init(name: "Idea \($0)") }
        XCTAssertThrowsError(try plan.validated())
        plan.programs = [.init(name: "  ")]
        XCTAssertThrowsError(try plan.validated())
        plan.programs = [.init(name: "Music", purpose: .music, notes: "First line\nSecond line")]
        _ = try plan.validated()
        XCTAssertFalse(plan.capabilities.canWriteFittedPrograms)
    }

    func testInvalidTextAndDatesAreRejectedWithoutDiscardingUserFields() throws {
        var plan = FittingWorkspaceDraft(name: "Good name")
        plan.birthDate = "2025-02-29"
        XCTAssertThrowsError(try plan.validated()) {
            XCTAssertEqual($0 as? FittingWorkspaceDraft.ValidationError, .invalidBirthDate)
        }
        XCTAssertEqual(plan.birthDate, "2025-02-29")
        plan.birthDate = ""
        plan.patientLabel = "Example\u{0}"
        XCTAssertThrowsError(try plan.validated())
        plan.patientLabel = "Example"
        plan.leftAcoustics.receiver = "One\nTwo"
        XCTAssertThrowsError(try plan.validated())
        plan.leftAcoustics.receiver = "Recorded speaker"
        plan.name = String(repeating: "n", count: 161)
        XCTAssertThrowsError(try plan.validated())
    }

    func testUnsupportedEnumAndOversizeFilesFailBeforeUse() throws {
        let valid = try FittingWorkspaceDraft(model: .intent3, rationale: .vacPlus).encoded()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["rationale"] = "nalNL3"
        XCTAssertThrowsError(try FittingWorkspaceDraft.decode(JSONSerialization.data(withJSONObject: object)))
        XCTAssertThrowsError(try FittingWorkspaceDraft.decode(Data(repeating: 0, count: FittingWorkspaceDraft.maximumFileBytes + 1))) {
            XCTAssertEqual($0 as? FittingWorkspaceDraft.ValidationError, .fileTooLarge)
        }
    }
}
