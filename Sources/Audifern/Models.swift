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
    var standardSoftwareRevision: String?
    var standardHardwareRevision: String?
    var softwareRevision: String? { standardSoftwareRevision ?? deviceMetadata?.softwareRevision }
    var hardwareRevision: String? { standardHardwareRevision ?? deviceMetadata?.hardwareRevision }
    var softwareRevisionSource: String? {
        if standardSoftwareRevision != nil { return "Device Information (2A28)" }
        return deviceMetadata?.softwareRevision == nil ? nil : "HIID (2019)"
    }
    var hardwareRevisionSource: String? {
        if standardHardwareRevision != nil { return "Device Information (2A27)" }
        return deviceMetadata?.hardwareRevision == nil ? nil : "HIID (2009)"
    }
    var deviceMetadata: OticonIdentification.Metadata?
    var deviceMetadataStatus: String?
    var batteryHealth: OticonBattery.Health?
    var coreDumpInfo: OticonDiagnostics.CoreDumpInfo?
    var advancedServices: [UTLProtocol.Service] = []
    var serialNumber: String?
    var ear: Int?
    var sinkAudioLocations: UInt32?
    var volume: OticonRemoteProtocol.Volume?
    var tinnitusVolume: OticonRemoteProtocol.Volume?
    var streamingVolume: OticonRemoteProtocol.Volume?
    var writableTinnitusVolume = false
    var writableStreamingVolume = false
    var tinnitusStatus: String?
    var streamingVolumeStatus: String?
    var tinnitusStatusFailed = false
    var streamingVolumeStatusFailed = false
    var volumeRanges: OticonRemoteProtocol.VolumeRanges?
    var programIDs: [Int] = []
    var activeProgram: Int?
    var programNames: [Int: String] = [:]
    var programBoostable: [Int: Bool] = [:]
    var programTinnitus: [Int: Bool] = [:]
    var programStreaming: [Int: Bool] = [:]
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
    var canChangeTinnitusVolume: Bool { canChangeAuxiliaryVolume(.tinnitus) }
    var canChangeStreamingVolume: Bool { canChangeAuxiliaryVolume(.streaming) }
    var canChangeMicrophoneEqualizer: Bool { isConnected && !actionPending && !advancedBusy && !groupActionPending && writableMicrophoneEqualizer && microphoneEqualizer != nil }
    var canChangeStreamingEqualizer: Bool { isConnected && !actionPending && !advancedBusy && !groupActionPending && writableStreamingEqualizer && streamingEqualizer != nil }
    var canChangeSpeechBooster: Bool {
        isConnected && !actionPending && !advancedBusy && !groupActionPending && writableSpeechBooster && speechBoosterEnabled != nil
            && activeProgram.flatMap { programBoostable[$0] } == true
    }
    var activeProgramName: String? { activeProgram.flatMap { programNames[$0] } }
    func auxiliaryVolume(_ source: AuxiliaryHearingControls.Source) -> OticonRemoteProtocol.Volume? {
        source == .tinnitus ? tinnitusVolume : streamingVolume
    }
    func auxiliaryRange(_ source: AuxiliaryHearingControls.Source) -> ClosedRange<Int>? {
        source == .tinnitus ? volumeRanges?.tinnitus : volumeRanges?.streaming
    }
    func auxiliaryProgramEligible(_ source: AuxiliaryHearingControls.Source) -> Bool? {
        guard let activeProgram else { return nil }
        if source == .tinnitus { return programTinnitus[activeProgram] }
        guard programTinnitus[activeProgram] == false else { return nil }
        return programStreaming[activeProgram]
    }
    func canChangeAuxiliaryVolume(_ source: AuxiliaryHearingControls.Source) -> Bool {
        let writable = source == .tinnitus ? writableTinnitusVolume : writableStreamingVolume
        guard isConnected, !actionPending, !advancedBusy, !groupActionPending, writable,
              auxiliaryProgramEligible(source) == true, let value = auxiliaryVolume(source),
              let range = auxiliaryRange(source) else { return false }
        return range.contains(value.level)
    }
    var sideLabel: String {
        if sinkAudioLocations == 1 { return "Left" }
        if sinkAudioLocations == 2 { return "Right" }
        return ear.map { "Side \($0)" } ?? "Hearing aid"
    }

    /// Namespaces each revision by its actual Device Information characteristic.
    /// A malformed update invalidates only that field; firmware never fills in
    /// an absent software revision.
    mutating func receiveRevision(service: String, characteristic: String, data: Data) -> Bool {
        guard let field = StandardGATT.revisionField(service: service, characteristic: characteristic) else { return false }
        let value = StandardGATT.informationString(data)
        switch field {
        case .firmware: firmware = value
        case .hardware: standardHardwareRevision = value
        case .software: standardSoftwareRevision = value
        }
        return true
    }

    func advertisesDeviceInformationCharacteristic(_ uuid: String) -> Bool {
        services.contains { service in
            HearingAidDiscovery.normalizedUUID(service.uuid) == StandardGATT.deviceInformationService
                && service.characteristics.contains { HearingAidDiscovery.normalizedUUID($0.uuid) == HearingAidDiscovery.normalizedUUID(uuid) }
        }
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
        standardSoftwareRevision = nil
        standardHardwareRevision = nil
        deviceMetadata = nil
        deviceMetadataStatus = nil
        batteryHealth = nil
        coreDumpInfo = nil
        advancedServices = []
        serialNumber = nil
        ear = nil
        sinkAudioLocations = nil
        volume = nil
        tinnitusVolume = nil; streamingVolume = nil
        writableTinnitusVolume = false; writableStreamingVolume = false
        tinnitusStatus = nil; streamingVolumeStatus = nil
        tinnitusStatusFailed = false; streamingVolumeStatusFailed = false
        volumeRanges = nil
        programIDs = []
        activeProgram = nil
        programNames = [:]
        programBoostable = [:]
        programTinnitus = [:]; programStreaming = [:]
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
    var isDemo = false
    var probeSeconds: Double?
    var probeOutput: String?
    var probeConnect: UUID?
    var backupOutput: String?
    var backupSeconds: Double = 90
    var error: String?
    var isProbe: Bool { probeSeconds != nil || probeOutput != nil || error != nil }
    var isBackup: Bool { backupOutput != nil }

    init(arguments: [String] = CommandLine.arguments) {
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--demo": isDemo = true
            case "--probe-seconds", "--probe-output", "--probe-connect", "--backup-output", "--backup-seconds":
                index += 1
                guard index < arguments.count else {
                    error = "Missing value for \(argument)."
                    return
                }
                let value = arguments[index]
                if argument == "--backup-output" {
                    guard !value.isEmpty else { error = "Backup output must be a new local file."; return }
                    backupOutput = value
                } else if argument == "--backup-seconds" {
                    guard let seconds = Double(value), seconds.isFinite, (10...300).contains(seconds) else {
                        error = "Backup timeout must be between 10 and 300 seconds."; return
                    }
                    backupSeconds = seconds
                } else if argument == "--probe-seconds" {
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
                if argument.hasPrefix("--probe-") || argument.hasPrefix("--backup-") {
                    error = "Unknown probe option: \(argument)."
                    return
                }
            }
            index += 1
        }
        if backupOutput != nil {
            guard !isDemo, probeSeconds == nil, probeOutput == nil, probeConnect == nil else {
                error = "Backup, preview and discovery-probe modes cannot be combined."; return
            }
        } else if arguments.contains("--backup-seconds") {
            error = "Backup mode requires --backup-output PATH."; return
        }
        if probeSeconds != nil || probeOutput != nil || probeConnect != nil {
            guard !isDemo else { error = "Preview and Bluetooth probe modes cannot be combined."; return }
            guard probeSeconds != nil, let output = probeOutput, !output.isEmpty else {
                error = "Probe mode requires --probe-seconds N and --probe-output PATH."
                return
            }
        }
    }
}
