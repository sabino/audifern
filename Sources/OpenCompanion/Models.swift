import Foundation
import CompanionCore

struct NearbyDevice: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int?
    var services: [String]
    var candidateReasons: [String]
    var companyID: UInt16?
    var lastSeen: Date
    var source: String
    var isConnectable: Bool?
    var isSystemConnected: Bool
    var isCandidate: Bool { !candidateReasons.isEmpty }
}

enum ConnectionPhase: String {
    case connecting, connected, disconnecting, disconnected, failed
    var label: String { rawValue.capitalized }
}

struct AidConnection: Identifiable {
    let id: UUID
    var name: String
    var phase: ConnectionPhase
    var connectedAt: Date?
    var lastValueAt: Date?
    var services: [GATTServiceInfo] = []
    var battery: Int?
    var batteryTelemetry: OticonBattery.State?
    var batteryTelemetryUpdatedAt: Date?
    var estimatedTimeLeftSeconds: TimeInterval? {
        guard isConnected, let updated = batteryTelemetryUpdatedAt,
              (0...(2 * OticonBattery.pollingIntervalSeconds)).contains(Date().timeIntervalSince(updated)) else { return nil }
        return batteryTelemetry?.estimatedTimeLeftSeconds
    }
    var manufacturer: String?
    var model: String?
    var firmware: String?
    var serialNumber: String?
    var ear: Int?
    var sinkAudioLocations: UInt32?
    var volume: OticonRemoteProtocol.Volume?
    var volumeRanges: OticonRemoteProtocol.VolumeRanges?
    var programIDs: [Int] = []
    var activeProgram: Int?
    var programNames: [Int: String] = [:]
    var programBoostable: [Int: Bool] = [:]
    var speechBoosterEnabled: Bool?
    var writableSpeechBooster = false
    var consumerStatus: String?
    var groupActionPending = false
    var microphoneEqualizer: OticonEqualizer.State?
    var streamingEqualizer: OticonEqualizer.State?
    var writableMicrophoneEqualizer = false
    var writableStreamingEqualizer = false
    var advancedBusy = false
    var advancedStatus: String?
    var writableVolume = false
    var writableProgram = false
    var actionPending = false
    var actionStatus: String?
    var actionFailed = false
    var error: String?

    var isConnected: Bool { phase == .connected }
    var canChangeVolume: Bool { isConnected && !actionPending && !advancedBusy && !groupActionPending && writableVolume && volume != nil && volumeRanges != nil }
    var canChangeProgram: Bool { isConnected && !actionPending && !advancedBusy && !groupActionPending && writableProgram && activeProgram != nil && !programIDs.isEmpty }
    var canChangeMicrophoneEqualizer: Bool { isConnected && !actionPending && !advancedBusy && !groupActionPending && writableMicrophoneEqualizer && microphoneEqualizer != nil }
    var canChangeStreamingEqualizer: Bool { isConnected && !actionPending && !advancedBusy && !groupActionPending && writableStreamingEqualizer && streamingEqualizer != nil }
    var canChangeSpeechBooster: Bool {
        isConnected && !actionPending && !advancedBusy && !groupActionPending && writableSpeechBooster && speechBoosterEnabled != nil
            && activeProgram.flatMap { programBoostable[$0] } == true
    }
    var activeProgramName: String? { activeProgram.flatMap { programNames[$0] } }
    var sideLabel: String {
        if sinkAudioLocations == 1 { return "Left" }
        if sinkAudioLocations == 2 { return "Right" }
        return ear.map { "Side \($0)" } ?? "Hearing aid"
    }

    mutating func clearLiveValues() {
        connectedAt = nil
        lastValueAt = nil
        battery = nil
        batteryTelemetry = nil
        batteryTelemetryUpdatedAt = nil
        manufacturer = nil
        model = nil
        firmware = nil
        serialNumber = nil
        ear = nil
        sinkAudioLocations = nil
        volume = nil
        volumeRanges = nil
        programIDs = []
        activeProgram = nil
        programNames = [:]
        programBoostable = [:]
        speechBoosterEnabled = nil
        writableSpeechBooster = false
        consumerStatus = nil
        groupActionPending = false
        microphoneEqualizer = nil
        streamingEqualizer = nil
        writableMicrophoneEqualizer = false
        writableStreamingEqualizer = false
        advancedBusy = false
        advancedStatus = nil
        writableVolume = false
        writableProgram = false
        actionPending = false
        actionStatus = nil
        actionFailed = false
        for serviceIndex in services.indices {
            for characteristicIndex in services[serviceIndex].characteristics.indices {
                services[serviceIndex].characteristics[characteristicIndex].value = nil
                services[serviceIndex].characteristics[characteristicIndex].isNotifying = false
            }
        }
    }
}

struct GATTServiceInfo: Identifiable, Equatable {
    let id: String
    let uuid: String
    let isPrimary: Bool
    var characteristics: [GATTCharacteristicInfo]
}

struct GATTCharacteristicInfo: Identifiable, Equatable {
    let id: String
    let uuid: String
    let properties: String
    var value: String?
    var isNotifying: Bool
}

struct SessionEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let event: String
    let message: String
    let details: [String: String]

    init(_ event: String, _ message: String, details: [String: String] = [:]) {
        self.id = UUID()
        self.timestamp = Date()
        self.event = event
        self.message = message
        self.details = details
    }
}

struct LaunchConfiguration: Sendable {
    var probeSeconds: Double?
    var probeOutput: String?
    var probeConnect: UUID?
    var error: String?
    var isProbe: Bool { probeSeconds != nil || probeOutput != nil || error != nil }

    init(arguments: [String] = CommandLine.arguments) {
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--probe-seconds", "--probe-output", "--probe-connect":
                index += 1
                guard index < arguments.count else {
                    error = "Missing value for \(argument)."
                    return
                }
                let value = arguments[index]
                if argument == "--probe-seconds" {
                    guard let seconds = Double(value), seconds.isFinite, seconds >= 1, seconds <= 300 else {
                        error = "Probe duration must be between 1 and 300 seconds."
                        return
                    }
                    probeSeconds = seconds
                } else if argument == "--probe-output" {
                    probeOutput = value
                } else {
                    guard let uuid = UUID(uuidString: value) else {
                        error = "--probe-connect requires an exact CoreBluetooth peripheral UUID."
                        return
                    }
                    probeConnect = uuid
                }
            default:
                // LaunchServices may add its own arguments to a GUI launch.
                if argument.hasPrefix("--probe-") {
                    error = "Unknown probe option: \(argument)."
                    return
                }
            }
            index += 1
        }
        if probeSeconds != nil || probeOutput != nil || probeConnect != nil {
            guard probeSeconds != nil, let output = probeOutput, !output.isEmpty else {
                error = "Probe mode requires --probe-seconds N and --probe-output PATH."
                return
            }
        }
    }
}
