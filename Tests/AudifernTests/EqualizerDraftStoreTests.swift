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
