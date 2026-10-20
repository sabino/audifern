import CompanionCore
import Foundation
import Testing
@testable import Audifern

@Test func controlReadinessRequiresCurrentConnectionValues() {
    var state = AidConnection(id: UUID(), name: "Test aid", phase: .connected)
    state.writableVolume = true
    state.volumeRanges = OticonRemoteProtocol.VolumeRanges(data: Data([0xF8, 4, 0, 18, 0xFB, 0]))
    #expect(!state.canChangeVolume)
    state.volume = OticonRemoteProtocol.Volume(data: Data([0, 1]))
    #expect(state.canChangeVolume)
    state.actionPending = true
    #expect(!state.canChangeVolume)
    state.actionPending = false
    state.phase = .disconnected
    #expect(!state.canChangeVolume)
}

@Test func disconnectClearsLiveStatusAndPreviousConfirmation() {
    var state = AidConnection(id: UUID(), name: "Test aid", phase: .connected)
    state.volume = OticonRemoteProtocol.Volume(data: Data([0, 1]))
    state.volumeRanges = OticonRemoteProtocol.VolumeRanges(data: Data([0xF8, 4, 0, 18, 0xFB, 0]))
    state.battery = 35
    state.activeProgram = 0
    state.programIDs = [0]
    state.writableVolume = true
    state.writableProgram = true
    state.lastValueAt = Date()
    state.actionPending = true
    state.actionStatus = "Volume 0 confirmed by hearing aid"
    state.services = [GATTServiceInfo(id: "battery", uuid: "180F", isPrimary: true, characteristics: [
        GATTCharacteristicInfo(id: "level", uuid: "2A19", properties: "read, notify", value: "35%", isNotifying: true)
    ])]
    state.clearLiveValues()
    #expect(state.volume == nil)
    #expect(state.volumeRanges == nil)
    #expect(state.battery == nil)
    #expect(state.activeProgram == nil)
    #expect(state.programIDs.isEmpty)
    #expect(state.lastValueAt == nil)
    #expect(!state.canChangeVolume && !state.canChangeProgram)
    #expect(!state.actionPending && state.actionStatus == nil)
    #expect(state.services[0].characteristics[0].value == nil)
    #expect(!state.services[0].characteristics[0].isNotifying)
}

@Test func physicalSideUsesOnlyAnExactStandardLocation() {
    var state = AidConnection(id: UUID(), name: "Test aid", phase: .connected)
    state.ear = 0
    #expect(state.sideLabel == "Side 0")
    state.sinkAudioLocations = 1
    #expect(state.sideLabel == "Left")
    state.sinkAudioLocations = 2
    #expect(state.sideLabel == "Right")
    state.sinkAudioLocations = 3
    #expect(state.sideLabel == "Side 0")
}

@Test func probeCannotStartWithMissingOrMalformedRequiredArguments() {
    #expect(LaunchConfiguration(arguments: ["app", "--probe-connect", UUID().uuidString]).error != nil)
    #expect(LaunchConfiguration(arguments: ["app", "--probe-seconds", "0", "--probe-output", "/tmp/test.jsonl"]).error != nil)
    #expect(LaunchConfiguration(arguments: ["app", "--probe-seconds", "2", "--probe-output", "/tmp/test.jsonl", "--probe-connect", "not-a-uuid"]).error != nil)
    let valid = LaunchConfiguration(arguments: ["app", "--probe-seconds", "2", "--probe-output", "/tmp/test.jsonl"])
    #expect(valid.error == nil && valid.isProbe && valid.probeConnect == nil)
}
