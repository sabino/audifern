@testable import CompanionCore
import Foundation
import Testing
@testable import Audifern

@Test func speechBoosterRequiresAnExplicitlyBoostableCurrentProgram() {
    var state = AidConnection(id: UUID(), name: "Synthetic aid", phase: .connected)
    state.activeProgram = 1
    state.speechBoosterEnabled = false; state.writableSpeechBooster = true
    #expect(!state.canChangeSpeechBooster)
    state.programBoostable[1] = false
    #expect(!state.canChangeSpeechBooster)
    state.programBoostable[1] = true
    #expect(state.canChangeSpeechBooster)
    state.groupActionPending = true
    #expect(!state.canChangeSpeechBooster)
}

@Test func serialInspectionIsExplicitlyBoundToDeviceInformationService() {
    #expect(ReadOnlyInspection.name(service: "180A", characteristic: "2A25") == "Serial number")
    #expect(ReadOnlyInspection.name(service: "180F", characteristic: "2A25") == nil)
    #expect(ReadOnlyInspection.displayValue(service: "180A", characteristic: "2A25", data: Data("SYNTHETIC-123".utf8)) == "SYNTHETIC-123")
}

@Test func disconnectClearsPrivateIdentifiersAndConsumerFeatureState() {
    var state = AidConnection(id: UUID(), name: "Synthetic aid", phase: .connected)
    state.serialNumber = "SYNTHETIC-123"
    state.programBoostable = [1: true]
    state.speechBoosterEnabled = true; state.writableSpeechBooster = true
    state.groupActionPending = true
    state.clearLiveValues()
    #expect(state.serialNumber == nil && state.programBoostable.isEmpty)
    #expect(state.speechBoosterEnabled == nil && !state.writableSpeechBooster)
    #expect(!state.groupActionPending)
}

@Test func timeLeftRequiresFreshTelemetryAndCurrentConnection() throws {
    let service = UTLProtocol.Service(id: OticonBattery.serviceID, handle: 7, major: 2, minor: 0, status: 255)
    let telemetry = try OticonBattery.fastState(Data([0, 0, 0, 50, 0, 0, 0x2E, 0xE0, 0, 0, 3, 0xE8, 0x40]), service: service)
    var state = AidConnection(id: UUID(), name: "Synthetic aid", phase: .connected)
    state.batteryTelemetry = telemetry
    #expect(state.estimatedTimeLeftSeconds == nil)
    state.batteryTelemetryUpdatedAt = Date()
    #expect(state.estimatedTimeLeftSeconds == 43_200)
    state.batteryTelemetryUpdatedAt = Date().addingTimeInterval(-601)
    #expect(state.estimatedTimeLeftSeconds == nil)
    state.batteryTelemetryUpdatedAt = Date()
    state.phase = .disconnected
    #expect(state.estimatedTimeLeftSeconds == nil)
    state.clearLiveValues()
    #expect(state.batteryTelemetry == nil && state.batteryTelemetryUpdatedAt == nil)
}
