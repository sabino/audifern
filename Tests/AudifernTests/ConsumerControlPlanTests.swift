import CompanionCore
import Foundation
import Testing
@testable import Audifern

private func consumerAid(right: Bool = false, scale: Double = 0.25) throws -> AidConnection {
    var aid = AidConnection(id: UUID(), name: "Synthetic aid", phase: .connected)
    aid.sinkAudioLocations = right ? 2 : 1
    aid.volume = OticonRemoteProtocol.Volume(data: Data([2, 0]))
    aid.volumeRanges = OticonRemoteProtocol.VolumeRanges(data: Data([0xF8, 4, 0, 18, 0xFB, 0]))
    aid.writableVolume = true
    aid.activeProgram = 0; aid.programIDs = [0, 1]; aid.programNames = [0: "General", 1: "Music"]
    aid.writableProgram = true; aid.programBoostable = [0: true, 1: false]
    aid.speechBoosterEnabled = true; aid.writableSpeechBooster = true
    let eq = try OticonEqualizer.State(rawSteps: .init(repeating: 4, count: 8),
                                      minimumSteps: .init(repeating: -24, count: 8),
                                      maximumSteps: .init(repeating: 24, count: 8), stepDB: scale)
    aid.microphoneEqualizer = eq; aid.streamingEqualizer = eq
    aid.writableMicrophoneEqualizer = true; aid.writableStreamingEqualizer = true
    return aid
}

@Test func linkedEQQuantizesForEachAidAndKeepsItsOwnLimits() throws {
    let left = try consumerAid(scale: 0.25), right = try consumerAid(right: true, scale: 0.5)
    let plan = try ConsumerControlPlan(aids: [left, right], change: .equalizer(microphone: true, bandsDB: [1, -2, 3]))
    #expect(plan.steps.count == 2)
    guard case .equalizer(true, let leftSteps, let leftScale) = plan.steps[0].setting,
          case .equalizer(true, let rightSteps, let rightScale) = plan.steps[1].setting else { Issue.record("Missing EQ plan"); return }
    #expect(leftSteps == [4, -8, -8, -8, 12, 12, 12, 12])
    #expect(rightSteps == [2, -4, -4, -4, 6, 6, 6, 6])
    #expect(leftScale.stepDB == 0.25 && rightScale.stepDB == 0.5)
}

@Test func linkedEQRejectsWholePlanWhenSecondAidCannotRepresentIt() throws {
    let left = try consumerAid(scale: 0.5), right = try consumerAid(right: true, scale: 0.125)
    #expect(throws: (any Error).self) {
        try ConsumerControlPlan(aids: [left, right], change: .equalizer(microphone: false, bandsDB: [4, 0, 0]))
    }
    var unloaded = right
    unloaded.streamingEqualizer = nil
    #expect(throws: (any Error).self) {
        try ConsumerControlPlan(aids: [left, unloaded], change: .equalizer(microphone: false, bandsDB: [0, 0, 0]))
    }
}

@Test func channelEQPlansIndependentBandsWithEachAidScaleAndExistingRevalidation() throws {
    let left = try consumerAid(scale: 0.25), right = try consumerAid(right: true, scale: 0.5)
    let levels = [0.25, 0.75, -0.25, -0.75, 1, 2, -1, -2]
    let plan = try ConsumerControlPlan(aids: [left, right], change: .equalizerChannels(microphone: true, levelsByAid: [left.id: levels, right.id: levels]))
    guard case .equalizer(true, let leftSteps, _) = plan.steps[0].setting,
          case .equalizer(true, let rightSteps, _) = plan.steps[1].setting else {
        Issue.record("Missing independent-channel EQ plan"); return
    }
    #expect(leftSteps == [1, 3, -1, -3, 4, 8, -4, -8])
    #expect(rightSteps == [0, 2, 0, -2, 2, 4, -2, -4])
    var changed = right
    changed.activeProgram = 1
    #expect(throws: (any Error).self) { try plan.steps[1].validate(changed) }
    changed.activeProgram = 0
    changed.writableMicrophoneEqualizer = false
    #expect(throws: (any Error).self) { try plan.steps[1].validate(changed) }
}

@Test func channelEQPreflightRejectsTheWholePairForAnUnsupportedSecondBand() throws {
    let left = try consumerAid(scale: 0.5), right = try consumerAid(right: true, scale: 0.125)
    var levels = [Double](repeating: 0, count: 8)
    levels[7] = 4
    #expect(throws: (any Error).self) {
        try ConsumerControlPlan(aids: [left, right], change: .equalizerChannels(microphone: false, levelsByAid: [left.id: levels, right.id: levels]))
    }
    #expect(throws: (any Error).self) {
        try ConsumerControlPlan(aids: [left], change: .equalizerChannels(microphone: true, levelsByAid: [left.id: [0, 0, 0]]))
    }
}

