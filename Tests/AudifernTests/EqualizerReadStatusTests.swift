import Foundation
import Testing
@testable import Audifern

@MainActor @Test func togetherEQStatusKeepsBothEarsEvidenceAndIdentifiesTheFailedSide() throws {
    let aids = DemoData.connections.values.sorted { $0.sideLabel < $1.sideLabel }
    let right = try #require(aids.last)
    var states: [UUID: EqualizerLoader.State] = [:]
    #expect(EqualizerReadSummary(aids: aids, microphone: true, states: states).isLoaded)
    states[right.id] = .init(context: .init(id: right.id, connectedAt: right.connectedAt, program: right.activeProgram), status: .failed("Synthetic read failure"))
    let summary = EqualizerReadSummary(aids: aids, microphone: true, states: states)
    #expect(!summary.isLoaded && summary.hasProblem)
    #expect(summary.ears.first?.state == .loaded)
    #expect(summary.ears.last?.state == .failed("Synthetic read failure"))
    #expect(summary.detail.contains("Synthetic read failure"))
    #expect(summary.ears.count == 2)
}

@MainActor @Test func EQStatusDoesNotReuseAnotherProgramsFailureOrAConnectedEarsSuccess() throws {
    var aids = DemoData.connections.values.sorted { $0.sideLabel < $1.sideLabel }
    let left = try #require(aids.first)
    let states = [left.id: EqualizerLoader.State(context: .init(id: left.id, connectedAt: left.connectedAt, program: 99), status: .failed("Old program"))]
    #expect(EqualizerReadSummary(aids: aids, microphone: true, states: states).isLoaded)
    aids[1].phase = .disconnected
    let summary = EqualizerReadSummary(aids: aids, microphone: true, states: states)
    #expect(!summary.isLoaded && summary.hasProblem)
    #expect(summary.ears.last?.state == .disconnected)
    aids[1].phase = .connected; aids[1].streamingEqualizer = nil
    #expect(EqualizerReadSummary(aids: aids, microphone: true, states: [:]).isLoaded)
    #expect(!EqualizerReadSummary(aids: aids, microphone: false, states: [:]).isLoaded)
}
