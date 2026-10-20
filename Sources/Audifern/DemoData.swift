import CompanionCore
import Foundation

/// Deliberately synthetic fixtures. Preview startup never creates a Bluetooth
/// manager and never reads the user's audiograms, presets or authentication key.
@MainActor enum DemoData {
    static let leftID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let rightID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    static var devices: [NearbyDevice] {
        [leftID, rightID].map { id in
            .init(id: id, name: "Preview hearing aid", rssi: nil, services: [OticonRemoteProtocol.service],
                  candidateReasons: ["Synthetic preview"], companyID: nil, lastSeen: Date(), source: "Preview",
                  isConnectable: false, isSystemConnected: true)
        }
    }
    static var connections: [UUID: AidConnection] {
        Dictionary(uniqueKeysWithValues: [(leftID, true), (rightID, false)].map { id, left in
            var aid = AidConnection(id: id, name: "Preview hearing aid", phase: .connected)
            aid.model = "Preview RIC"; aid.manufacturer = "Sample"; aid.firmware = "Demo 1.0"
            aid.standardSoftwareRevision = "Demo 1.0"; aid.standardHardwareRevision = "Sample"
            aid.sinkAudioLocations = left ? 1 : 2
            aid.battery = left ? 76 : 68
            let charge: UInt32 = left ? 1600 : 1400
            var battery = Data()
            for number: UInt32 in [UInt32(aid.battery!), charge, 100] {
                battery.append(contentsOf: [UInt8(truncatingIfNeeded: number >> 24), UInt8(truncatingIfNeeded: number >> 16),
                                           UInt8(truncatingIfNeeded: number >> 8), UInt8(truncatingIfNeeded: number)])
            }
            battery.append(0x40)
            let service = UTLProtocol.Service(id: OticonBattery.serviceID, handle: 1, major: 2, minor: 0, status: 0xFF)
            aid.batteryTelemetry = try? OticonBattery.fastState(battery, service: service)
            aid.batteryTelemetryUpdatedAt = Date()
            aid.volume = .init(data: Data([0, 1])); aid.volumeRanges = .init(data: Data([0xFC, 4, 0, 18, 0xFB, 0]))
            aid.activeProgram = 0; aid.programIDs = [0]; aid.programNames = [0: "General"]
            aid.programBoostable = [0: true]; aid.programTinnitus = [0: false]; aid.programStreaming = [0: false]
            aid.speechBoosterEnabled = false
            aid.microphoneEqualizer = try? .init(rawSteps: Array(repeating: 0, count: 8), minimumSteps: Array(repeating: -6, count: 8),
                                               maximumSteps: Array(repeating: 6, count: 8), stepDB: 1)
            aid.streamingEqualizer = aid.microphoneEqualizer
            aid.tinnitusVolume = .init(data: Data([0, 1])); aid.streamingVolume = .init(data: Data([10, 0]))
            return (id, aid)
        })
    }
}

@MainActor final class PreviewNotificationDelivery: BatteryNotificationDelivery {
    func permission() async -> BatteryNotificationPermission { .notRequested }
    func requestPermission() async throws -> Bool { false }
    func containsNotification(identifier: String) async -> Bool { false }
    func deliver(_ notification: BatteryLocalNotification) async throws {}
    func cancelPendingBatteryNotifications() async {}
}