@Test func linkedEQRefusesConflictingReportedAxesAndRevalidatesItsSelectedAxis() throws {
    var left = try consumerAid(), right = try consumerAid(right: true)
    func eq(_ frequencies: [Double]) throws -> OticonEqualizer.State {
        try .init(rawSteps: .init(repeating: 0, count: 8), minimumSteps: .init(repeating: -24, count: 8),
                  maximumSteps: .init(repeating: 24, count: 8), stepDB: 0.25, frequenciesHz: frequencies)
    }
    left.microphoneEqualizer = try eq([250, 500, 1000, 2000, 3000, 4000, 6000, 8000])
    right.microphoneEqualizer = try eq([300, 600, 1200, 2400, 3600, 4800, 6400, 8800])
    let change = ConsumerControlPlan.Change.equalizerChannels(microphone: true,
        levelsByAid: [left.id: .init(repeating: 0.5, count: 8), right.id: .init(repeating: 0.5, count: 8)])
    #expect(throws: (any Error).self) { try ConsumerControlPlan(aids: [left, right], change: change) }
    let singleChange = ConsumerControlPlan.Change.equalizerChannels(microphone: true,
        levelsByAid: [left.id: .init(repeating: 0.5, count: 8)])
    let step = try #require(ConsumerControlPlan(aids: [left], change: singleChange).steps.first)
    left.microphoneEqualizer = right.microphoneEqualizer
    #expect(throws: (any Error).self) { try step.validate(left) }
    // A neutral reset is independently valid for each aid's own channel layout.
    #expect(try ConsumerControlPlan(aids: [left, right], change: .restore(.microphone)).steps.count == 2)
}

@Test func channelEQNeedsOneIndependentVectorPerSelectedAid() throws {
    let left = try consumerAid(), right = try consumerAid(right: true)
    let first = [Double](repeating: 0.25, count: 8), second = [Double](repeating: -0.25, count: 8)
    let plan = try ConsumerControlPlan(aids: [left, right],
        change: .equalizerChannels(microphone: true, levelsByAid: [left.id: first, right.id: second]))
    #expect(plan.steps.count == 2)
    guard case .equalizer(true, let leftValues, _) = plan.steps[0].setting,
          case .equalizer(true, let rightValues, _) = plan.steps[1].setting else {
        Issue.record("Missing per-aid vectors"); return
    }
    #expect(leftValues == .init(repeating: 1, count: 8) && rightValues == .init(repeating: -1, count: 8))
    for invalid in [[left.id: first], [left.id: first, right.id: second, UUID(): first]] {
        #expect(throws: (any Error).self) {
            try ConsumerControlPlan(aids: [left, right], change: .equalizerChannels(microphone: true, levelsByAid: invalid))
        }
    }
}

@Test func resetAllUsesOnlyNeutralConsumerSettingsInCurrentProgram() throws {
    let aid = try consumerAid()
    let plan = try ConsumerControlPlan(aids: [aid], change: .restore(.all))
    #expect(plan.steps.count == 4)
    #expect(plan.steps.allSatisfy { $0.aidID == aid.id && $0.program == 0 })
    #expect(plan.steps[0].setting == .volume(level: 0, muted: false))
    #expect(plan.steps[3].setting == .speechBooster(false))
    for step in plan.steps[1...2] {
        guard case .equalizer(_, let steps, _) = step.setting else { Issue.record("Expected EQ reset"); continue }
        #expect(steps == .init(repeating: 0, count: 8))
    }
    // Serial identity and clinical data never enter a consumer-setting plan.
    #expect(aid.volume?.level == 2 && aid.volume?.muted == true)
    #expect(aid.microphoneEqualizer?.rawSteps == .init(repeating: 4, count: 8))
}

@Test func defaultResetCannotGuessMissingCapabilitiesOrOverrideRanges() throws {
    var aid = try consumerAid()
    aid.programBoostable = [:]
    #expect(throws: (any Error).self) { try ConsumerControlPlan(aids: [aid], change: .restore(.all)) }
    aid.programBoostable = [0: false]
    #expect(try ConsumerControlPlan(aids: [aid], change: .restore(.all)).steps.count == 3)
    #expect(throws: (any Error).self) { try ConsumerControlPlan(aids: [aid], change: .restore(.speechBooster)) }
    aid.volumeRanges = OticonRemoteProtocol.VolumeRanges(data: Data([1, 4, 0, 18, 0xFB, 0]))
    #expect(throws: (any Error).self) { try ConsumerControlPlan(aids: [aid], change: .restore(.volume)) }
    aid.microphoneEqualizer = try OticonEqualizer.State(rawSteps: .init(repeating: 4, count: 8),
        minimumSteps: .init(repeating: 1, count: 8), maximumSteps: .init(repeating: 24, count: 8), stepDB: 0.25)
    #expect(throws: (any Error).self) { try ConsumerControlPlan(aids: [aid], change: .restore(.microphone)) }
}

