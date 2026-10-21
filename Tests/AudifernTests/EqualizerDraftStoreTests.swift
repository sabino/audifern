import CompanionCore
import Foundation
import Testing
@testable import Audifern

@MainActor @Test func equalizerDraftsSurviveReadbackButClearAcrossProgramOrCapabilityChanges() throws {
    let id = UUID()
    var aid = AidConnection(id: id, name: "Synthetic aid", phase: .connected)
    aid.activeProgram = 1
    func eq(_ gain: Int, limit: Int = 6) throws -> OticonEqualizer.State {
        try .init(rawSteps: Array(repeating: gain, count: 8), minimumSteps: Array(repeating: -limit, count: 8),
                  maximumSteps: Array(repeating: limit, count: 8), stepDB: 1)
    }
    aid.microphoneEqualizer = try eq(0)
    aid.streamingEqualizer = try eq(0)
    let drafts = EqualizerDraftStore()
    drafts.reconcile([id: aid])
    drafts[id, microphone: true] = [1, 2, 3]
    drafts[id, microphone: false] = [3, 2, 1]
    aid.microphoneEqualizer = try eq(1)
    drafts.reconcile([id: aid])
    #expect(drafts[id, microphone: true] == [1, 2, 3])
    #expect(drafts[id, microphone: false] == [3, 2, 1])
    aid.microphoneEqualizer = try eq(1, limit: 4)
    drafts.reconcile([id: aid])
    #expect(drafts[id, microphone: true] == nil)
    #expect(drafts[id, microphone: false] == [3, 2, 1])
    aid.activeProgram = 2
    drafts.reconcile([id: aid])
    #expect(drafts[id, microphone: false] == nil)
    drafts[id, microphone: true] = [2, 2, 2]
    aid.phase = .disconnected
    drafts.reconcile([id: aid])
    #expect(drafts[id, microphone: true] == nil)
    drafts[id, microphone: false] = [2, 2, 2]
    drafts.reconcile([:])
    #expect(drafts[id, microphone: false] == nil)
}

@MainActor @Test func previewCannotIssueBluetoothActionsOrExposePrivateIdentities() {
    let store = BluetoothStore(demo: true)
    #expect(store.isDemo && !store.isPoweredOn && store.connectedCount == 2)
    #expect(store.orderedConnections.allSatisfy { $0.serialNumber == nil && !$0.canChangeVolume && !$0.canChangeProgram && !$0.canChangeMicrophoneEqualizer })
    store.startScan(seconds: 0.01)
    store.connectPair()
    store.connect(to: DemoData.leftID)
    store.disconnect()
    store.adjustVolume(DemoData.leftID, by: 1)
    store.setMuted(DemoData.rightID, muted: true)
    store.readProgramSnapshot()
    #expect(!store.isScanning && store.connectedCount == 2)
    #expect(store.programSnapshot == nil && !store.programSnapshotBusy)
    #expect(store.orderedConnections.allSatisfy { $0.volume?.level == 0 && $0.serialNumber == nil })
}

@MainActor @Test func aChangedReportedFrequencyAxisInvalidatesItsEightChannelDraft() throws {
    let id = UUID()
    var aid = AidConnection(id: id, name: "Synthetic", phase: .connected)
    aid.activeProgram = 1
    func equalizer(_ frequencies: [Double]?) throws -> OticonEqualizer.State {
        try .init(rawSteps: .init(repeating: 0, count: 8), minimumSteps: .init(repeating: -12, count: 8),
                  maximumSteps: .init(repeating: 12, count: 8), stepDB: 0.25, frequenciesHz: frequencies)
    }
    aid.microphoneEqualizer = try equalizer(nil); aid.streamingEqualizer = try equalizer(nil)
    let drafts = EqualizerDraftStore()
    drafts.reconcile([id: aid])
    drafts[id, microphone: true] = Array(repeating: 0.5, count: 8)
    drafts[id, microphone: false] = Array(repeating: -0.5, count: 8)
    aid.microphoneEqualizer = try equalizer([250, 500, 1000, 2000, 3000, 4000, 6000, 8000])
    drafts.reconcile([id: aid])
    #expect(drafts[id, microphone: true] == nil)
    #expect(drafts[id, microphone: false] == Array(repeating: -0.5, count: 8))
}

