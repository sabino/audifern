import CompanionCore
import Foundation

/// Plans only the consumer controls already exposed by the connected aids.
/// A reset here never selects a program or changes a clinical fitting.
struct ConsumerControlPlan {
    enum ResetScope: String, CaseIterable, Identifiable {
        case volume, microphone, streaming, speechBooster, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .volume: "Volume and mute"
            case .microphone: "Microphone EQ"
            case .streaming: "Streaming EQ"
            case .speechBooster: "SpeechBooster"
            case .all: "All sound controls"
            }
        }
        var explanation: String {
            switch self {
            case .volume: "Set microphone volume to 0 and unmute."
            case .microphone: "Set all microphone EQ bands to neutral (0 dB)."
            case .streaming: "Set all streaming EQ bands to neutral (0 dB)."
            case .speechBooster: "Turn SpeechBooster off using the aid’s consumer defaults."
            case .all: "Set volume to 0, unmute, flatten both EQs and turn SpeechBooster off where the current program supports it."
            }
        }
    }
    enum Change {
        case volumeLevels([UUID: Int])
        case equalizer(microphone: Bool, bandsDB: [Double])
        case equalizerChannels(microphone: Bool, levelsByAid: [UUID: [Double]])
        case speechBooster(Bool)
        case program(Int)
        case restore(ResetScope)
    }
    enum Setting: Equatable {
        case volume(level: Int, muted: Bool)
        case equalizer(microphone: Bool, steps: [Int], expected: OticonEqualizer.State)
        case speechBooster(Bool)
        case program(Int)
        var label: String {
            switch self {
            case .volume: "Volume and mute"
            case .equalizer(let microphone, _, _): microphone ? "Microphone EQ" : "Streaming EQ"
            case .speechBooster: "SpeechBooster"
            case .program: "Program"
            }
        }
    }
    struct Step: Equatable {
        let aidID: UUID
        let side: String
        let program: Int?
        let setting: Setting
        var expectedVolume: OticonRemoteProtocol.Volume? = nil

        func validate(_ aid: AidConnection) throws {
            guard aid.id == aidID, aid.isConnected, aid.activeProgram == program else {
                throw PlanError.unavailable("An aid’s connection or program changed. Refresh its controls and try again.")
            }
            // The executor owns this lock. Other pending work must still block it.
            var available = aid
            available.groupActionPending = false
            switch setting {
            case .volume(let level, _):
                guard available.canChangeVolume, aid.volumeRanges?.main.contains(level) == true else {
                    throw PlanError.unavailable("\(side) volume is unavailable or outside its reported range.")
                }
                if let expectedVolume, aid.volume != expectedVolume {
                    throw PlanError.unavailable("Volume or mute changed. Refresh before retrying.")
                }
            case .equalizer(let microphone, let steps, let expected):
                let eq = microphone ? aid.microphoneEqualizer : aid.streamingEqualizer
                let ready = microphone ? available.canChangeMicrophoneEqualizer : available.canChangeStreamingEqualizer
                guard ready, let eq, eq.stepDB == expected.stepDB,
                      eq.minimumSteps == expected.minimumSteps, eq.maximumSteps == expected.maximumSteps,
                      eq.frequenciesHz == expected.frequenciesHz else {
                    throw PlanError.unavailable("\(side) EQ limits changed. Reload its advanced controls.")
                }
                try eq.validate(steps)
            case .speechBooster:
                guard available.canChangeSpeechBooster else {
                    throw PlanError.unavailable("Load \(side.lowercased()) SpeechBooster in a supported program first.")
                }
            case .program(let program):
                guard available.canChangeProgram, aid.programIDs.contains(program) else {
                    throw PlanError.unavailable("That program is unavailable on the \(side.lowercased()) aid.")
                }
            }
        }
    }
    enum PlanError: LocalizedError {
        case unavailable(String)
        var errorDescription: String? { switch self { case .unavailable(let message): message } }
    }
    let steps: [Step]

    init(aids: [AidConnection], change: Change) throws {
        guard !aids.isEmpty, aids.count <= 2, Set(aids.map(\.id)).count == aids.count else {
            throw PlanError.unavailable("Choose one aid or a connected pair.")
        }
        if case .program(let program) = change, aids.count == 2 {
            guard let name = aids[0].programNames[program], !name.isEmpty, name == aids[1].programNames[program] else {
                throw PlanError.unavailable("The program must have the same reported ID and name on both aids.")
            }
        }
        switch change {
        case .equalizer(let microphone, _), .equalizerChannels(let microphone, _):
            let layouts = aids.compactMap { (microphone ? $0.microphoneEqualizer : $0.streamingEqualizer)?.frequenciesHz }
            if let first = layouts.first, layouts.contains(where: { $0 != first }) {
                throw PlanError.unavailable("The aids report different EQ frequency layouts. Adjust each ear separately.")
            }
        default: break
        }
        if case .equalizerChannels(_, let levels) = change, Set(levels.keys) != Set(aids.map(\.id)) {
            throw PlanError.unavailable("An EQ draft must match every selected hearing aid exactly.")
        }
        if case .volumeLevels(let levels) = change, Set(levels.keys) != Set(aids.map(\.id)) {
            throw PlanError.unavailable("Volume targets must match every selected hearing aid exactly.")
        }
        var planned: [Step] = []
        for aid in aids {
            guard aid.isConnected, !aid.actionPending, !aid.advancedBusy, !aid.groupActionPending else {
                throw PlanError.unavailable("Wait for both aids to finish connecting or changing settings.")
            }
            func append(_ setting: Setting, expectedVolume: OticonRemoteProtocol.Volume? = nil) throws {
                let step = Step(aidID: aid.id, side: aid.sideLabel, program: aid.activeProgram, setting: setting, expectedVolume: expectedVolume)
                try step.validate(aid)
                planned.append(step)
            }
            func equalizer(_ microphone: Bool, _ bandsDB: [Double]) throws {
                guard let eq = microphone ? aid.microphoneEqualizer : aid.streamingEqualizer else {
                    throw PlanError.unavailable("Load \(aid.sideLabel.lowercased()) advanced controls first.")
                }
                try append(.equalizer(microphone: microphone, steps: eq.steps(forThreeBandDB: bandsDB), expected: eq))
            }
            switch change {
            case .volumeLevels(let levels):
                guard let target = levels[aid.id], let current = aid.volume else {
                    throw PlanError.unavailable("Load current volume before changing it.")
                }
                try append(.volume(level: target, muted: current.muted), expectedVolume: current)
            case .equalizer(let microphone, let bandsDB): try equalizer(microphone, bandsDB)
            case .equalizerChannels(let microphone, let levelsByAid):
                guard let bandsDB = levelsByAid[aid.id],
                      let eq = microphone ? aid.microphoneEqualizer : aid.streamingEqualizer else {
                    throw PlanError.unavailable("Load \(aid.sideLabel.lowercased()) advanced controls first.")
                }
                try append(.equalizer(microphone: microphone, steps: eq.steps(forChannelDB: bandsDB), expected: eq))
            case .speechBooster(let enabled): try append(.speechBooster(enabled))
            case .program(let program): try append(.program(program))
            case .restore(let scope):
                if scope == .volume || scope == .all { try append(.volume(level: 0, muted: false)) }
                if scope == .microphone || scope == .all { try equalizer(true, [0, 0, 0]) }
                if scope == .streaming || scope == .all { try equalizer(false, [0, 0, 0]) }
                if scope == .speechBooster || scope == .all {
                    if scope == .all, let program = aid.activeProgram, aid.programBoostable[program] == false {
                        // Unsupported in this program, so there is no booster setting to reset.
                    } else { try append(.speechBooster(false)) }
                }
            }
        }
        steps = planned
    }
}

