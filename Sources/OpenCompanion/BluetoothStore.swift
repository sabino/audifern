import AppKit
import Combine
import CompanionCore
@preconcurrency import CoreBluetooth
import Foundation

@MainActor private final class PendingSetting {
    enum Stage { case acknowledgement, readback }
    let characteristic: CBCharacteristic
    let expected: Data
    let label: String
    var stage = Stage.acknowledgement
    var readbackAttempts = 0
    var timeout: Task<Void, Never>?
    init(characteristic: CBCharacteristic, expected: Data, label: String) {
        self.characteristic = characteristic
        self.expected = expected
        self.label = label
    }
}

@MainActor private final class AidLink {
    let peripheral: CBPeripheral
    var serviceIDs: [ObjectIdentifier: String] = [:]
    var characteristicIDs: [ObjectIdentifier: String] = [:]
    var remoteCharacteristics: [String: CBCharacteristic] = [:]
    var connectTimeout: Task<Void, Never>?
    var pending: PendingSetting?
    var utilityWrite: UtilityWrite?
    var utilityRead: UtilityRead?
    var utlCharacteristics: [String: CBCharacteristic] = [:]
    var utlInformation: UTLProtocol.GattInformation?
    var utlSession: UTLSession?
    var legacyEqualizerData: Data?
    var legacySpeechBoosterData: Data?
    var programInfoRequested = false
    var batteryPollTask: Task<Void, Never>?
    var batteryPollGeneration: UUID?
    var batteryZeroRetryCount = 0
    init(_ peripheral: CBPeripheral) { self.peripheral = peripheral }
}

@MainActor private final class UtilityWrite {
    let characteristic: CBCharacteristic
    var result: Result<Void, any Error>?
    init(_ characteristic: CBCharacteristic) { self.characteristic = characteristic }
}
@MainActor private final class UtilityRead {
    let characteristic: CBCharacteristic
    var result: Result<Data, any Error>?
    init(_ characteristic: CBCharacteristic) { self.characteristic = characteristic }
}