@MainActor @Test func linkedChannelEditsPreserveEachEarsUntouchedShapeAndLimits() throws {
    var left = AidConnection(id: UUID(), name: "Synthetic left", phase: .connected)
    var right = AidConnection(id: UUID(), name: "Synthetic right", phase: .connected)
    left.microphoneEqualizer = try .init(rawSteps: [0, 20, 1, 2, 3, 4, 5, 6],
        minimumSteps: .init(repeating: -24, count: 8), maximumSteps: .init(repeating: 24, count: 8), stepDB: 0.25)
    right.microphoneEqualizer = try .init(rawSteps: [0, -1, -2, -3, -4, -5, -6, -7],
        minimumSteps: .init(repeating: -12, count: 8), maximumSteps: .init(repeating: 2, count: 8), stepDB: 0.5)
    let drafts = EqualizerDraftStore()
    let baselineLeft = try #require(left.microphoneEqualizer).channelDB
    let baselineRight = try #require(right.microphoneEqualizer).channelDB
    #expect(drafts.editChannels([left, right], microphone: true, channels: [0], value: 0.5))
    var expectedLeft = baselineLeft, expectedRight = baselineRight
    expectedLeft[0] = 0.5; expectedRight[0] = 0.5
    #expect(drafts[left.id, microphone: true] == expectedLeft)
    #expect(drafts[right.id, microphone: true] == expectedRight)
    // An untouched5dB band is valid for left even though right's limit is1dB.
    #expect(drafts[left.id, microphone: true]?[1] == 5)
    #expect(drafts.editChannels([left, right], microphone: true, channels: [1, 2, 3], value: 1))
    for channel in 1...3 { expectedLeft[channel] = 1; expectedRight[channel] = 1 }
    #expect(drafts[left.id, microphone: true] == expectedLeft)
    #expect(drafts[right.id, microphone: true] == expectedRight)
    #expect(!drafts.editChannels([left, right], microphone: true, channels: [4], value: 3))
    #expect(drafts[left.id, microphone: true] == expectedLeft && drafts[right.id, microphone: true] == expectedRight)
}

@MainActor @Test func separateEarDraftSurvivesTheOtherEarLoadingAndIsVisibleToGroupedApply() throws {
    var left = AidConnection(id: UUID(), name: "Synthetic left", phase: .connected)
    var right = AidConnection(id: UUID(), name: "Synthetic right", phase: .connected)
    left.activeProgram = 0
    left.microphoneEqualizer = try .init(rawSteps: .init(repeating: 0, count: 8),
        minimumSteps: .init(repeating: -6, count: 8), maximumSteps: .init(repeating: 6, count: 8), stepDB: 1)
    let drafts = EqualizerDraftStore()
    drafts.reconcile([left.id: left, right.id: right])
    #expect(drafts.editChannels([left], microphone: true, channels: [0], value: 2))
    right.activeProgram = 0
    right.microphoneEqualizer = left.microphoneEqualizer
    drafts.reconcile([left.id: left, right.id: right])
    #expect(drafts[left.id, microphone: true]?[0] == 2)
    #expect(drafts[right.id, microphone: true] == nil)
    #expect(drafts.hasChanges(for: [right, left], microphone: true))
    #expect(!drafts.hasChanges(for: [right], microphone: true))
    #expect(!drafts.hasChanges(for: [left, right], microphone: false))
    #expect(drafts.editChannels([right], microphone: true, channels: [1], value: -1))
    #expect(drafts[left.id, microphone: true]?[1] == 0)
    #expect(drafts[right.id, microphone: true]?[0] == 0)
    // Grouping does not replace either vector; only a touched band is mirrored.
    #expect(drafts.editChannels([left, right], microphone: true, channels: [7], value: 1))
    #expect(drafts[left.id, microphone: true]?[0] == 2)
    #expect(drafts[right.id, microphone: true]?[1] == -1)
}
