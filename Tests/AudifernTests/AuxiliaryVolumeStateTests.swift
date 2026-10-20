@testable import CompanionCore
import Foundation
import Testing
@testable import Audifern

private func auxiliaryState() -> AidConnection {
    var aid = AidConnection(id: UUID(), name: "Synthetic aid", phase: .connected)
    aid.activeProgram = 1
    aid.volumeRanges = .init(data: Data([0xFC, 6, 0xFC, 3, 0xFC, 3]))
    aid.tinnitusVolume = .init(data: Data([0, 1]))
    aid.streamingVolume = .init(data: Data([0, 1]))
    aid.writableTinnitusVolume = true; aid.writableStreamingVolume = true
    return aid
}

@Test func auxiliaryControlsFailClosedWithoutCurrentFittedProgramFlags() {
    var aid = auxiliaryState()
    #expect(!aid.canChangeTinnitusVolume && !aid.canChangeStreamingVolume)
    aid.programTinnitus[1] = false
    #expect(!aid.canChangeTinnitusVolume && !aid.canChangeStreamingVolume)
    aid.programTinnitus[1] = true
    #expect(aid.canChangeTinnitusVolume)
    aid.programStreaming[1] = true
    #expect(!aid.canChangeStreamingVolume)
    aid.programTinnitus[1] = false
    #expect(aid.canChangeStreamingVolume && !aid.canChangeTinnitusVolume)
    aid.activeProgram = 2
    #expect(!aid.canChangeTinnitusVolume && !aid.canChangeStreamingVolume)
}

@Test func auxiliaryControlsNeedCurrentValuesRangesWritableCharacteristicAndIdleConnection() {
    var aid = auxiliaryState()
    aid.programTinnitus[1] = true
    #expect(aid.canChangeTinnitusVolume)
    aid.groupActionPending = true; #expect(!aid.canChangeTinnitusVolume)
    aid.groupActionPending = false; aid.advancedBusy = true; #expect(!aid.canChangeTinnitusVolume)
    aid.advancedBusy = false; aid.writableTinnitusVolume = false; #expect(!aid.canChangeTinnitusVolume)
    aid.writableTinnitusVolume = true; aid.tinnitusVolume = nil; #expect(!aid.canChangeTinnitusVolume)
    aid.tinnitusVolume = .init(data: Data([0, 1])); aid.volumeRanges = nil; #expect(!aid.canChangeTinnitusVolume)
    aid = auxiliaryState(); aid.programTinnitus[1] = true; aid.phase = .disconnected
    #expect(!aid.canChangeTinnitusVolume)
}

@Test func disconnectClearsAuxiliaryStatesAndDoesNotCarryTherapyEligibilityToAnotherConnection() {
    var aid = auxiliaryState()
    aid.programTinnitus = [1: true]; aid.programStreaming = [2: true]
    aid.tinnitusStatus = "Synthetic confirmation"; aid.streamingVolumeStatus = "Synthetic confirmation"
    aid.tinnitusStatusFailed = true; aid.streamingVolumeStatusFailed = true
    aid.clearLiveValues()
    #expect(aid.tinnitusVolume == nil && aid.streamingVolume == nil)
    #expect(!aid.writableTinnitusVolume && !aid.writableStreamingVolume)
    #expect(aid.programTinnitus.isEmpty && aid.programStreaming.isEmpty)
    #expect(aid.tinnitusStatus == nil && aid.streamingVolumeStatus == nil)
    #expect(!aid.tinnitusStatusFailed && !aid.streamingVolumeStatusFailed)
}

@Test func auxiliaryVolumeReadAndNotifyAllowlistIsBoundToTheProvenLegacyService() {
    for uuid in [OticonRemoteProtocol.tinnitusVolume, OticonRemoteProtocol.streamingVolume] {
        #expect(ReadOnlyInspection.name(service: OticonRemoteProtocol.service, characteristic: uuid) != nil)
        #expect(ReadOnlyInspection.shouldNotify(service: OticonRemoteProtocol.service, characteristic: uuid))
        #expect(ReadOnlyInspection.name(service: "180A", characteristic: uuid) == nil)
        #expect(ReadOnlyInspection.displayValue(service: OticonRemoteProtocol.service, characteristic: uuid,
                                               data: Data([0xFE, 0])) == "Level -2 · muted")
    }
}