/// Independent, main-queue connections. Probe mode cannot issue hearing-setting writes.
@MainActor
final class BluetoothStore: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    @Published private(set) var bluetoothStatus = "Starting Bluetooth…"
    @Published private(set) var isPoweredOn = false
    @Published private(set) var isScanning = false
    @Published private(set) var devices: [NearbyDevice] = []
    @Published private(set) var selectedPeripheralID: UUID?
    @Published private(set) var connections: [UUID: AidConnection] = [:]
    @Published private(set) var events: [SessionEvent] = []
    @Published private(set) var lastError: String?
    @Published private(set) var linkedActionPending = false
    @Published private(set) var linkedActionStatus: String?
    @Published private(set) var linkedActionFailed = false
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var links: [UUID: AidLink] = [:]
    private var loggedDiscoveryAt: [UUID: Date] = [:]
    private var scanTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var pendingScan = false
    private var probeConfiguration: LaunchConfiguration?
    private var recorder: ProbeRecorder?
    private var probeHasAttemptedConnect = false

    var orderedConnections: [AidConnection] {
        connections.values.sorted {
            if $0.isConnected != $1.isConnected { return $0.isConnected }
            if $0.ear != $1.ear { return ($0.ear ?? 99) < ($1.ear ?? 99) }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    var selectedConnection: AidConnection? { selectedPeripheralID.flatMap { connections[$0] } }
    var connectedCount: Int { connections.values.filter(\.isConnected).count }

    /// Shortcut only for two recovered hearing candidates with matching names or the known remote service.
    var pairCandidateIDs: [UUID] {
        let recovered = devices.filter { $0.isSystemConnected && $0.isCandidate }
        let groups = Dictionary(grouping: recovered) { $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        let matches = groups.filter { !$0.key.isEmpty && $0.value.count == 2 }
        if matches.count == 1, let group = matches.values.first { return group.map(\.id).sorted { $0.uuidString < $1.uuidString } }
        let vendor = recovered.filter { $0.services.map(HearingAidDiscovery.normalizedUUID).contains(OticonRemoteProtocol.service) }
        return vendor.count == 2 ? vendor.map(\.id).sorted { $0.uuidString < $1.uuidString } : []
    }
    var connectedPair: [AidConnection] {
        let ids = pairCandidateIDs
        guard ids.count == 2 else { return [] }
        let pair = ids.compactMap { connections[$0] }
        return pair.count == 2 && pair.allSatisfy(\.isConnected) ? pair : []
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }
    func select(_ id: UUID) { selectedPeripheralID = id }

    func startProbe(_ configuration: LaunchConfiguration) {
        guard let seconds = configuration.probeSeconds, let path = configuration.probeOutput else { return }
        do { recorder = try ProbeRecorder(path: path) }
        catch {
            fputs("Cannot create private probe output: \(error.localizedDescription)\n", stderr)
            exit(2)
        }
        probeConfiguration = configuration
        record("probe_started", "Read-only Bluetooth probe", details: ["duration_seconds": String(seconds), "connect_uuid": configuration.probeConnect?.uuidString ?? "none", "scope": "discovery; exact-UUID connection; allowlisted read-only values and notifications; no setting writes"])
        pendingScan = true
        if isPoweredOn { startScan(seconds: seconds) }
        probeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.stopScan()
            self.disconnect()
            self.record("probe_finished", "Probe duration complete", details: ["peripherals_seen": String(self.devices.count)])
            self.recorder?.finish()
            self.recorder = nil
            NSApplication.shared.terminate(nil)
        }
    }
    func startScan(seconds: Double = 15) {
        guard isPoweredOn else { pendingScan = true; record("scan_waiting", "Waiting for Bluetooth permission and power"); return }
        pendingScan = false
        scanTask?.cancel()
        recoverConnectedPeripherals()
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        record("scan_started", "Scanning nearby BLE advertisements", details: ["duration_seconds": String(seconds)])
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.stopScan()
        }
    }
    func stopScan() {
        scanTask?.cancel(); scanTask = nil
        guard isScanning else { return }
        central.stopScan(); isScanning = false
        record("scan_stopped", "Scan stopped")
    }
    func connectPair() {
        guard probeConfiguration == nil else { return }
        for id in pairCandidateIDs { connect(to: id) }
    }
    func connect(to id: UUID) {
        guard isPoweredOn, let target = peripherals[id], links[id] == nil else { return }
        let link = AidLink(target)
        links[id] = link
        connections[id] = AidConnection(id: id, name: target.name ?? devices.first(where: { $0.id == id })?.name ?? "Hearing aid", phase: .connecting)
        selectedPeripheralID = id
        target.delegate = self
        record("connection_requested", "Connecting to \(target.name ?? "device")", details: ["uuid": id.uuidString])
        central.connect(target, options: nil)
        link.connectTimeout = Task { [weak self, weak link] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, let link, self.links[id] === link, self.connections[id]?.phase == .connecting else { return }
            self.connections[id]?.error = "Connection timed out. The device may be busy with another host."
            self.record("connection_timeout", "Connection did not complete within 20 seconds", details: ["uuid": id.uuidString])
            self.disconnect(id)
        }
    }
    func disconnect(_ id: UUID) {
        guard let link = links[id] else { return }
        link.connectTimeout?.cancel(); link.pending?.timeout?.cancel()
        connections[id]?.clearLiveValues()
        connections[id]?.phase = .disconnecting
        connections[id]?.actionStatus = nil
        central.cancelPeripheralConnection(link.peripheral)
        record("disconnect_requested", "Disconnect requested", details: ["uuid": id.uuidString])
    }
    func disconnect() { for id in Array(links.keys) { disconnect(id) } }
    func clearEvents() { events = [] }
    func refresh(_ id: UUID) {
        guard let link = liveLink(id), connections[id]?.actionPending == false,
              connections[id]?.advancedBusy == false, connections[id]?.groupActionPending == false else { return }
        connections[id]?.error = nil
        for service in link.peripheral.services ?? [] {
            for characteristic in service.characteristics ?? [] { readIfAllowed(characteristic, service: service, link: link) }
        }
        record("refresh_requested", "Refreshing current hearing-aid values", details: ["uuid": id.uuidString])
        // Standard refresh reuses an already authenticated channel only.
        // It never opens or reauthenticates an advanced channel by itself.
        if link.utlSession?.isReady == true { refreshConsumerFeatures(id) }
    }
    func adjustVolume(_ id: UUID, by delta: Int) {
        guard delta == -1 || delta == 1, let state = connections[id], state.canChangeVolume,
              let volume = state.volume, let ranges = state.volumeRanges,
              let payload = OticonRemoteProtocol.volumePayload(level: volume.level + delta, muted: volume.muted, reportedRange: ranges.main) else { return }
        writeSetting(id, characteristicUUID: OticonRemoteProtocol.mainVolume, data: payload, label: "Volume \(volume.level + delta)")
    }
    func setMuted(_ id: UUID, muted: Bool) {
        guard let state = connections[id], state.canChangeVolume, let volume = state.volume, let ranges = state.volumeRanges,
              let payload = OticonRemoteProtocol.volumePayload(level: volume.level, muted: muted, reportedRange: ranges.main) else { return }
        writeSetting(id, characteristicUUID: OticonRemoteProtocol.mainVolume, data: payload, label: muted ? "Mute" : "Unmute")
    }
    func selectProgram(_ id: UUID, program: Int) {
        guard let state = connections[id], state.canChangeProgram, state.activeProgram != program,
              let payload = OticonRemoteProtocol.programPayload(id: program, reportedPrograms: state.programIDs) else { return }
        writeSetting(id, characteristicUUID: OticonRemoteProtocol.activeProgram, data: payload, label: "Program \(program)")
    }

    func applyLinkedVolume(by delta: Int) {
        guard delta == -1 || delta == 1 else { return }
        performLinkedChange(delta: delta, muted: nil)
    }
    func setLinkedMuted(_ muted: Bool) { performLinkedChange(delta: nil, muted: muted) }

    private func performLinkedChange(delta: Int?, muted: Bool?) {
        let pair = connectedPair
        guard probeConfiguration == nil, !linkedActionPending, pair.count == 2, pair.allSatisfy(\.canChangeVolume) else { return }
        let targets = pair.compactMap { state -> (UUID, AidLink)? in liveLink(state.id).map { (state.id, $0) } }
        guard targets.count == 2 else { return }
        linkedActionPending = true; linkedActionFailed = false; linkedActionStatus = "Reading both hearing aids…"
        for (id, _) in targets { connections[id]?.groupActionPending = true }
        Task {
            defer {
                self.linkedActionPending = false
                for (id, _) in targets { self.connections[id]?.groupActionPending = false }
            }
            var completed = 0
            do {
                for (id, link) in targets {
                    guard self.liveLink(id) === link, let characteristic = link.remoteCharacteristics[OticonRemoteProtocol.mainVolume] else { throw UTLSession.SessionError.disconnected }
                    _ = try await self.readUtility(id, characteristic: characteristic)
                }
                let states = targets.compactMap { self.connections[$0.0] }
                let snapshots = states.compactMap { state -> LinkedHearingControls.Aid? in
                    guard let volume = state.volume, let ranges = state.volumeRanges, state.writableVolume,
                          !state.actionPending, !state.advancedBusy else { return nil }
                    return .init(level: volume.level, muted: volume.muted, range: ranges.main)
                }
                guard states.count == 2, let controls = LinkedHearingControls(aids: snapshots) else {
                    throw UTLSession.SessionError.unavailable("Both aids need current volume and range information.")
                }
                let levels = delta.flatMap { controls.levels(adjustingBy: $0) } ?? (delta == nil ? snapshots.map(\.level) : nil)
                guard let levels, levels.count == 2 else { throw UTLSession.SessionError.unavailable("One hearing aid has reached its volume limit.") }
                let payloads = try states.enumerated().map { index, state -> Data in
                    guard let range = state.volumeRanges?.main, let current = state.volume,
                          let payload = OticonRemoteProtocol.volumePayload(level: levels[index], muted: muted ?? current.muted, reportedRange: range) else {
                        throw UTLSession.SessionError.unavailable("Linked change is outside an aid's reported range.")
                    }
                    return payload
                }
                for (index, target) in targets.enumerated() {
                    let (id, link) = target
                    guard self.liveLink(id) === link, self.connections[id]?.activeProgram == states[index].activeProgram,
                          let range = self.connections[id]?.volumeRanges?.main, range.contains(levels[index]) else {
                        throw UTLSession.SessionError.unavailable("An aid's connection, program or range changed during the linked request.")
                    }
                    try await self.awaitSetting(id, characteristicUUID: OticonRemoteProtocol.mainVolume, data: payloads[index],
                                                label: muted.map { $0 ? "Linked mute" : "Linked unmute" } ?? "Linked volume")
                    completed += 1
                }
                self.linkedActionStatus = "Both hearing aids confirmed the linked change."
            } catch {
                self.linkedActionFailed = true
                self.linkedActionStatus = completed == 0 ? "Linked change not confirmed: \(error.localizedDescription)"
                    : "Linked change stopped after \(completed) confirmed aid. \(error.localizedDescription)"
            }
        }
    }

    /// Selects only the metadata cursor, never the active listening program.
    func refreshProgramInfo(_ id: UUID) {
        guard probeConfiguration == nil, let link = liveLink(id), link.pending == nil,
              connections[id]?.advancedBusy == false, connections[id]?.groupActionPending == false,
              let programs = connections[id]?.programIDs, !programs.isEmpty else { return }
        connections[id]?.advancedBusy = true
        connections[id]?.advancedStatus = "Reading program names…"
        Task { [weak self, weak link] in
            guard let self, let link else { return }
            var result: [Int: String] = [:]
            var boostable: [Int: Bool] = [:]
            var queryError: (any Error)?
            do {
                guard let selector = link.remoteCharacteristics[OticonProgramInfo.selector],
                      let information = link.remoteCharacteristics[OticonProgramInfo.information] else {
                    throw UTLSession.SessionError.unavailable("Program metadata is not exposed by this aid.")
                }
                for program in programs {
                    guard let byte = UInt8(exactly: program), byte != 255 else { continue }
                    try await self.writeUtility(id, characteristic: selector, data: Data([byte]))
                    let metadata = try await self.readUtility(id, characteristic: information)
                    let decoded = try OticonProgramInfo.Program(data: metadata, id: program)
                    if !decoded.label.isEmpty { result[program] = decoded.label }
                    boostable[program] = decoded.boostable
                }
            } catch { queryError = error }
            // The installed client releases its metadata cursor with 0xff.
            if let selector = link.remoteCharacteristics[OticonProgramInfo.selector], self.liveLink(id) === link {
                do { try await self.writeUtility(id, characteristic: selector, data: Data([255])) }
                catch { if queryError == nil { queryError = error } }
            }
            guard self.liveLink(id) === link else { return }
            self.connections[id]?.programNames.merge(result) { _, new in new }
            self.connections[id]?.programBoostable.merge(boostable) { _, new in new }
            self.connections[id]?.advancedBusy = false
            self.connections[id]?.advancedStatus = queryError.map { "Program names: \($0.localizedDescription)" } ?? "Program names read from hearing aid."
            self.record("program_metadata", queryError == nil ? "Program names read from hearing aid" : "Program metadata query incomplete", details: ["uuid": id.uuidString, "count": String(result.count)])
        }
    }

    /// Explicit opt-in: opens one free UTL channel, authenticates locally, and
    /// performs service discovery and consumer-EQ reads. No fitting transaction.
    func refreshAdvanced(_ id: UUID, keyURL: URL? = nil) {
        guard probeConfiguration == nil, let link = liveLink(id), link.pending == nil, connections[id]?.advancedBusy == false, connections[id]?.groupActionPending == false else { return }
        connections[id]?.advancedBusy = true
        connections[id]?.advancedStatus = "Loading advanced controls…"
        Task { [weak self, weak link] in
            guard let self, let link else { return }
            defer { if self.liveLink(id) === link { self.connections[id]?.advancedBusy = false } }
            do {
                if let characteristic = link.remoteCharacteristics[OticonEqualizer.legacyCharacteristic], characteristic.properties.contains(.read) {
                    _ = try await self.readUtility(id, characteristic: characteristic)
                }
                let session: UTLSession
                if let existing = link.utlSession, existing.isReady { session = existing }
                else {
                    guard let information = link.utlCharacteristics[UTLProtocol.information],
                          let control = link.utlCharacteristics[UTLProtocol.control] else {
                        throw UTLSession.SessionError.unavailable("This aid does not expose the advanced transport.")
                    }
                    let info = try UTLProtocol.GattInformation(data: try await self.readUtility(id, characteristic: information))
                    let key = try UTLSession.loadKey(keyURL ?? UTLSession.defaultKeyURL)
                    session = try UTLSession(info: info, physicalATTMTU: link.peripheral.maximumWriteValueLength(for: .withResponse) + 3, progress: { [weak self, weak link] stage in
                        guard let self, let link, self.liveLink(id) === link else { return }
                        if !stage.hasPrefix("Consumer command ") {
                            self.connections[id]?.advancedStatus = stage == "Opening advanced channel"
                                ? "Connecting advanced controls…" : "Reading device controls…"
                        }
                        self.record("advanced_progress", stage, details: ["uuid": id.uuidString])
                    }, diagnostic: { [weak self, weak link] message in
                        guard let self, let link, self.liveLink(id) === link else { return }
                        self.record("advanced_eq_diagnostic", message, details: ["uuid": id.uuidString])
                    }, batteryUpdate: { [weak self, weak link] telemetry in
                        guard let self, let link, self.liveLink(id) === link, link.utlSession?.isReady == true else { return }
                        self.updateBatteryTelemetry(id, telemetry: telemetry)
                    }) { [weak self, weak link] uuid, data in
                        guard let self, let link, self.liveLink(id) === link, let characteristic = link.utlCharacteristics[uuid] else { throw UTLSession.SessionError.disconnected }
                        try await self.writeUtility(id, characteristic: characteristic, data: data)
                    }
                    guard let output = link.utlCharacteristics[UTLProtocol.outputs[Int(session.channel)]] else { throw UTLSession.SessionError.unavailable("Advanced channel output is absent.") }
                    link.utlSession = session
                    try await self.subscribeUtility(id, characteristic: control)
                    try await self.subscribeUtility(id, characteristic: output)
                    try await session.start(key: key)
                    self.record("advanced_authenticated", "Advanced channel authenticated; service registry read", details: ["uuid": id.uuidString, "services": session.services.map { String(format: "%08X/%u.%u", $0.id, $0.major, $0.minor) }.joined(separator: ",")])
                }
                guard let service = session.services.first(where: { UTLAdvanced.supportsEqualizer($0, microphone: false) }) else { throw UTLSession.SessionError.unavailable("No supported equalizer contract was advertised.") }
                let step: Double
                if service.major >= 2 { step = try await session.equalizerStep() }
                else {
                    // V1.1/V1.2 consumer readers use the historical scale and
                    // fixed UI limits. Their get_info map remains diagnostic.
                    _ = try? await session.equalizerStep()
                    step = OticonEqualizer.defaultStepDB
                }
                if UTLAdvanced.supportsEqualizer(service, microphone: true) {
                    self.connections[id]?.microphoneEqualizer = try await session.equalizer(microphone: true, stepDB: step)
                    self.connections[id]?.writableMicrophoneEqualizer = true
                }
                self.connections[id]?.streamingEqualizer = try await session.equalizer(microphone: false, stepDB: step)
                self.connections[id]?.writableStreamingEqualizer = true
                self.connections[id]?.advancedStatus = "Advanced equalizers read from hearing aid."
                await self.readConsumerFeatures(id, link: link, session: session)
            } catch {
                if let session = link.utlSession { await session.stop(); link.utlSession = nil }
                self.invalidateEqualizer(id, microphone: true)
                self.invalidateEqualizer(id, microphone: false)
                self.invalidateConsumerFeatures(id, link: link)
                // A prior UTL value is not valid evidence for legacy fallback.
                // Only a new, validated 16-byte read can re-enable streaming EQ.
                if let characteristic = link.remoteCharacteristics[OticonEqualizer.legacyCharacteristic], characteristic.properties.contains(.read) {
                    _ = try? await self.readUtility(id, characteristic: characteristic)
                }
                self.connections[id]?.advancedStatus = "Advanced controls: \(UTLSession.describe(error))"
                self.record("advanced_unavailable", "Advanced control read stopped: \(UTLSession.describe(error))", details: ["uuid": id.uuidString])
            }
        }
    }

    /// Read-only consumer feature refresh. Reuses a current session without
    /// changing EQ or writing either ear's consumer settings.
    func refreshConsumerFeatures(_ id: UUID) {
        guard probeConfiguration == nil, let link = liveLink(id), link.pending == nil,
              connections[id]?.advancedBusy == false, connections[id]?.groupActionPending == false else { return }
        guard let session = link.utlSession, session.isReady else { refreshAdvanced(id); return }
        connections[id]?.advancedBusy = true
        Task {
            defer { if self.liveLink(id) === link { self.connections[id]?.advancedBusy = false } }
            await self.readConsumerFeatures(id, link: link, session: session)
        }
    }

    private func readConsumerFeatures(_ id: UUID, link: AidLink, session: UTLSession) async {
        var failures: [String] = []
        if session.supportsBatteryTelemetry {
            do {
                let telemetry = try await session.batteryTelemetry()
                guard liveLink(id) === link else { return }
                updateBatteryTelemetry(id, telemetry: telemetry)
                link.batteryZeroRetryCount = telemetry.hasCorruptZeroTelemetry ? link.batteryZeroRetryCount + 1 : 0
                startBatteryPolling(id, link: link)
            } catch {
                connections[id]?.batteryTelemetry = nil
                connections[id]?.batteryTelemetryUpdatedAt = nil
                failures.append("Battery telemetry: \(UTLSession.describe(error))")
            }
        }
        if session.supportsIdentification, connections[id]?.serialNumber == nil {
            do {
                let identity = try await session.identification()
                guard liveLink(id) === link else { return }
                connections[id]?.serialNumber = identity.serialNumber
                record("device_identification_read", "Hearing aid identification read", details: ["uuid": id.uuidString])
            } catch {
                failures.append("Device identification: \(UTLSession.describe(error))")
            }
        }
        if session.supportsSpeechBooster {
            do {
                let state = try await session.speechBooster()
                guard liveLink(id) === link else { return }
                connections[id]?.speechBoosterEnabled = state.isEnabled
                connections[id]?.writableSpeechBooster = true
                record("speech_booster_read", "Speech Booster state read from hearing aid", details: ["uuid": id.uuidString])
            } catch {
                connections[id]?.speechBoosterEnabled = nil
                connections[id]?.writableSpeechBooster = false
                failures.append("Speech Booster: \(UTLSession.describe(error))")
            }
        } else {
            connections[id]?.speechBoosterEnabled = nil
            connections[id]?.writableSpeechBooster = false
            failures.append("Speech Booster is not available through this aid's supported consumer contract.")
        }
        if !session.isReady {
            await session.stop()
            if link.utlSession === session { link.utlSession = nil }
            invalidateEqualizer(id, microphone: true); invalidateEqualizer(id, microphone: false)
            invalidateConsumerFeatures(id, link: link)
            failures.append("Device features need a refresh because the advanced channel closed.")
        }
        guard liveLink(id) === link else { return }
        connections[id]?.consumerStatus = failures.isEmpty ? "Device features read from hearing aid." : failures.joined(separator: " ")
    }

    private func updateBatteryTelemetry(_ id: UUID, telemetry: OticonBattery.State) {
        connections[id]?.batteryTelemetry = telemetry
        connections[id]?.batteryTelemetryUpdatedAt = Date()
        if let percentage = telemetry.percentage { connections[id]?.battery = percentage }
        record("battery_telemetry", "Battery telemetry read from hearing aid", details: ["uuid": id.uuidString])
    }
    private func startBatteryPolling(_ id: UUID, link: AidLink) {
        guard link.batteryPollTask == nil else { return }
        let generation = UUID(); link.batteryPollGeneration = generation
        link.batteryPollTask = Task { [weak self, weak link] in
            guard let self, let link else { return }
            defer {
                if link.batteryPollGeneration == generation {
                    link.batteryPollTask = nil; link.batteryPollGeneration = nil
                }
            }
            while !Task.isCancelled {
                guard self.liveLink(id) === link, link.utlSession?.isReady == true else { return }
                let retryingZero = self.connections[id]?.batteryTelemetry?.hasCorruptZeroTelemetry == true && link.batteryZeroRetryCount < 12
                do { try await Task.sleep(for: .seconds(retryingZero ? 5 : OticonBattery.pollingIntervalSeconds)) }
                catch { return }
                guard self.liveLink(id) === link, link.utlSession?.isReady == true else { return }
                if self.connections[id]?.advancedBusy == false && self.connections[id]?.actionPending == false && self.connections[id]?.groupActionPending == false {
                    guard let session = link.utlSession else { return }
                    self.connections[id]?.advancedBusy = true
                    await self.readConsumerFeatures(id, link: link, session: session)
                    if self.liveLink(id) === link { self.connections[id]?.advancedBusy = false }
                }
            }
        }
    }

    func setSpeechBooster(_ id: UUID, enabled: Bool) {
        setSpeechBoosters([id], enabled: enabled)
    }
    func setSpeechBoosters(_ ids: [UUID], enabled: Bool) {
        performConsumerChange(ids, change: .speechBooster(enabled))
    }

    func setMicrophoneEqualizer(_ id: UUID, bandsDB: [Double]) {
        setEqualizer(id, microphone: true, bandsDB: bandsDB)
    }
    func setStreamingEqualizer(_ id: UUID, bandsDB: [Double]) {
        setEqualizer(id, microphone: false, bandsDB: bandsDB)
    }
    private func setEqualizer(_ id: UUID, microphone: Bool, bandsDB: [Double]) {
        setEqualizers([id], microphone: microphone, bandsDB: bandsDB)
    }
    func setEqualizers(_ ids: [UUID], microphone: Bool, bandsDB: [Double]) {
        performConsumerChange(ids, change: .equalizer(microphone: microphone, bandsDB: bandsDB))
    }
    func selectPrograms(_ ids: [UUID], program: Int) {
        performConsumerChange(ids, change: .program(program))
    }
    func restoreSoundDefaults(_ ids: [UUID], scope: ConsumerControlPlan.ResetScope) {
        performConsumerChange(ids, change: .restore(scope))
    }

    private func performConsumerChange(_ ids: [UUID], change: ConsumerControlPlan.Change) {
        guard probeConfiguration == nil, !linkedActionPending else { return }
        let plan: ConsumerControlPlan
        let targets = ids.compactMap { id in liveLink(id).map { (id, $0) } }
        do {
            guard targets.count == ids.count else { throw UTLSession.SessionError.disconnected }
            plan = try ConsumerControlPlan(aids: ids.compactMap { connections[$0] }, change: change)
        } catch {
            linkedActionFailed = true; linkedActionStatus = "No changes sent. \(error.localizedDescription)"
            return
        }
        linkedActionPending = true; linkedActionFailed = false
        linkedActionStatus = "Checking sound controls…"
        for id in ids { connections[id]?.groupActionPending = true }
        Task {
            defer {
                self.linkedActionPending = false
                for (id, link) in targets where self.liveLink(id) === link { self.connections[id]?.groupActionPending = false }
            }
            let outcome = await ConsumerControlExecutor.run(plan, validate: { step in
                guard let original = targets.first(where: { $0.0 == step.aidID })?.1,
                      self.liveLink(step.aidID) === original else { throw UTLSession.SessionError.disconnected }
                // Detect changes made on the aid or by another client, too.
                if let program = original.remoteCharacteristics[OticonRemoteProtocol.activeProgram] {
                    _ = try await self.readUtility(step.aidID, characteristic: program)
                }
                guard let state = self.connections[step.aidID] else { throw UTLSession.SessionError.disconnected }
                try step.validate(state)
            }, apply: { step in
                self.linkedActionStatus = "\(step.side): changing \(step.setting.label.lowercased())…"
                do {
                    switch step.setting {
                    case .volume(let level, let muted):
                        guard let range = self.connections[step.aidID]?.volumeRanges?.main,
                              let payload = OticonRemoteProtocol.volumePayload(level: level, muted: muted, reportedRange: range) else {
                            throw UTLSession.SessionError.unavailable("Volume limits changed.")
                        }
                        try await self.awaitSetting(step.aidID, characteristicUUID: OticonRemoteProtocol.mainVolume, data: payload, label: "Default volume and mute")
                    case .equalizer(let microphone, let steps, _):
                        try await self.applyEqualizer(step.aidID, microphone: microphone, steps: steps)
                        self.connections[step.aidID]?.advancedStatus = "\(microphone ? "Microphone" : "Streaming") EQ confirmed by hearing aid."
                    case .speechBooster(let enabled):
                        try await self.applySpeechBooster(step.aidID, enabled: enabled)
                    case .program(let program):
                        guard let state = self.connections[step.aidID],
                              let payload = OticonRemoteProtocol.programPayload(id: program, reportedPrograms: state.programIDs) else {
                            throw UTLSession.SessionError.unavailable("Program availability changed.")
                        }
                        try await self.awaitSetting(step.aidID, characteristicUUID: OticonRemoteProtocol.activeProgram, data: payload, label: "Program")
                    }
                } catch {
                    if case .equalizer(let microphone, _, _) = step.setting,
                       let original = targets.first(where: { $0.0 == step.aidID })?.1, self.liveLink(step.aidID) === original {
                        self.invalidateEqualizer(step.aidID, microphone: microphone)
                        self.connections[step.aidID]?.advancedStatus = "EQ not confirmed: \(UTLSession.describe(error))"
                    }
                    throw error
                }
            })
            self.linkedActionStatus = outcome.message
            self.linkedActionFailed = !outcome.succeeded
            self.record(outcome.succeeded ? "consumer_changes_confirmed" : "consumer_changes_stopped", outcome.message)
        }
    }

    private func applySpeechBooster(_ id: UUID, enabled: Bool) async throws {
        guard let link = liveLink(id) else { throw UTLSession.SessionError.disconnected }
        do {
            if let session = link.utlSession, session.isReady, session.supportsSpeechBooster {
                let confirmed = try await session.setSpeechBooster(enabled: enabled)
                guard liveLink(id) === link else { throw UTLSession.SessionError.disconnected }
                connections[id]?.speechBoosterEnabled = confirmed.isEnabled
            } else if let characteristic = link.remoteCharacteristics[OticonSpeechBooster.legacyCharacteristic] {
                let fresh = try await readUtility(id, characteristic: characteristic)
                let payload = try OticonSpeechBooster.legacyPayload(current: fresh, enabled: enabled)
                try await awaitSetting(id, characteristicUUID: OticonSpeechBooster.legacyCharacteristic,
                                       data: payload, label: "Speech Booster", allowWithoutResponse: true)
            } else { throw UTLSession.SessionError.unavailable("Load SpeechBooster controls before changing them.") }
            connections[id]?.consumerStatus = "SpeechBooster \(enabled ? "on" : "off") confirmed by hearing aid."
            record("setting_confirmed", "SpeechBooster \(enabled ? "on" : "off") confirmed by hearing aid", details: ["uuid": id.uuidString])
        } catch {
            if liveLink(id) === link, let session = link.utlSession, !session.isReady {
                await session.stop()
                if link.utlSession === session { link.utlSession = nil }
                invalidateEqualizer(id, microphone: true); invalidateEqualizer(id, microphone: false)
                invalidateConsumerFeatures(id, link: link)
            }
            if liveLink(id) === link {
                connections[id]?.speechBoosterEnabled = nil
                connections[id]?.writableSpeechBooster = false
                connections[id]?.consumerStatus = "SpeechBooster not confirmed: \(UTLSession.describe(error))"
            }
            throw error
        }
    }

    /// Serial, verified application of an app-local preset. A different fitted
    /// program must be selected explicitly and re-read before applying a preset.
    func applySoundSettings(_ id: UUID, program: Int, volume: Int, muted: Bool,
                            microphoneSteps: [Int]? = nil, streamingSteps: [Int]? = nil) async throws {
        guard probeConfiguration == nil, let state = connections[id], state.isConnected, !state.actionPending, !state.advancedBusy, !state.groupActionPending,
              state.activeProgram == program, let ranges = state.volumeRanges, state.volume != nil,
              let payload = OticonRemoteProtocol.volumePayload(level: volume, muted: muted, reportedRange: ranges.main) else {
            throw UTLSession.SessionError.unavailable("Select the preset's existing program and refresh its controls before applying.")
        }
        if let microphoneSteps {
            guard state.canChangeMicrophoneEqualizer, let eq = state.microphoneEqualizer else { throw UTLSession.SessionError.unavailable("Microphone EQ must be loaded first.") }
            try eq.validate(microphoneSteps)
        }
        if let streamingSteps {
            guard state.canChangeStreamingEqualizer, let eq = state.streamingEqualizer else { throw UTLSession.SessionError.unavailable("Streaming EQ must be loaded first.") }
            try eq.validate(streamingSteps)
        }
        connections[id]?.advancedBusy = true
        defer { connections[id]?.advancedBusy = false }
        do {
            try await awaitSetting(id, characteristicUUID: OticonRemoteProtocol.mainVolume, data: payload, label: "Preset volume")
            if let microphoneSteps { try await applyEqualizer(id, microphone: true, steps: microphoneSteps) }
            if let streamingSteps { try await applyEqualizer(id, microphone: false, steps: streamingSteps) }
            connections[id]?.advancedStatus = "All preset settings confirmed by hearing aid."
        } catch {
            if microphoneSteps != nil { invalidateEqualizer(id, microphone: true) }
            if streamingSteps != nil { invalidateEqualizer(id, microphone: false) }
            connections[id]?.advancedStatus = "Preset apply stopped; earlier confirmed settings may already be applied. \(error.localizedDescription)"
            throw error
        }
    }

    private func applyEqualizer(_ id: UUID, microphone: Bool, steps: [Int]) async throws {
        guard let link = liveLink(id), let state = connections[id], let expected = microphone ? state.microphoneEqualizer : state.streamingEqualizer else { throw UTLSession.SessionError.disconnected }
        try expected.validate(steps)
        if let session = link.utlSession, session.isReady,
           session.services.contains(where: { UTLAdvanced.supportsEqualizer($0, microphone: microphone) }) {
            let confirmed: OticonEqualizer.State
            do { confirmed = try await session.setEqualizer(microphone: microphone, steps: steps, expected: expected) }
            catch {
                if liveLink(id) === link, !session.isReady {
                    await session.stop()
                    if link.utlSession === session { link.utlSession = nil }
                    invalidateEqualizer(id, microphone: true)
                    invalidateEqualizer(id, microphone: false)
                    invalidateConsumerFeatures(id, link: link)
                }
                throw error
            }
            guard liveLink(id) === link else { throw UTLSession.SessionError.disconnected }
            if microphone { connections[id]?.microphoneEqualizer = confirmed }
            else { connections[id]?.streamingEqualizer = confirmed }
            record("setting_confirmed", "\(microphone ? "Microphone" : "Streaming") EQ confirmed by hearing aid", details: ["uuid": id.uuidString])
        } else if !microphone, let characteristic = link.remoteCharacteristics[OticonEqualizer.legacyCharacteristic] {
            let fresh = try await readUtility(id, characteristic: characteristic)
            let payload = try OticonEqualizer.legacyStreamingPayload(current: fresh, steps: steps)
            try await awaitSetting(id, characteristicUUID: OticonEqualizer.legacyCharacteristic, data: payload, label: "Streaming EQ")
        } else { throw UTLSession.SessionError.unavailable("Advanced EQ is not connected. Load advanced controls again.") }
    }
    private func invalidateEqualizer(_ id: UUID, microphone: Bool) {
        if microphone {
            connections[id]?.microphoneEqualizer = nil
            connections[id]?.writableMicrophoneEqualizer = false
        } else {
            connections[id]?.streamingEqualizer = nil
            connections[id]?.writableStreamingEqualizer = false
            links[id]?.legacyEqualizerData = nil
        }
    }
    private func invalidateConsumerFeatures(_ id: UUID, link: AidLink) {
        connections[id]?.speechBoosterEnabled = nil
        connections[id]?.writableSpeechBooster = false
        connections[id]?.batteryTelemetry = nil
        connections[id]?.batteryTelemetryUpdatedAt = nil
        link.legacySpeechBoosterData = nil
        link.batteryPollTask?.cancel(); link.batteryPollTask = nil; link.batteryPollGeneration = nil
        connections[id]?.consumerStatus = "Load device features to refresh their current state."
    }
    private func awaitSetting(_ id: UUID, characteristicUUID: String, data: Data, label: String, allowWithoutResponse: Bool = false) async throws {
        guard let link = liveLink(id), link.pending == nil,
              let characteristic = link.remoteCharacteristics[characteristicUUID], characteristic.properties.contains(.read),
              characteristic.properties.contains(.write) || (allowWithoutResponse && characteristic.properties.contains(.writeWithoutResponse)) else {
            throw UTLSession.SessionError.unavailable("Control is unavailable or another request is pending.")
        }
        writeSetting(id, characteristicUUID: characteristicUUID, data: data, label: label, allowWithoutResponse: allowWithoutResponse)
        try await waitUtility(id, link: link) { link.pending == nil }
        guard connections[id]?.actionFailed == false else { throw UTLSession.SessionError.unavailable(connections[id]?.actionStatus ?? "Setting was not confirmed.") }
    }
    private func readUtility(_ id: UUID, characteristic: CBCharacteristic) async throws -> Data {
        guard let link = liveLink(id), characteristic.properties.contains(.read), link.utilityRead == nil else { throw UTLSession.SessionError.unavailable("Read is unavailable or busy.") }
        let request = UtilityRead(characteristic); link.utilityRead = request
        defer { if link.utilityRead === request { link.utilityRead = nil } }
        link.peripheral.readValue(for: characteristic)
        try await waitUtility(id, link: link) { request.result != nil }
        return try request.result!.get()
    }
    private func writeUtility(_ id: UUID, characteristic: CBCharacteristic, data: Data) async throws {
        guard let link = liveLink(id), characteristic.properties.contains(.write) else { throw UTLSession.SessionError.unavailable("Acknowledged write is unavailable.") }
        try await waitUtility(id, link: link) { link.utilityWrite == nil }
        let request = UtilityWrite(characteristic); link.utilityWrite = request
        defer { if link.utilityWrite === request { link.utilityWrite = nil } }
        link.peripheral.writeValue(data, for: characteristic, type: .withResponse)
        try await waitUtility(id, link: link) { request.result != nil }
        try request.result!.get()
    }
    private func subscribeUtility(_ id: UUID, characteristic: CBCharacteristic) async throws {
        guard let link = liveLink(id), characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) else { throw UTLSession.SessionError.unavailable("Advanced notifications are unavailable.") }
        if characteristic.isNotifying { return }
        link.peripheral.setNotifyValue(true, for: characteristic)
        try await waitUtility(id, link: link) { characteristic.isNotifying }
    }
    private func waitUtility(_ id: UUID, link: AidLink, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(11)
        while !condition() {
            try Task.checkCancellation()
            guard liveLink(id) === link else { throw UTLSession.SessionError.disconnected }
            guard Date() < deadline else { throw UTLSession.SessionError.timeout }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard liveLink(id) === link else { throw UTLSession.SessionError.disconnected }
    }
    private func maybeReadProgramNames(_ id: UUID, link: AidLink) {
        guard probeConfiguration == nil, !link.programInfoRequested, connections[id]?.advancedBusy == false, connections[id]?.groupActionPending == false,
              connections[id]?.programIDs.isEmpty == false,
              link.remoteCharacteristics[OticonProgramInfo.selector] != nil,
              link.remoteCharacteristics[OticonProgramInfo.information] != nil else { return }
        link.programInfoRequested = true
        refreshProgramInfo(id)
    }
    private func writeSetting(_ id: UUID, characteristicUUID: String, data: Data, label: String, allowWithoutResponse: Bool = false) {
        guard probeConfiguration == nil, let link = liveLink(id), link.pending == nil,
              let characteristic = link.remoteCharacteristics[characteristicUUID],
              characteristic.properties.contains(.write) || (allowWithoutResponse && characteristic.properties.contains(.writeWithoutResponse)),
              characteristic.properties.contains(.read) else { return }
        let pending = PendingSetting(characteristic: characteristic, expected: data, label: label)
        link.pending = pending
        connections[id]?.actionPending = true
        connections[id]?.actionFailed = false
        connections[id]?.actionStatus = "Sending \(label.lowercased())…"
        record("setting_requested", "\(label) requested by user", details: ["uuid": id.uuidString, "characteristic": characteristicUUID, "payload_hex": data.hexString])
        if allowWithoutResponse && characteristic.properties.contains(.writeWithoutResponse) {
            pending.stage = .readback; pending.readbackAttempts = 1
            Task {
                do {
                    try await self.waitUtility(id, link: link) { link.peripheral.canSendWriteWithoutResponse }
                    guard link.pending === pending else { return }
                    link.peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
                    try await Task.sleep(for: .milliseconds(350))
                    guard self.liveLink(id) === link, link.pending === pending else { return }
                    link.peripheral.readValue(for: characteristic)
                } catch {
                    if self.liveLink(id) === link, link.pending === pending { self.completeSetting(id, link: link, message: "\(label) was not confirmed: \(error.localizedDescription)", failed: true) }
                }
            }
        } else { link.peripheral.writeValue(data, for: characteristic, type: .withResponse) }
        pending.timeout = Task { [weak self, weak link, weak pending] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, let link, let pending, self.links[id] === link, link.pending === pending else { return }
            self.completeSetting(id, link: link, message: "No confirmed readback. Refresh before trying again.", failed: true)
        }
    }
    private func liveLink(_ id: UUID) -> AidLink? {
        guard connections[id]?.phase == .connected, let link = links[id], link.peripheral.state == .connected else { return nil }
        return link
    }
    private func completeSetting(_ id: UUID, link: AidLink, message: String, failed: Bool) {
        if failed, let characteristic = link.pending?.characteristic.uuid.uuidString.uppercased() {
            // A failed/ambiguous transaction needs another actual read or notification before the next write.
            if characteristic == OticonRemoteProtocol.mainVolume { connections[id]?.volume = nil }
            if characteristic == OticonRemoteProtocol.activeProgram { connections[id]?.activeProgram = nil }
            if characteristic == OticonEqualizer.legacyCharacteristic { connections[id]?.streamingEqualizer = nil; link.legacyEqualizerData = nil }
            if characteristic == OticonSpeechBooster.legacyCharacteristic {
                connections[id]?.speechBoosterEnabled = nil; connections[id]?.writableSpeechBooster = false; link.legacySpeechBoosterData = nil
            }
        }
        link.pending?.timeout?.cancel(); link.pending = nil
        connections[id]?.actionPending = false
        connections[id]?.actionStatus = message
        connections[id]?.actionFailed = failed
        record(failed ? "setting_unconfirmed" : "setting_confirmed", message, details: ["uuid": id.uuidString])
    }
    private func record(_ event: String, _ message: String, details: [String: String] = [:]) {
        let item = SessionEvent(event, message, details: details)
        events.append(item)
        if events.count > 200 { events.removeFirst(events.count - 200) }
        if let recorder { do { try recorder.append(item) } catch { lastError = "Probe output write failed: \(error.localizedDescription)" } }
    }
    private func recoverConnectedPeripherals() {
        let recovered = central.retrieveConnectedPeripherals(withServices: HearingAidDiscovery.connectedRetrievalServices.map { CBUUID(string: $0) })
        record("connected_peripherals_retrieved", "Checked peripherals already connected to macOS", details: ["count": String(recovered.count), "matching_services": HearingAidDiscovery.connectedRetrievalServices.joined(separator: ",")])
        for device in recovered {
            let knownServices = (device.services ?? []).map { $0.uuid.uuidString }
            upsert(device, name: device.name, rssi: nil, services: knownServices, manufacturerData: nil, source: "Connected to macOS", connectable: nil)
            record("peripheral_recovered", "Recovered an existing macOS connection", details: ["uuid": device.identifier.uuidString, "name": device.name ?? "", "cached_services": knownServices.joined(separator: ",")])
            maybeProbeConnect(device)
        }
    }
    private func upsert(_ device: CBPeripheral, name: String?, rssi: Int?, services advertisedServices: [String], manufacturerData: Data?, source: String, connectable: Bool?) {
        peripherals[device.identifier] = device
        let existing = devices.first { $0.id == device.identifier }
        let services = Array(Set((existing?.services ?? []) + advertisedServices)).sorted()
        let name = name ?? device.name ?? existing?.name ?? "Unnamed device"
        let updated = NearbyDevice(id: device.identifier, name: name, rssi: rssi ?? existing?.rssi,
                                   services: services, candidateReasons: HearingAidDiscovery.candidateReasons(name: name, services: services),
                                   companyID: manufacturerData.flatMap(HearingAidDiscovery.manufacturerCompanyID) ?? existing?.companyID,
                                   lastSeen: Date(), source: source, isConnectable: connectable ?? existing?.isConnectable,
                                   isSystemConnected: source == "Connected to macOS" || existing?.isSystemConnected == true)
        if let index = devices.firstIndex(where: { $0.id == device.identifier }) { devices[index] = updated } else { devices.append(updated) }
        devices.sort { $0.isCandidate != $1.isCandidate ? $0.isCandidate : ($0.rssi ?? -128) > ($1.rssi ?? -128) }
    }
    private func maybeProbeConnect(_ device: CBPeripheral) {
        guard !probeHasAttemptedConnect, probeConfiguration?.probeConnect == device.identifier else { return }
        probeHasAttemptedConnect = true
        connect(to: device.identifier)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isPoweredOn = central.state == .poweredOn
        switch central.state {
        case .poweredOn: bluetoothStatus = "Bluetooth ready"
        case .poweredOff: bluetoothStatus = "Bluetooth is off"
        case .unauthorized: bluetoothStatus = "Bluetooth permission required in System Settings"
        case .unsupported: bluetoothStatus = "Bluetooth LE is not supported"
        case .resetting: bluetoothStatus = "Bluetooth is resetting"
        case .unknown: bluetoothStatus = "Waiting for Bluetooth…"
        @unknown default: bluetoothStatus = "Unknown Bluetooth state"
        }
        record("bluetooth_state", bluetoothStatus, details: ["state": String(central.state.rawValue), "authorization": String(CBCentralManager.authorization.rawValue)])
        if isPoweredOn {
            if pendingScan { startScan(seconds: probeConfiguration?.probeSeconds ?? 15) } else { recoverConnectedPeripherals() }
        } else {
            isScanning = false
            for id in Array(links.keys) {
                links[id]?.connectTimeout?.cancel(); links[id]?.pending?.timeout?.cancel()
                links[id]?.utlSession?.disconnected()
                links[id]?.batteryPollTask?.cancel(); links[id]?.batteryPollTask = nil; links[id]?.batteryPollGeneration = nil
                connections[id]?.clearLiveValues(); connections[id]?.phase = .disconnected
            }
            links = [:]
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        let advertisedServices = ((advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []).map { $0.uuidString }
        let overflowServices = ((advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []).map { $0.uuidString }
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
        let validRSSI = RSSI.intValue == 127 ? nil : RSSI.intValue
        upsert(peripheral, name: name, rssi: validRSSI, services: advertisedServices + overflowServices, manufacturerData: manufacturerData, source: "Advertisement", connectable: connectable)
        if Date().timeIntervalSince(loggedDiscoveryAt[peripheral.identifier] ?? .distantPast) >= 5 {
            loggedDiscoveryAt[peripheral.identifier] = Date()
            var details = ["uuid": peripheral.identifier.uuidString, "name": name ?? "", "rssi": validRSSI.map(String.init) ?? "unavailable", "services": (advertisedServices + overflowServices).joined(separator: ",")]
            if let manufacturerData { details["manufacturer_data_hex"] = manufacturerData.hexString }
            if let connectable { details["connectable"] = String(connectable) }
            if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
                for (uuid, data) in serviceData { details["service_data_\(uuid.uuidString)"] = data.hexString }
            }
            record("advertisement", "Discovered \(name ?? "unnamed device")", details: details)
        }
        maybeProbeConnect(peripheral)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier
        guard let link = links[id], link.peripheral === peripheral, connections[id]?.phase == .connecting else { return }
        link.connectTimeout?.cancel(); link.connectTimeout = nil
        connections[id]?.phase = .connected; connections[id]?.connectedAt = Date()
        record("connected", "Connected; discovering GATT services", details: ["uuid": id.uuidString])
        peripheral.discoverServices(nil)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        let id = peripheral.identifier
        guard let link = links[id], link.peripheral === peripheral else { return }
        link.connectTimeout?.cancel(); link.pending?.timeout?.cancel()
        connections[id]?.clearLiveValues(); connections[id]?.phase = .failed
        connections[id]?.error = error?.localizedDescription ?? "Connection failed"
        links[id] = nil
        record("connection_failed", error?.localizedDescription ?? "Connection failed", details: ["uuid": id.uuidString])
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        let id = peripheral.identifier
        guard let link = links[id], link.peripheral === peripheral else { return }
        link.connectTimeout?.cancel(); link.pending?.timeout?.cancel()
        link.utlSession?.disconnected()
        link.batteryPollTask?.cancel(); link.batteryPollTask = nil; link.batteryPollGeneration = nil
        connections[id]?.clearLiveValues(); connections[id]?.phase = .disconnected; connections[id]?.actionStatus = nil
        if let error { connections[id]?.error = error.localizedDescription }
        links[id] = nil
        record("disconnected", error?.localizedDescription ?? "Disconnected", details: ["uuid": id.uuidString])
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        let id = peripheral.identifier
        guard let link = liveLink(id), link.peripheral === peripheral else { return }
        if let error { reportGATTError(error, id: id, stage: "service_discovery"); return }
        let inventory = (peripheral.services ?? []).enumerated().map { index, service in
            let serviceID = "\(service.uuid.uuidString)-\(index)"
            link.serviceIDs[ObjectIdentifier(service)] = serviceID
            return GATTServiceInfo(id: serviceID, uuid: service.uuid.uuidString, isPrimary: service.isPrimary, characteristics: [])
        }
        connections[id]?.services = inventory
        upsert(peripheral, name: peripheral.name, rssi: nil, services: inventory.map(\.uuid), manufacturerData: nil, source: "Connected to macOS", connectable: true)
        record("services_discovered", "GATT service inventory received", details: ["uuid": id.uuidString, "services": inventory.map(\.uuid).joined(separator: ",")])
        for service in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: service) }
    }
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        let id = peripheral.identifier
        guard !invalidatedServices.isEmpty, let link = liveLink(id), link.peripheral === peripheral else { return }
        link.pending?.timeout?.cancel(); link.pending = nil
        link.utlSession?.disconnected(); link.utlSession = nil
        link.batteryPollTask?.cancel(); link.batteryPollTask = nil; link.batteryPollGeneration = nil
        link.serviceIDs = [:]; link.characteristicIDs = [:]; link.remoteCharacteristics = [:]; link.utlCharacteristics = [:]
        link.programInfoRequested = false; link.legacyEqualizerData = nil
        connections[id]?.clearLiveValues()
        connections[id]?.services = []
        connections[id]?.connectedAt = Date()
        record("services_invalidated", "Bluetooth services changed; refreshing current values", details: ["uuid": id.uuidString])
        peripheral.discoverServices(nil)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        let id = peripheral.identifier
        guard let link = liveLink(id), link.peripheral === peripheral else { return }
        if let error { reportGATTError(error, id: id, stage: "characteristic_discovery"); return }
        guard let serviceID = link.serviceIDs[ObjectIdentifier(service)], let serviceIndex = connections[id]?.services.firstIndex(where: { $0.id == serviceID }) else { return }
        let inventory = (service.characteristics ?? []).enumerated().map { index, characteristic in
            let characteristicID = "\(serviceID)/\(characteristic.uuid.uuidString)-\(index)"
            link.characteristicIDs[ObjectIdentifier(characteristic)] = characteristicID
            let properties = Self.propertiesDescription(characteristic.properties)
            record("characteristic_discovered", "GATT characteristic inventoried", details: ["uuid": id.uuidString, "service": service.uuid.uuidString, "characteristic": characteristic.uuid.uuidString, "properties": properties])
            return GATTCharacteristicInfo(id: characteristicID, uuid: characteristic.uuid.uuidString, properties: properties, value: nil, isNotifying: characteristic.isNotifying)
        }
        connections[id]?.services[serviceIndex].characteristics = inventory
        for characteristic in service.characteristics ?? [] {
            if HearingAidDiscovery.normalizedUUID(service.uuid.uuidString) == OticonRemoteProtocol.service {
                link.remoteCharacteristics[characteristic.uuid.uuidString.uppercased()] = characteristic
                if characteristic.uuid.uuidString.uppercased() == OticonRemoteProtocol.mainVolume { connections[id]?.writableVolume = characteristic.properties.contains(.write) && characteristic.properties.contains(.read) }
                if characteristic.uuid.uuidString.uppercased() == OticonRemoteProtocol.activeProgram { connections[id]?.writableProgram = characteristic.properties.contains(.write) && characteristic.properties.contains(.read) }
                if characteristic.uuid.uuidString.uppercased() == OticonEqualizer.legacyCharacteristic { connections[id]?.writableStreamingEqualizer = characteristic.properties.contains(.write) && characteristic.properties.contains(.read) }
                if characteristic.uuid.uuidString.uppercased() == OticonSpeechBooster.legacyCharacteristic {
                    connections[id]?.writableSpeechBooster = characteristic.properties.contains(.read)
                        && (characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse))
                }
            }
            if HearingAidDiscovery.normalizedUUID(service.uuid.uuidString) == UTLProtocol.service {
                link.utlCharacteristics[characteristic.uuid.uuidString.uppercased()] = characteristic
            }
            readIfAllowed(characteristic, service: service, link: link)
            if ReadOnlyInspection.shouldNotify(service: service.uuid.uuidString, characteristic: characteristic.uuid.uuidString),
               characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) { peripheral.setNotifyValue(true, for: characteristic) }
        }
        maybeReadProgramNames(id, link: link)
    }
    private func readIfAllowed(_ characteristic: CBCharacteristic, service: CBService, link: AidLink) {
        guard ReadOnlyInspection.name(service: service.uuid.uuidString, characteristic: characteristic.uuid.uuidString) != nil, characteristic.properties.contains(.read) else { return }
        link.peripheral.readValue(for: characteristic)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        let id = peripheral.identifier
        guard let link = liveLink(id), link.peripheral === peripheral else { return }
        if let error {
            if let request = link.utilityRead, request.characteristic === characteristic { request.result = .failure(error) }
            reportGATTError(error, id: id, stage: "read"); return
        }
        if let request = link.utilityRead, request.characteristic === characteristic, let value = characteristic.value { request.result = .success(value) }
        if HearingAidDiscovery.normalizedUUID(characteristic.service?.uuid.uuidString ?? "") == UTLProtocol.service,
           let value = characteristic.value, let session = link.utlSession {
            let uuid = characteristic.uuid.uuidString.uppercased()
            let wasReady = session.isReady
            if uuid == UTLProtocol.control { session.receiveControl(value) }
            else if uuid == UTLProtocol.outputs[Int(session.channel)] { session.receiveOutput(value) }
            if wasReady && !session.isReady {
                invalidateEqualizer(id, microphone: true)
                invalidateEqualizer(id, microphone: false)
                invalidateConsumerFeatures(id, link: link)
                if let legacy = link.remoteCharacteristics[OticonEqualizer.legacyCharacteristic], legacy.properties.contains(.read) {
                    peripheral.readValue(for: legacy)
                }
                connections[id]?.advancedStatus = "Advanced channel closed. Load advanced controls again."
            }
            if uuid == UTLProtocol.control || uuid == UTLProtocol.outputs[Int(session.channel)] { return }
        }
        guard let service = characteristic.service, ReadOnlyInspection.name(service: service.uuid.uuidString, characteristic: characteristic.uuid.uuidString) != nil, let value = characteristic.value else { return }
        let text = ReadOnlyInspection.displayValue(service: service.uuid.uuidString, characteristic: characteristic.uuid.uuidString, data: value)
        updateCharacteristic(id, link: link, characteristic: characteristic) { $0.value = text }
        updateLiveState(id, service: service.uuid.uuidString, characteristic: characteristic.uuid.uuidString, value: value)
        maybeReadProgramNames(id, link: link)
        // The serial is displayed per aid, but not duplicated into event logs.
        if !(HearingAidDiscovery.normalizedUUID(service.uuid.uuidString) == StandardGATT.deviceInformationService && HearingAidDiscovery.normalizedUUID(characteristic.uuid.uuidString) == "2A25") {
            record("gatt_value", "Read-only GATT value received", details: ["uuid": id.uuidString, "service": service.uuid.uuidString, "characteristic": characteristic.uuid.uuidString, "value": text, "value_hex": value.hexString])
        }
        if let pending = link.pending, pending.characteristic === characteristic, pending.stage == .readback {
            let matched: Bool
            if characteristic.uuid.uuidString.uppercased() == OticonSpeechBooster.legacyCharacteristic,
               let expected = OticonSpeechBooster.legacyEnabled(pending.expected), let actual = OticonSpeechBooster.legacyEnabled(value) { matched = expected == actual }
            else { matched = value == pending.expected }
            if matched { completeSetting(id, link: link, message: "\(pending.label) confirmed by hearing aid", failed: false) }
            else if pending.readbackAttempts < 3 {
                pending.readbackAttempts += 1
                Task { [weak self, weak link, weak pending] in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled, let self, let link, let pending, self.links[id] === link, link.pending === pending, self.liveLink(id) != nil else { return }
                    link.peripheral.readValue(for: characteristic)
                }
            } else { completeSetting(id, link: link, message: "Request accepted; device reports a different value. Current status refreshed.", failed: true) }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        let id = peripheral.identifier
        if let link = liveLink(id), link.peripheral === peripheral, let request = link.utilityWrite, request.characteristic === characteristic {
            request.result = error.map { .failure($0) } ?? .success(())
            return
        }
        guard let link = liveLink(id), link.peripheral === peripheral, let pending = link.pending, pending.characteristic === characteristic else { return }
        if let error { completeSetting(id, link: link, message: "\(pending.label) failed: \(error.localizedDescription)", failed: true); return }
        pending.stage = .readback; pending.readbackAttempts = 1
        connections[id]?.actionStatus = "Request accepted; confirming current value…"
        record("setting_acknowledged", "Write acknowledged; requesting readback", details: ["uuid": id.uuidString, "characteristic": characteristic.uuid.uuidString])
        peripheral.readValue(for: characteristic)
    }
    private func updateLiveState(_ id: UUID, service: String, characteristic: String, value: Data) {
        let service = HearingAidDiscovery.normalizedUUID(service)
        let characteristic = HearingAidDiscovery.normalizedUUID(characteristic)
        connections[id]?.lastValueAt = Date()
        if service == StandardGATT.batteryService, characteristic == StandardGATT.batteryLevel { connections[id]?.battery = StandardGATT.batteryPercentage(value) }
        else if service == "1850", characteristic == "2BCA", value.count == 4 { connections[id]?.sinkAudioLocations = value.enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << (8 * $1.offset)) } }
        else if service == StandardGATT.deviceInformationService {
            switch characteristic {
            case "2A29": connections[id]?.manufacturer = StandardGATT.informationString(value)
            case "2A24": connections[id]?.model = StandardGATT.informationString(value)
            case "2A26": connections[id]?.firmware = StandardGATT.informationString(value)
            case "2A25": connections[id]?.serialNumber = StandardGATT.informationString(value)
            default: break
            }
        } else if service == OticonRemoteProtocol.service {
            if connections[id]?.actionPending == false,
               [OticonRemoteProtocol.mainVolume, OticonRemoteProtocol.activeProgram].contains(characteristic) {
                connections[id]?.actionStatus = nil
                connections[id]?.actionFailed = false
            }
            switch characteristic {
            case OticonRemoteProtocol.ear: connections[id]?.ear = value.count == 1 ? value.first.map(Int.init) : nil
            case OticonRemoteProtocol.mainVolume: connections[id]?.volume = OticonRemoteProtocol.Volume(data: value)
            case OticonRemoteProtocol.volumeRanges: connections[id]?.volumeRanges = OticonRemoteProtocol.VolumeRanges(data: value)
            case OticonRemoteProtocol.activeProgram:
                let program = value.count == 1 ? value.first.map(Int.init) : nil
                if let old = connections[id]?.activeProgram, old != program {
                    connections[id]?.microphoneEqualizer = nil
                    connections[id]?.streamingEqualizer = nil
                    connections[id]?.writableMicrophoneEqualizer = false
                    connections[id]?.volumeRanges = nil
                    connections[id]?.speechBoosterEnabled = nil
                    connections[id]?.writableSpeechBooster = false
                    if let link = liveLink(id), let ranges = link.remoteCharacteristics[OticonRemoteProtocol.volumeRanges], ranges.properties.contains(.read) { link.peripheral.readValue(for: ranges) }
                    if let link = liveLink(id), let eq = link.remoteCharacteristics[OticonEqualizer.legacyCharacteristic], eq.properties.contains(.read) { link.peripheral.readValue(for: eq) }
                }
                connections[id]?.activeProgram = program
            case OticonRemoteProtocol.availablePrograms: connections[id]?.programIDs = OticonRemoteProtocol.programIDs(bitmap: value) ?? []
            case OticonEqualizer.legacyCharacteristic:
                if let link = liveLink(id), let state = try? OticonEqualizer.legacyStreamingState(value) {
                    link.legacyEqualizerData = value
                    if link.utlSession?.isReady != true {
                        connections[id]?.streamingEqualizer = state
                        let properties = link.remoteCharacteristics[OticonEqualizer.legacyCharacteristic]?.properties
                        connections[id]?.writableStreamingEqualizer = properties?.contains(.write) == true && properties?.contains(.read) == true
                    }
                } else { invalidateEqualizer(id, microphone: false) }
            case OticonSpeechBooster.legacyCharacteristic:
                if let link = liveLink(id), link.utlSession?.isReady != true,
                   let enabled = OticonSpeechBooster.legacyEnabled(value) {
                    link.legacySpeechBoosterData = value
                    connections[id]?.speechBoosterEnabled = enabled
                    let properties = link.remoteCharacteristics[OticonSpeechBooster.legacyCharacteristic]?.properties
                    connections[id]?.writableSpeechBooster = properties?.contains(.read) == true
                        && (properties?.contains(.write) == true || properties?.contains(.writeWithoutResponse) == true)
                }
            default: break
            }
        } else if service == UTLProtocol.service, characteristic == UTLProtocol.information {
            links[id]?.utlInformation = try? UTLProtocol.GattInformation(data: value)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        let id = peripheral.identifier
        guard let link = liveLink(id), link.peripheral === peripheral else { return }
        if let error { reportGATTError(error, id: id, stage: "notification"); return }
        updateCharacteristic(id, link: link, characteristic: characteristic) { $0.isNotifying = characteristic.isNotifying }
        record("notification_state", "Read-only status notification state", details: ["uuid": id.uuidString, "characteristic": characteristic.uuid.uuidString, "notifying": String(characteristic.isNotifying)])
    }
    private func updateCharacteristic(_ id: UUID, link: AidLink, characteristic: CBCharacteristic, update: (inout GATTCharacteristicInfo) -> Void) {
        guard let service = characteristic.service, let serviceID = link.serviceIDs[ObjectIdentifier(service)], let characteristicID = link.characteristicIDs[ObjectIdentifier(characteristic)],
              let serviceIndex = connections[id]?.services.firstIndex(where: { $0.id == serviceID }),
              let characteristicIndex = connections[id]?.services[serviceIndex].characteristics.firstIndex(where: { $0.id == characteristicID }) else { return }
        if var state = connections[id] { update(&state.services[serviceIndex].characteristics[characteristicIndex]); connections[id] = state }
    }
    private func reportGATTError(_ error: any Error, id: UUID, stage: String) {
        connections[id]?.error = error.localizedDescription
        record("gatt_error", error.localizedDescription, details: ["uuid": id.uuidString, "stage": stage])
    }
    private static func propertiesDescription(_ properties: CBCharacteristicProperties) -> String {
        let choices: [(CBCharacteristicProperties, String)] = [(.read, "read"), (.write, "write"), (.writeWithoutResponse, "write without response"), (.notify, "notify"), (.indicate, "indicate"), (.broadcast, "broadcast"), (.authenticatedSignedWrites, "signed write"), (.extendedProperties, "extended")]
        return choices.filter { properties.contains($0.0) }.map(\.1).joined(separator: ", ")
    }
}