@Test func perSettingResetTouchesOnlyRequestedSettingAndAid() throws {
    let left = try consumerAid(), right = try consumerAid(right: true)
    let plan = try ConsumerControlPlan(aids: [right], change: .restore(.streaming))
    #expect(plan.steps.count == 1 && plan.steps[0].aidID != left.id)
    guard case .equalizer(false, let steps, _) = plan.steps[0].setting else { Issue.record("Wrong reset setting"); return }
    #expect(steps.allSatisfy { $0 == 0 })
    #expect(throws: (any Error).self) { try ConsumerControlPlan(aids: [], change: .restore(.all)) }
    #expect(throws: (any Error).self) { try ConsumerControlPlan(aids: [left, left], change: .restore(.all)) }
}

@Test func sharedProgramRequiresMatchingNamesAndReportedIDs() throws {
    let left = try consumerAid()
    var right = try consumerAid(right: true)
    #expect(try ConsumerControlPlan(aids: [left, right], change: .program(1)).steps.count == 2)
    right.programNames[1] = "Different fitted program"
    #expect(throws: (any Error).self) { try ConsumerControlPlan(aids: [left, right], change: .program(1)) }
    right.programNames[1] = "Music"; right.programIDs = [0]
    #expect(throws: (any Error).self) { try ConsumerControlPlan(aids: [left, right], change: .program(1)) }
}

@Test func inFlightPlanDetectsChangedProgramScaleAndBusyState() throws {
    var aid = try consumerAid()
    let step = try ConsumerControlPlan(aids: [aid], change: .equalizer(microphone: true, bandsDB: [1, 0, 0])).steps[0]
    aid.groupActionPending = true
    try step.validate(aid) // Only this executor's own lock is ignored.
    aid.activeProgram = 1
    #expect(throws: (any Error).self) { try step.validate(aid) }
    aid.activeProgram = 0; aid.actionPending = true
    #expect(throws: (any Error).self) { try step.validate(aid) }
    aid.actionPending = false
    aid.microphoneEqualizer = try consumerAid(scale: 0.5).microphoneEqualizer
    #expect(throws: (any Error).self) { try step.validate(aid) }
    aid.phase = .disconnected
    #expect(throws: (any Error).self) { try step.validate(aid) }
}

@Test @MainActor func executorChecksBothTargetsBeforeAnyWrite() async throws {
    let left = try consumerAid(), right = try consumerAid(right: true)
    let plan = try ConsumerControlPlan(aids: [left, right], change: .speechBooster(false))
    var writes: [UUID] = []
    let outcome = await ConsumerControlExecutor.run(plan, validate: { step in
        if step.aidID == right.id { throw ConsumerControlPlan.PlanError.unavailable("Synthetic second-side failure") }
    }, apply: { step in writes.append(step.aidID) })
    #expect(writes.isEmpty && outcome.confirmed == 0 && outcome.attempted == 0 && !outcome.succeeded)
    #expect(outcome.message.hasPrefix("No changes sent."))
}

@Test @MainActor func executorReportsPartialConfirmationWithoutRollbackOrFalseSuccess() async throws {
    let left = try consumerAid(), right = try consumerAid(right: true)
    let plan = try ConsumerControlPlan(aids: [left, right], change: .speechBooster(false))
    var writes: [UUID] = []
    let outcome = await ConsumerControlExecutor.run(plan, validate: { _ in }, apply: { step in
        writes.append(step.aidID)
        if step.aidID == right.id { throw ConsumerControlPlan.PlanError.unavailable("Synthetic missing reply") }
    })
    #expect(writes == [left.id, right.id])
    #expect(outcome.confirmed == 1 && outcome.attempted == 2 && !outcome.succeeded)
    #expect(outcome.message.contains("Earlier confirmed changes remain applied"))
    #expect(outcome.message.contains("may still have reached"))
}

@Test @MainActor func executorRechecksTargetBetweenPreflightAndWrite() async throws {
    let left = try consumerAid(), right = try consumerAid(right: true)
    let plan = try ConsumerControlPlan(aids: [left, right], change: .restore(.volume))
    var writes: [UUID] = []
    let outcome = await ConsumerControlExecutor.run(plan, validate: { step in
        if !writes.isEmpty && step.aidID == right.id { throw ConsumerControlPlan.PlanError.unavailable("Program changed") }
    }, apply: { step in writes.append(step.aidID) })
    #expect(writes == [left.id] && outcome.confirmed == 1 && outcome.attempted == 1)
    #expect(!outcome.succeeded && !outcome.message.contains("last request may"))
}

@Test @MainActor func executorRequiresEveryResetStepToConfirm() async throws {
    let left = try consumerAid(), right = try consumerAid(right: true)
    let plan = try ConsumerControlPlan(aids: [left, right], change: .restore(.all))
    var steps: [ConsumerControlPlan.Step] = []
    let outcome = await ConsumerControlExecutor.run(plan, validate: { _ in }, apply: { step in steps.append(step) })
    #expect(outcome.succeeded && outcome.confirmed == 8 && outcome.attempted == 8)
    #expect(steps == plan.steps)
}