/// Both targets are checked before the first write and again before each step.
/// Every apply closure must await device confirmation; a group is not atomic.
@MainActor
enum ConsumerControlExecutor {
    struct Outcome {
        let confirmed: Int
        let total: Int
        let attempted: Int
        let error: String?
        var succeeded: Bool { error == nil }
        var message: String {
            guard let error else { return "All \(total) sound \(total == 1 ? "change" : "changes") confirmed by the hearing aids." }
            if attempted == 0 { return "No changes sent. \(error)" }
            let uncertain = attempted > confirmed ? " The last request may still have reached the aid." : ""
            return "Stopped after \(confirmed) of \(total) confirmed changes.\(confirmed > 0 ? " Earlier confirmed changes remain applied." : "")\(uncertain) \(error)"
        }
    }
    static func run(_ plan: ConsumerControlPlan,
                    validate: (ConsumerControlPlan.Step) async throws -> Void,
                    apply: (ConsumerControlPlan.Step) async throws -> Void) async -> Outcome {
        var confirmed = 0
        var attempted = 0
        do {
            for step in plan.steps { try await validate(step) }
            for step in plan.steps {
                try await validate(step)
                attempted += 1
                try await apply(step)
                confirmed += 1
            }
            return Outcome(confirmed: confirmed, total: plan.steps.count, attempted: attempted, error: nil)
        } catch {
            return Outcome(confirmed: confirmed, total: plan.steps.count, attempted: attempted, error: error.localizedDescription)
        }
    }
}
