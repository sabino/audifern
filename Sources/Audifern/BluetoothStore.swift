import AppKit
import Combine
import CompanionCore
@preconcurrency import CoreBluetooth
import Foundation
import QuickAccessKit

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
    var automaticConsumerReadRequested = false
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

private struct AuxiliaryVolumeSnapshot: Equatable {
    let program: Int
    let control: AuxiliaryHearingControls.Aid
}

/// Independent, main-queue connections. Probe mode cannot issue hearing-setting writes.
@MainActor
final class BluetoothStore: NSObject, ObservableObject, AutomaticConnectionTransport, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    let isDemo: Bool
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
    @Published private(set) var programSnapshot: ConsumerProgramSnapshot?
    @Published private(set) var programSnapshotStatus: String?
    @Published private(set) var programSnapshotBusy = false
    @Published private(set) var deviceBackupBusy = false
    @Published private(set) var deviceBackupStatus: String?
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var links: [UUID: AidLink] = [:]
    private var loggedDiscoveryAt: [UUID: Date] = [:]
    private var scanTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var pendingScan = false
    private var automaticScan = false
    private var measuredSignals: [UUID: ConnectionSignal] = [:]
    private let batteryCache: BatteryRuntimeCache?
    var onManualConnect: (() -> Void)?
    var onManualDisconnect: (() -> Void)?
    private var probeConfiguration: LaunchConfiguration?
    private var recorder: ProbeRecorder?
    private var probeHasAttemptedConnect = false
    lazy var equalizerLoader = EqualizerLoader { [weak self] context in
        guard let self else { throw UTLSession.SessionError.disconnected }
        try await self.readEqualizers(context)
    }

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

    override convenience init() { self.init(demo: false) }
    init(demo: Bool, batteryCache: BatteryRuntimeCache? = nil) {
        isDemo = demo
        self.batteryCache = batteryCache
        super.init()
        if demo {
            connections = DemoData.connections
            devices = DemoData.devices
            selectedPeripheralID = DemoData.leftID
            bluetoothStatus = "Preview mode"
            events = [.init("preview_started", "Preview mode uses synthetic devices. Bluetooth is disabled.")]
            return
        }
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
    func startScan(seconds: Double = 15, automatic: Bool = false) {
        guard isPoweredOn else { pendingScan = true; record("scan_waiting", "Waiting for Bluetooth permission and power"); return }
        pendingScan = false
        automaticScan = automatic
        scanTask?.cancel()
        recoverConnectedPeripherals()
        central.scanForPeripherals(withServices: automatic ? HearingAidDiscovery.connectedRetrievalServices.map { CBUUID(string: $0) } : nil,
                                  options: [CBCentralManagerScanOptionAllowDuplicatesKey: !automatic])
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
        automaticScan = false
        guard isScanning else { return }
        central.stopScan(); isScanning = false
        record("scan_stopped", "Scan stopped")
    }
    func connectPair() {
        guard probeConfiguration == nil else { return }
        for id in pairCandidateIDs { connect(to: id) }
    }
    func connect(to id: UUID, manual: Bool = true) {
        guard isPoweredOn, let target = peripherals[id], links[id] == nil else { return }
        let link = AidLink(target)
        links[id] = link
        connections[id] = AidConnection(id: id, name: target.name ?? devices.first(where: { $0.id == id })?.name ?? "Hearing aid", phase: .connecting)
        connections[id]?.cachedBatteryReading = batteryCache?.reading(for: id)
        if manual { onManualConnect?() }
        selectedPeripheralID = id
        target.delegate = self
        record("connection_requested", "Connecting to \(target.name ?? "device")", details: ["uuid": id.uuidString])
        central.connect(target, options: nil)
        link.connectTimeout = Task { [weak self, weak link] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, let link, self.links[id] === link, self.connections[id]?.phase == .connecting else { return }
            self.connections[id]?.error = "Connection timed out. The device may be busy with another host."
            self.record("connection_timeout", "Connection did not complete within 20 seconds", details: ["uuid": id.uuidString])
            self.disconnect(id, manual: false)
        }
    }
    func disconnect(_ id: UUID, manual: Bool = true) {
        guard let link = links[id] else { return }
        if manual { onManualDisconnect?() }
        link.connectTimeout?.cancel(); link.pending?.timeout?.cancel()
        connections[id]?.clearLiveValues()
        connections[id]?.phase = .disconnecting
        connections[id]?.actionStatus = nil
        central.cancelPeripheralConnection(link.peripheral)
        record("disconnect_requested", "Disconnect requested", details: ["uuid": id.uuidString])
    }
    func disconnect() { for id in Array(links.keys) { disconnect(id) } }
    func clearEvents() { events = [] }

    var automationPoweredOn: Bool { !isDemo && probeConfiguration == nil && isPoweredOn }
    var automationPhases: [UUID: ConnectionPhase] { connections.mapValues(\.phase) }
    var automationSignals: [UUID: ConnectionSignal] { measuredSignals }
    var automationCurrentAids: [RememberedHearingAid] {
        orderedConnections.filter { $0.canChangeVolume && ["Left", "Right"].contains($0.sideLabel) }
            .map { RememberedHearingAid(id: $0.id, side: $0.sideLabel) }
    }
    func retrieveRemembered(_ ids: [UUID]) {
        guard automationPoweredOn else { return }
        for peripheral in central.retrievePeripherals(withIdentifiers: ids) { peripherals[peripheral.identifier] = peripheral }
    }
    func scanForRemembered() {
        guard automationPoweredOn, !isScanning else { return }
        startScan(seconds: 4, automatic: true)
    }
    func stopAutomaticScan() { if automaticScan { stopScan() } }
    func connectRemembered(_ id: UUID) -> Bool {
        guard automationPoweredOn, peripherals[id] != nil, links[id] == nil else { return false }
        connect(to: id, manual: false); return true
    }
    func disconnectAutomaticConnections() { for id in Array(links.keys) { disconnect(id, manual: false) } }
    func measureConnectedSignal() {
        guard automationPoweredOn else { return }
        for link in links.values where link.peripheral.state == .connected { link.peripheral.readRSSI() }
    }
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: (any Error)?) {
        guard error == nil, (-127 ... -1).contains(RSSI.intValue), liveLink(peripheral.identifier)?.peripheral === peripheral else { return }
        measuredSignals[peripheral.identifier] = .init(rssi: RSSI.intValue, measuredAt: Date())
    }

    /// Fresh consumer controls only. The metadata cursor is released after a
    /// legacy query; this never selects a listening program or writes a setting.
    func readProgramSnapshot() {
        guard !isDemo, probeConfiguration == nil, !programSnapshotBusy else { return }
        programSnapshot = nil
        let connected = orderedConnections.filter(\.isConnected)
        let targets = connected.compactMap { aid -> (UUID, AidLink, ConsumerProgramSnapshot.Side)? in
            guard let side = ConsumerProgramSnapshot.Side(rawValue: aid.sideLabel.lowercased()),
                  let link = liveLink(aid.id) else { return nil }
            return (aid.id, link, side)
        }
        guard !linkedActionPending, (1...2).contains(targets.count), targets.count == connected.count,
              Set(targets.map { $0.2 }).count == targets.count,
              targets.allSatisfy({ id, link, _ in
                  connections[id]?.actionPending == false && connections[id]?.advancedBusy == false
                      && connections[id]?.groupActionPending == false && link.pending == nil
                      && link.utilityRead == nil && link.utilityWrite == nil
              }) else {
            programSnapshotStatus = "Connect one aid per known left/right side and wait for current requests to finish."
            return
        }
        programSnapshotBusy = true
        programSnapshotStatus = "Reading current programs and consumer controls…"
        for (id, _, _) in targets {
            connections[id]?.groupActionPending = true
            connections[id]?.advancedBusy = true
        }
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.programSnapshotBusy = false
                for (id, link, _) in targets where self.liveLink(id) === link {
                    self.connections[id]?.groupActionPending = false
                    self.connections[id]?.advancedBusy = false
                }
            }
            var captured: [ConsumerProgramSnapshot.Aid] = []
            var expectedPrograms: [UUID: Int] = [:]
            var notes: [String] = []
            do {
                for (id, link, side) in targets {
                    try self.checkSnapshotLink(id, link: link, side: side)
                    let programBefore = try await self.readSnapshotProgram(id, link: link)
                    expectedPrograms[id] = programBefore
                    let rangeData = try await self.readSnapshotValue(id, link: link, uuid: OticonRemoteProtocol.volumeRanges)
                    let volumeData = try await self.readSnapshotValue(id, link: link, uuid: OticonRemoteProtocol.mainVolume)
                    guard let ranges = OticonRemoteProtocol.VolumeRanges(data: rangeData),
                          let main = OticonRemoteProtocol.Volume(data: volumeData) else {
                        throw UTLSession.SessionError.unavailable("The aid did not return valid current volume and ranges.")
                    }
                    let mainVolume = try ConsumerProgramSnapshot.Volume(level: main.level, muted: main.muted, range: ranges.main)
                    let label = side.rawValue.capitalized
                    var session: UTLSession?
                    await self.cleanFailedSnapshotSession(id, link: link)
                    if let existing = link.utlSession, existing.isReady { session = existing }
                    else if FileManager.default.fileExists(atPath: UTLSession.defaultKeyURL.path),
                            link.utlCharacteristics[UTLProtocol.information] != nil,
                            link.utlCharacteristics[UTLProtocol.control] != nil {
                        do { session = try await self.readyAdvancedSession(id, link: link) }
                        catch { notes.append("\(label): advanced controls unavailable."); await self.cleanFailedSnapshotSession(id, link: link) }
                    }
                    try self.checkSnapshotLink(id, link: link, side: side)
                    var program: ConsumerProgramSnapshot.Program?
                    if let session, session.isReady, session.supportsProgramInformation {
                        do {
                            program = try await session.programInformation().first { $0.programID == programBefore }
                            if program == nil { notes.append("\(label): UTL metadata omitted the active program; used the legacy metadata query.") }
                        } catch {
                            notes.append("\(label): UTL metadata unavailable; used the legacy metadata query.")
                            await self.cleanFailedSnapshotSession(id, link: link)
                        }
                    }
                    if program == nil { program = try await self.readSnapshotLegacyProgram(id, link: link, program: programBefore) }
                    guard let program else { throw UTLSession.SessionError.unavailable("Current program metadata is unavailable.") }
                    var streamingVolume: ConsumerProgramSnapshot.Volume?, tinnitusVolume: ConsumerProgramSnapshot.Volume?
                    for source in [AuxiliaryHearingControls.Source.streaming, .tinnitus] {
                        let eligible = source == .tinnitus ? program.tinnitus
                            : UInt8(exactly: program.category).map { AuxiliaryHearingControls.supportsStreaming(category: $0, tinnitus: program.tinnitus) } == true
                        guard eligible, link.remoteCharacteristics[source.characteristic]?.properties.contains(.read) == true else { continue }
                        do {
                            let data = try await self.readSnapshotValue(id, link: link, uuid: source.characteristic)
                            guard let value = OticonRemoteProtocol.Volume(data: data) else { throw ConsumerProgramSnapshot.SnapshotError.invalid }
                            let volume = try ConsumerProgramSnapshot.Volume(level: value.level, muted: value.muted,
                                range: source == .tinnitus ? ranges.tinnitus : ranges.streaming)
                            if source == .tinnitus { tinnitusVolume = volume } else { streamingVolume = volume }
                        } catch { notes.append("\(label): \(source.rawValue.lowercased()) volume unavailable.") }
                    }
                    var microphoneEQ: ConsumerProgramSnapshot.Equalizer?, streamingEQ: ConsumerProgramSnapshot.Equalizer?
                    if let session, session.isReady,
                       let eqService = session.services.first(where: { UTLAdvanced.supportsEqualizer($0, microphone: false) }) {
                        var step: Double?
                        do {
                            if eqService.major >= 2 { step = try await session.equalizerStep() }
                            else {
                                // Historical consumer scale remains authoritative
                                // for 1.x. Read optional get_info labels without
                                // substituting its reported scale.
                                _ = try? await session.equalizerStep()
                                step = OticonEqualizer.defaultStepDB
                            }
                        }
                        catch { notes.append("\(label): EQ step size unavailable."); await self.cleanFailedSnapshotSession(id, link: link) }
                        if let step {
                            for microphone in [true, false] where UTLAdvanced.supportsEqualizer(eqService, microphone: microphone) && session.isReady {
                                do {
                                    let value = try await session.equalizer(microphone: microphone, stepDB: step)
                                    if microphone { microphoneEQ = .init(state: value) } else { streamingEQ = .init(state: value) }
                                } catch {
                                    notes.append("\(label): \(microphone ? "microphone" : "streaming") EQ unavailable.")
                                    await self.cleanFailedSnapshotSession(id, link: link)
                                }
                            }
                        }
                    } else { notes.append("\(label): EQ omitted; no supported ready advanced channel.") }
                    var speechBooster: Bool?
                    if program.boostable {
                        if let session, session.isReady, session.supportsSpeechBooster {
                            do { speechBooster = try await session.speechBooster().isEnabled }
                            catch { notes.append("\(label): SpeechBooster unavailable."); await self.cleanFailedSnapshotSession(id, link: link) }
                        } else if link.remoteCharacteristics[OticonSpeechBooster.legacyCharacteristic]?.properties.contains(.read) == true {
                            do {
                                let data = try await self.readSnapshotValue(id, link: link, uuid: OticonSpeechBooster.legacyCharacteristic)
                                speechBooster = OticonSpeechBooster.legacyEnabled(data)
                                if speechBooster == nil { notes.append("\(label): SpeechBooster unavailable.") }
                            } catch { notes.append("\(label): SpeechBooster unavailable.") }
                        }
                    }
                    try self.checkSnapshotLink(id, link: link, side: side)
                    guard try await self.readSnapshotProgram(id, link: link) == programBefore else {
                        throw UTLSession.SessionError.unavailable("A listening program changed while reading. Try again after it settles.")
                    }
                    captured.append(try .init(side: side, model: self.connections[id]?.model, program: program,
                        volume: mainVolume, streamingVolume: streamingVolume, tinnitusVolume: tinnitusVolume,
                        microphoneEqualizer: microphoneEQ, streamingEqualizer: streamingEQ, speechBoosterEnabled: speechBooster))
                }
                // Reading the second ear must not hide a later change on the first.
                guard Set(self.orderedConnections.filter(\.isConnected).map(\.id)) == Set(targets.map { $0.0 }) else {
                    throw UTLSession.SessionError.unavailable("The connected hearing aids changed during the read.")
                }
                for (id, link, side) in targets {
                    try self.checkSnapshotLink(id, link: link, side: side)
                    guard try await self.readSnapshotProgram(id, link: link) == expectedPrograms[id] else {
                        throw UTLSession.SessionError.unavailable("A listening program changed during the read. Read again before exporting.")
                    }
                }
                guard Set(self.orderedConnections.filter(\.isConnected).map(\.id)) == Set(targets.map { $0.0 }) else {
                    throw UTLSession.SessionError.unavailable("The connected hearing aids changed during the read.")
                }
                for (id, link, side) in targets {
                    try self.checkSnapshotLink(id, link: link, side: side)
                    guard self.connections[id]?.activeProgram == expectedPrograms[id] else {
                        throw UTLSession.SessionError.unavailable("A listening program changed before the snapshot finished.")
                    }
                }
                self.programSnapshot = try .init(aids: captured)
                let note = notes.isEmpty ? "" : " " + Array(Set(notes)).sorted().joined(separator: " ")
                self.programSnapshotStatus = "Fresh consumer controls read. Clinical fitting data is not included.\(note)"
                self.record("program_snapshot_read", "Fresh consumer program snapshot read", details: ["aid_count": String(captured.count)])
            } catch {
                for (id, link, _) in targets { await self.cleanFailedSnapshotSession(id, link: link) }
                self.programSnapshot = nil
                self.programSnapshotStatus = "Snapshot unavailable: \(UTLSession.describe(error))"
            }
        }
    }

    private func checkSnapshotLink(_ id: UUID, link: AidLink, side: ConsumerProgramSnapshot.Side) throws {
        guard !isDemo, liveLink(id) === link, connections[id]?.sideLabel.lowercased() == side.rawValue else {
            throw UTLSession.SessionError.disconnected
        }
    }
    private func readSnapshotValue(_ id: UUID, link: AidLink, uuid: String) async throws -> Data {
        guard liveLink(id) === link, let characteristic = link.remoteCharacteristics[uuid], characteristic.properties.contains(.read) else {
            throw UTLSession.SessionError.unavailable("A required current consumer value is unavailable.")
        }
        let data = try await readUtility(id, characteristic: characteristic)
        guard liveLink(id) === link else { throw UTLSession.SessionError.disconnected }
        return data
    }
    private func readSnapshotProgram(_ id: UUID, link: AidLink) async throws -> Int {
        let data = try await readSnapshotValue(id, link: link, uuid: OticonRemoteProtocol.activeProgram)
        guard data.count == 1, let id = data.first else { throw ConsumerProgramSnapshot.SnapshotError.invalid }
        return Int(id)
    }
    private func readSnapshotLegacyProgram(_ id: UUID, link: AidLink, program: Int) async throws -> ConsumerProgramSnapshot.Program {
        guard liveLink(id) === link, let byte = UInt8(exactly: program), byte != 255,
              let selector = link.remoteCharacteristics[OticonProgramInfo.selector], selector.properties.contains(.write),
              link.remoteCharacteristics[OticonProgramInfo.information]?.properties.contains(.read) == true else {
            throw UTLSession.SessionError.unavailable("This aid does not expose current program metadata.")
        }
        var result: ConsumerProgramSnapshot.Program?, queryError: (any Error)?
        do {
            // Marked by entering this block before awaiting the write ACK: even
            // a lost ACK can mean that the device moved its metadata cursor.
            try await writeUtility(id, characteristic: selector, data: Data([byte]))
            let data = try await readSnapshotValue(id, link: link, uuid: OticonProgramInfo.information)
            let value = try OticonProgramInfo.Program(data: data, id: program)
            result = try .init(programID: program, name: value.label, category: UInt32(value.category),
                               boostable: value.boostable, tinnitus: value.tinnitus)
        } catch { queryError = error }
        if liveLink(id) === link {
            do { try await writeUtility(id, characteristic: selector, data: Data([255])) }
            catch { if queryError == nil { queryError = error } }
        } else { throw UTLSession.SessionError.disconnected }
        if let queryError { throw queryError }
        guard let result else { throw ConsumerProgramSnapshot.SnapshotError.invalid }
        return result
    }
    private func cleanFailedSnapshotSession(_ id: UUID, link: AidLink) async {
        guard liveLink(id) === link, let session = link.utlSession, !session.isReady else { return }
        await session.stop()
        guard liveLink(id) === link, link.utlSession === session else { return }
        link.utlSession = nil
        invalidateEqualizer(id, microphone: true); invalidateEqualizer(id, microphone: false)
        invalidateConsumerFeatures(id, link: link)
    }

    /// Save a verified consumer checkpoint before attempting the separately
    /// scoped fitting-record read. The required checkpoint closure must persist
    /// successfully; a UI-only snapshot is never used as a backup prerequisite.
    func captureDeviceBackup(deadline: Date = Date().addingTimeInterval(90),
                             checkpoint: @MainActor (DeviceBackup) throws -> Void) async throws -> DeviceBackup {
        guard !isDemo, probeConfiguration == nil, !deviceBackupBusy, !programSnapshotBusy else {
            throw UTLSession.SessionError.unavailable("A read-only backup cannot start in the current mode.")
        }
        deviceBackupBusy = true
        deviceBackupStatus = "Reading a fresh consumer-state checkpoint…"
        var completed = false
        var checkpointSaved = false
        defer {
            deviceBackupBusy = false
            if !completed {
                deviceBackupStatus = checkpointSaved
                    ? "Backup stopped. The verified checkpoint has been preserved."
                    : "Backup stopped before a verified checkpoint could be saved."
            }
        }
        readProgramSnapshot()
        guard programSnapshotBusy else { throw UTLSession.SessionError.unavailable(programSnapshotStatus ?? "Current controls are not ready.") }
        while programSnapshotBusy {
            try Task.checkCancellation()
            guard Date() < deadline else { throw UTLSession.SessionError.timeout }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let consumer = programSnapshot else {
            throw UTLSession.SessionError.unavailable(programSnapshotStatus ?? "The consumer checkpoint could not be read.")
        }
        let targets = consumer.aids.compactMap { aid -> (UUID, AidLink, ConsumerProgramSnapshot.Side)? in
            guard let connection = orderedConnections.first(where: { $0.isConnected && $0.sideLabel.lowercased() == aid.side.rawValue }),
                  let link = liveLink(connection.id) else { return nil }
            return (connection.id, link, aid.side)
        }
        guard targets.count == consumer.aids.count else { throw UTLSession.SessionError.disconnected }
        for (id, _, _) in targets { connections[id]?.advancedBusy = true; connections[id]?.groupActionPending = true }
        defer {
            for (id, link, _) in targets where liveLink(id) === link {
                connections[id]?.advancedBusy = false; connections[id]?.groupActionPending = false
            }
        }
        var programs: [UUID: [ConsumerProgramSnapshot.Program]] = [:]
        var capturedServices: [UUID: [DeviceBackup.Service]] = [:]
        var capturedIdentification: [UUID: Data] = [:]
        var notes: [UUID: [String]] = [:]
        var records: [UUID: [DeviceBackup.Record]] = [:]
        var endUserSettings: [UUID: DeviceBackup.EndUserSettings] = [:]
        for (id, link, side) in targets {
            try checkSnapshotLink(id, link: link, side: side)
            do {
                let session = try await readyAdvancedSession(id, link: link)
                capturedServices[id] = session.services.map(DeviceBackup.Service.init)
                await readDeviceMetadata(id, link: link, session: session) { payload in
                    capturedIdentification[id] = payload
                }
                if session.isReady && session.supportsProgramInformation { programs[id] = try await session.programInformation() }
            } catch {
                notes[id, default: []].append("Some extended device or program metadata was unavailable.")
                await cleanFailedSnapshotSession(id, link: link)
            }
        }
        // Freeze identity before fitting reads. A later disconnect must not
        // prevent archiving bytes already received from this owned connection.
        let identities = try Dictionary(uniqueKeysWithValues: targets.map { id, link, side in
            try checkSnapshotLink(id, link: link, side: side)
            guard let aid = connections[id] else { throw UTLSession.SessionError.disconnected }
            let metadata = aid.deviceMetadata
            return (id, DeviceBackup.Identity(peripheralID: id, serialNumber: aid.serialNumber,
                    model: metadata?.model ?? aid.model, firmware: aid.firmware ?? metadata?.firmwareRevision,
                    software: aid.softwareRevision, hiidVersion: metadata?.hiidVersion,
                    releasePackageVersion: metadata?.releasePackageVersion,
                    runtimeMemoryMapVersion: metadata?.runtimeMemoryMapVersion))
        })
        func makeBackup(stage: DeviceBackup.AcquisitionStage) throws -> DeviceBackup {
            let aids = try targets.map { id, _, side -> DeviceBackup.Aid in
                guard let identity = identities[id] else { throw UTLSession.SessionError.disconnected }
                return .init(side: side, identity: identity,
                    services: capturedServices[id] ?? [],
                    programs: programs[id] ?? consumer.aids.filter { $0.side == side }.map(\.program),
                    programInventoryComplete: programs[id] != nil,
                    records: records[id] ?? [], endUserSettings: endUserSettings[id],
                    identification: capturedIdentification[id], notes: notes[id] ?? [])
            }
            return try DeviceBackup(consumerControls: consumer, aids: aids, acquisitionStage: stage)
        }
        let baseline = try makeBackup(stage: .consumerCheckpoint)
        try checkpoint(baseline)
        checkpointSaved = true
        deviceBackupStatus = "Checkpoint saved. Reading the supported fitting record…"
        do {
            for (id, link, side) in targets {
                try Task.checkCancellation()
                guard Date() < deadline else { throw UTLSession.SessionError.timeout }
                try checkSnapshotLink(id, link: link, side: side)
                guard let identity = identities[id], SavedFitting.supports(identity),
                      let hiidVersion = identity.hiidVersion else {
                    notes[id, default: []].append("Fitting record not requested: this identification and memory-map combination has not been verified.")
                    continue
                }
                var readSession: UTLSession?
                do {
                    let session = try await readyAdvancedSession(id, link: link, purpose: .readOnlyBackup)
                    readSession = session
                    capturedServices[id] = session.services.map(DeviceBackup.Service.init)
                    let bytes = try await session.readFittingSystemRecord(hiidVersion: hiidVersion, deadline: deadline)
                    records[id] = [try .init(key: 1009, bytes: bytes)]
                    notes[id, default: []].append("HIID1009 fitting-system record read and checksum verified. Clinical restore is not supported.")
                } catch {
                    notes[id, default: []].append("Fitting record unavailable: \(UTLSession.describe(error))")
                }
                // The closure creates a NEW verified archive each time. A save
                // failure stops acquisition; it cannot be mistaken for a
                // benign unavailable getter and then discarded.
                if records[id] != nil {
                    try checkpoint(makeBackup(stage: .partialRead))
                }
                if records[id] != nil, let session = readSession {
                    do {
                        let result = try await session.readEndUserSettings(deadline: deadline)
                        endUserSettings[id] = result.data
                        notes[id, default: []].append(result.partial
                            ? "End-user settings were partially captured. Unread scopes remain outside this backup."
                            : "All advertised persisted end-user-setting scopes were captured. Live RAM, calibration and firmware are not included.")
                    } catch {
                        notes[id, default: []].append("End-user settings could not be read through the current read-only session.")
                    }
                    try checkpoint(makeBackup(stage: .partialRead))
                }
                guard Date() < deadline else { throw UTLSession.SessionError.timeout }
                await closeBackupReadSession(id, link: link)
                // Verify the ordinary consumer state after releasing the owned
                // backup channel. Do not infer unchanged sound from an ATT ACK
                // or from the checkpoint's copied values.
                try checkSnapshotLink(id, link: link, side: side)
                let programAfter = try await readSnapshotProgram(id, link: link)
                let volumeAfter = try await readSnapshotValue(id, link: link, uuid: OticonRemoteProtocol.mainVolume)
                guard let actual = OticonRemoteProtocol.Volume(data: volumeAfter),
                      let before = consumer.aids.first(where: { $0.side == side }),
                      programAfter == before.program.programID,
                      actual.level == before.volume?.level, actual.muted == before.volume?.muted else {
                    throw UTLSession.SessionError.unavailable("The active program or volume changed during backup. The original checkpoint has been preserved.")
                }
                guard Date() < deadline else { throw UTLSession.SessionError.timeout }
            }
            let result = try makeBackup(stage: .readCompleted)
            deviceBackupStatus = "Readable state captured. Clinical restore is not supported."
            completed = true
            record("device_backup_read", "Read-only device backup captured", details: ["aid_count": String(result.aids.count),
                "fitting_record_count": String(result.aids.reduce(0) { $0 + $1.records.count })])
            return result
        } catch {
            for (id, link, _) in targets { await closeBackupReadSession(id, link: link) }
            deviceBackupStatus = "Backup stopped. The verified checkpoint has been preserved."
            throw error
        }
    }

    private func closeBackupReadSession(_ id: UUID, link: AidLink) async {
        guard liveLink(id) === link, let session = link.utlSession, session.purpose == .readOnlyBackup else { return }
        await session.stop()
        guard liveLink(id) === link, link.utlSession === session else { return }
        link.utlSession = nil
        invalidateEqualizer(id, microphone: true); invalidateEqualizer(id, microphone: false)
        invalidateConsumerFeatures(id, link: link)
    }

    func finishBackupConnections() async {
        for (id, link) in links {
            if let session = link.utlSession { await session.stop(); link.utlSession = nil }
            disconnect(id)
        }
        // Let CoreBluetooth deliver owned cancellation callbacks before a
        // headless acquisition process exits. Existing system links stay owned
        // by the other apps that opened them.
        try? await Task.sleep(for: .milliseconds(350))
    }

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
    /// The slider submits once, on release. Its original snapshot must still
    /// match, and the existing consumer executor re-reads both aids before
    /// writing and confirms every write. No intermediate drag values are sent.
    func setMainVolume(_ selection: MainVolumeSelection, level: Int) {
        guard selection.matches(connections), let levels = selection.levels(setting: level) else {
            linkedActionFailed = true; linkedActionStatus = "Sound controls changed. Refresh before retrying."
            return
        }
        performConsumerChange(selection.aids.map(\.id), change: .volumeLevels(levels))
    }
    func setMuted(_ id: UUID, muted: Bool) {
        guard let state = connections[id], state.canChangeVolume, let volume = state.volume, let ranges = state.volumeRanges,
              let payload = OticonRemoteProtocol.volumePayload(level: volume.level, muted: muted, reportedRange: ranges.main) else { return }
        writeSetting(id, characteristicUUID: OticonRemoteProtocol.mainVolume, data: payload, label: muted ? "Mute" : "Unmute")
    }
    func adjustTinnitusVolume(_ id: UUID, by delta: Int) { adjustTinnitusVolume(ids: [id], by: delta) }
    func adjustTinnitusVolume(ids: [UUID], by delta: Int) { performAuxiliaryChange(ids: ids, source: .tinnitus, change: .adjust(delta)) }
    func setTinnitusMuted(_ id: UUID, muted: Bool) { setTinnitusMuted(ids: [id], muted: muted) }
    func setTinnitusMuted(ids: [UUID], muted: Bool) { performAuxiliaryChange(ids: ids, source: .tinnitus, change: .muted(muted)) }
    func adjustStreamingVolume(_ id: UUID, by delta: Int) { adjustStreamingVolume(ids: [id], by: delta) }
    func adjustStreamingVolume(ids: [UUID], by delta: Int) { performAuxiliaryChange(ids: ids, source: .streaming, change: .adjust(delta)) }
    func setStreamingMuted(_ id: UUID, muted: Bool) { setStreamingMuted(ids: [id], muted: muted) }
    func setStreamingMuted(ids: [UUID], muted: Bool) { performAuxiliaryChange(ids: ids, source: .streaming, change: .muted(muted)) }

    private func auxiliaryStatus(_ id: UUID, source: AuxiliaryHearingControls.Source, message: String, failed: Bool = false) {
        if source == .tinnitus {
            connections[id]?.tinnitusStatus = message; connections[id]?.tinnitusStatusFailed = failed
        } else {
            connections[id]?.streamingVolumeStatus = message; connections[id]?.streamingVolumeStatusFailed = failed
        }
    }

    private func freshAuxiliarySnapshot(_ id: UUID, link: AidLink,
                                        source: AuxiliaryHearingControls.Source) async throws -> AuxiliaryVolumeSnapshot {
        var values: [String: Data] = [:]
        for uuid in [OticonRemoteProtocol.activeProgram, OticonRemoteProtocol.volumeRanges, source.characteristic] {
            guard liveLink(id) === link, let characteristic = link.remoteCharacteristics[uuid],
                  characteristic.properties.contains(.read) else { throw UTLSession.SessionError.unavailable("Current source information is unavailable.") }
            values[uuid] = try await readUtility(id, characteristic: characteristic)
        }
        guard liveLink(id) === link, let state = connections[id],
              let programData = values[OticonRemoteProtocol.activeProgram], programData.count == 1,
              let program = programData.first.map(Int.init), state.activeProgram == program,
              let rangeData = values[OticonRemoteProtocol.volumeRanges], let ranges = OticonRemoteProtocol.VolumeRanges(data: rangeData),
              let value = values[source.characteristic], let volume = OticonRemoteProtocol.Volume(data: value),
              let characteristic = link.remoteCharacteristics[source.characteristic], characteristic.properties.contains(.write),
              state.auxiliaryProgramEligible(source) == true else {
            throw UTLSession.SessionError.unavailable("The current program does not expose this source with valid volume information.")
        }
        return AuxiliaryVolumeSnapshot(program: program, control: .init(current: volume,
            range: source == .tinnitus ? ranges.tinnitus : ranges.streaming, programEligible: true))
    }

    private func performAuxiliaryChange(ids: [UUID], source: AuxiliaryHearingControls.Source,
                                        change: AuxiliaryHearingControls.Change) {
        guard probeConfiguration == nil, (1...2).contains(ids.count), Set(ids).count == ids.count,
              ids.allSatisfy({ connections[$0]?.canChangeAuxiliaryVolume(source) == true }) else { return }
        if case .adjust(let delta) = change, delta != -1 && delta != 1 { return }
        let targets = ids.compactMap { id -> (UUID, AidLink)? in liveLink(id).map { (id, $0) } }
        guard targets.count == ids.count else { return }
        for (id, _) in targets {
            connections[id]?.groupActionPending = true
            auxiliaryStatus(id, source: source, message: "Reading current \(source.rawValue.lowercased()) controls…")
        }
        Task {
            defer {
                for (id, link) in targets where self.liveLink(id) === link { self.connections[id]?.groupActionPending = false }
            }
            var completed = 0
            do {
                var snapshots: [AuxiliaryVolumeSnapshot] = []
                for (id, link) in targets { snapshots.append(try await self.freshAuxiliarySnapshot(id, link: link, source: source)) }
                guard let payloads = AuxiliaryHearingControls.payloads(for: snapshots.map(\.control), change: change) else {
                    throw UTLSession.SessionError.unavailable("The requested source change is outside an aid's reported range.")
                }
                for (index, target) in targets.enumerated() {
                    let (id, link) = target
                    // Recheck after the other ear's reads/write acknowledgement.
                    // A changed untouched field is not silently overwritten.
                    let current = try await self.freshAuxiliarySnapshot(id, link: link, source: source)
                    guard current == snapshots[index] else {
                        throw UTLSession.SessionError.unavailable("An aid's program, source level, mute or range changed; refresh before retrying.")
                    }
                    try await self.awaitSetting(id, characteristicUUID: source.characteristic, data: payloads[index], label: source.rawValue)
                    completed += 1
                }
                for (id, _) in targets {
                    self.auxiliaryStatus(id, source: source,
                        message: targets.count == 2 ? "Both aids confirmed the \(source.rawValue.lowercased()) change." : "\(source.rawValue) change confirmed by hearing aid.")
                }
            } catch {
                let message = completed == 0 ? "\(source.rawValue) change not confirmed: \(error.localizedDescription)"
                    : "\(source.rawValue) change stopped after \(completed) confirmed aid. \(error.localizedDescription)"
                for (index, target) in targets.enumerated() {
                    let (id, link) = target
                    guard self.liveLink(id) === link else { continue }
                    if index >= completed {
                        if source == .tinnitus { self.connections[id]?.tinnitusVolume = nil }
                        else { self.connections[id]?.streamingVolume = nil }
                    }
                    self.auxiliaryStatus(id, source: source, message: message, failed: true)
                }
            }
        }
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
        connections[id]?.programTinnitus = [:]
        connections[id]?.programStreaming = [:]
        Task { [weak self, weak link] in
            guard let self, let link else { return }
            var result: [Int: String] = [:]
            var boostable: [Int: Bool] = [:]
            var tinnitus: [Int: Bool] = [:]
            var streaming: [Int: Bool] = [:]
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
                    tinnitus[program] = decoded.tinnitus
                    streaming[program] = AuxiliaryHearingControls.supportsStreaming(category: decoded.category, tinnitus: decoded.tinnitus)
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
            self.connections[id]?.programTinnitus = tinnitus
            self.connections[id]?.programStreaming = streaming
            self.connections[id]?.advancedBusy = false
            self.connections[id]?.advancedStatus = queryError.map { "Program names: \($0.localizedDescription)" } ?? "Program names read from hearing aid."
            self.record("program_metadata", queryError == nil ? "Program names read from hearing aid" : "Program metadata query incomplete", details: ["uuid": id.uuidString, "count": String(result.count)])
        }
    }

    private func readyAdvancedSession(_ id: UUID, link: AidLink, keyURL: URL? = nil,
                                      purpose: UTLSession.Purpose = .consumer) async throws -> UTLSession {
        guard liveLink(id) === link else { throw UTLSession.SessionError.disconnected }
        if let existing = link.utlSession, existing.isReady, existing.purpose == purpose {
            connections[id]?.advancedServices = existing.services
            return existing
        }
        if let previous = link.utlSession {
            // A failed owned channel must be released before choosing another.
            // stop is scoped to this process's client ID and selected channel.
            await previous.stop()
            guard liveLink(id) === link else { throw UTLSession.SessionError.disconnected }
            if link.utlSession === previous { link.utlSession = nil }
        }
        // A newly opened channel has not supplied its EQ step size/ranges or
        // current feature state. Preserve drafts only when reusing a ready
        // session; never send a legacy-scale draft through an unqueried UTL EQ.
        invalidateEqualizer(id, microphone: true); invalidateEqualizer(id, microphone: false)
        invalidateConsumerFeatures(id, link: link)
        guard let information = link.utlCharacteristics[UTLProtocol.information],
              let control = link.utlCharacteristics[UTLProtocol.control] else {
            throw UTLSession.SessionError.unavailable("This aid does not expose the advanced transport.")
        }
        let info = try UTLProtocol.GattInformation(data: try await readUtility(id, characteristic: information))
        let key = try UTLSession.loadKey(keyURL ?? UTLSession.defaultKeyURL)
        let session = try UTLSession(info: info, physicalATTMTU: link.peripheral.maximumWriteValueLength(for: .withResponse) + 3,
            progress: { [weak self, weak link] stage in
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
                guard let self, let link, self.liveLink(id) === link,
                      let characteristic = link.utlCharacteristics[uuid] else { throw UTLSession.SessionError.disconnected }
                try await self.writeUtility(id, characteristic: characteristic, data: data)
            }
        guard let output = link.utlCharacteristics[UTLProtocol.outputs[Int(session.channel)]] else {
            throw UTLSession.SessionError.unavailable("Advanced channel output is absent.")
        }
        link.utlSession = session
        try await subscribeUtility(id, characteristic: control)
        try await subscribeUtility(id, characteristic: output)
        try await session.start(key: key, purpose: purpose)
        guard liveLink(id) === link else { throw UTLSession.SessionError.disconnected }
        connections[id]?.advancedServices = session.services
        record("advanced_authenticated", "Advanced channel authenticated; service registry read",
               details: ["uuid": id.uuidString, "services": session.services.map {
                   String(format: "%08X/%u.%u", $0.id, $0.major, $0.minor)
               }.joined(separator: ",")])
        return session
    }

    /// Explicit read-only metadata load. It uses the normal consumer channel,
    /// without requiring EQ support or requesting fitting/firmware operations.
    func refreshDeviceMetadata(_ id: UUID, keyURL: URL? = nil) {
        guard probeConfiguration == nil, let link = liveLink(id), link.pending == nil,
              connections[id]?.actionPending == false, connections[id]?.advancedBusy == false,
              connections[id]?.groupActionPending == false else { return }
        connections[id]?.advancedBusy = true
        connections[id]?.deviceMetadataStatus = "Reading device details…"
        Task { [weak self, weak link] in
            guard let self, let link else { return }
            defer { if self.liveLink(id) === link { self.connections[id]?.advancedBusy = false } }
            do {
                let session = try await self.readyAdvancedSession(id, link: link, keyURL: keyURL)
                await self.readDeviceMetadata(id, link: link, session: session)
            } catch {
                guard self.liveLink(id) === link else { return }
                if let session = link.utlSession, !session.isReady {
                    await session.stop()
                    if link.utlSession === session { link.utlSession = nil }
                    self.invalidateEqualizer(id, microphone: true); self.invalidateEqualizer(id, microphone: false)
                    self.invalidateConsumerFeatures(id, link: link)
                }
                self.connections[id]?.deviceMetadataStatus = "Device details: \(UTLSession.describe(error))"
            }
        }
    }

    private func readDeviceMetadata(_ id: UUID, link: AidLink, session: UTLSession,
                                    didReadIdentification: ((Data) -> Void)? = nil) async {
        var failures: [String] = []
        if session.supportsIdentification {
            do {
                let identity = try await session.identification()
                // Preserve a successful response before an ancillary query can
                // fail and close the session, which clears its live raw state.
                if let payload = session.identificationPayload { didReadIdentification?(payload) }
                guard liveLink(id) === link, link.utlSession === session else { return }
                connections[id]?.deviceMetadata = identity.metadata
                if let serial = identity.serialNumber { connections[id]?.serialNumber = serial }
                if !identity.metadata.invalidFields.isEmpty {
                    failures.append("Identification fields unavailable: " + identity.metadata.invalidFields.joined(separator: ", ") + ".")
                }
            } catch {
                guard liveLink(id) === link, link.utlSession === session else { return }
                connections[id]?.deviceMetadata = nil
                failures.append("Identification: \(UTLSession.describe(error))")
            }
        } else {
            connections[id]?.deviceMetadata = nil
            failures.append("No supported identification service is advertised.")
        }
        if session.supportsBatteryTelemetry, session.isReady {
            do {
                let health = try await session.batteryHealth()
                guard liveLink(id) === link, link.utlSession === session else { return }
                connections[id]?.batteryHealth = health
            } catch {
                guard liveLink(id) === link, link.utlSession === session else { return }
                connections[id]?.batteryHealth = nil
                failures.append("Battery health: \(UTLSession.describe(error))")
            }
        } else {
            connections[id]?.batteryHealth = nil
            failures.append("Battery health is unavailable through the current consumer service.")
        }
        if session.supportsCoreDumpInfo, session.isReady {
            do {
                let info = try await session.coreDumpInfo()
                guard liveLink(id) === link, link.utlSession === session else { return }
                connections[id]?.coreDumpInfo = info
            } catch {
                guard liveLink(id) === link, link.utlSession === session else { return }
                connections[id]?.coreDumpInfo = nil
                failures.append("Crash-dump counters: \(UTLSession.describe(error))")
            }
        } else { connections[id]?.coreDumpInfo = nil }
        if !session.isReady {
            await session.stop()
            guard liveLink(id) === link else { return }
            if link.utlSession === session { link.utlSession = nil }
            invalidateEqualizer(id, microphone: true); invalidateEqualizer(id, microphone: false)
            invalidateConsumerFeatures(id, link: link)
            failures.append("The advanced channel closed; reload device details.")
        }
        guard liveLink(id) === link else { return }
        connections[id]?.deviceMetadataStatus = failures.isEmpty ? "Device details read from hearing aid." : failures.joined(separator: " ")
    }

    /// Load just consumer EQs when their editor opens. Do not hold their busy
    /// state for serial-number, battery or SpeechBooster queries.
    func loadEqualizersIfNeeded(_ ids: [UUID], microphone: Bool, retry: Bool = false) {
        guard !isDemo, probeConfiguration == nil else { return }
        for id in ids {
            guard let aid = connections[id], liveLink(id) != nil else { continue }
            let loaded = microphone
                ? aid.microphoneEqualizer != nil && aid.writableMicrophoneEqualizer
                : aid.streamingEqualizer != nil && aid.writableStreamingEqualizer
            if loaded && !retry { continue }
            let context = EqualizerLoader.Context(id: id, connectedAt: aid.connectedAt, program: aid.activeProgram)
            // A later program/channel invalidation needs a new read even if an
            // earlier read in this connection completed successfully.
            let completed = equalizerLoader.states[id]?.status == .loaded
            equalizerLoader.request(context, retry: retry || completed)
        }
    }

    private func readEqualizers(_ context: EqualizerLoader.Context) async throws {
        let id = context.id
        guard let link = liveLink(id) else { throw UTLSession.SessionError.disconnected }
        func validate() throws {
            guard liveLink(id) === link, let aid = connections[id],
                  aid.connectedAt == context.connectedAt, aid.activeProgram == context.program else {
                throw UTLSession.SessionError.unavailable("The hearing aid or program changed during the EQ read.")
            }
        }
        let waitDeadline = Date().addingTimeInterval(12)
        while connections[id]?.advancedBusy == true || connections[id]?.actionPending == true
                || connections[id]?.groupActionPending == true || link.pending != nil {
            try validate()
            guard Date() < waitDeadline else {
                throw UTLSession.SessionError.unavailable("Another device operation is still running. Try loading the EQ again.")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        try validate()
        connections[id]?.advancedBusy = true
        connections[id]?.advancedStatus = "Loading equalizers…"
        defer { if liveLink(id) === link { connections[id]?.advancedBusy = false } }
        do {
            let session = try await readyAdvancedSession(id, link: link)
            try validate()
            guard let service = session.services.first(where: { UTLAdvanced.supportsEqualizer($0, microphone: false) }) else {
                throw UTLSession.SessionError.unavailable("No supported equalizer contract was advertised.")
            }
            let deadline = Date().addingTimeInterval(20)
            let step: Double
            if service.major >= 2 { step = try await session.equalizerStep(deadline: deadline) }
            else {
                _ = try? await session.equalizerStep(deadline: deadline)
                step = OticonEqualizer.defaultStepDB
            }
            try validate()
            let microphoneEQ = UTLAdvanced.supportsEqualizer(service, microphone: true)
                ? try await session.equalizer(microphone: true, stepDB: step, deadline: deadline) : nil
            try validate()
            let streamingEQ = try await session.equalizer(microphone: false, stepDB: step, deadline: deadline)
            try validate()
            connections[id]?.microphoneEqualizer = microphoneEQ
            connections[id]?.writableMicrophoneEqualizer = microphoneEQ != nil
            connections[id]?.streamingEqualizer = streamingEQ
            connections[id]?.writableStreamingEqualizer = true
            connections[id]?.advancedStatus = "Advanced equalizers read from hearing aid."
            record("equalizers_read", "Consumer equalizers read from hearing aid", details: ["uuid": id.uuidString])
        } catch {
            guard liveLink(id) === link else { throw error }
            connections[id]?.advancedStatus = "Advanced controls: \(UTLSession.describe(error))"
            if let session = link.utlSession {
                await session.stop()
                if link.utlSession === session { link.utlSession = nil }
            }
            invalidateEqualizer(id, microphone: true); invalidateEqualizer(id, microphone: false)
            invalidateConsumerFeatures(id, link: link)
            record("equalizers_unavailable", "Consumer EQ read stopped: \(UTLSession.describe(error))", details: ["uuid": id.uuidString])
            throw error
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
                let session = try await self.readyAdvancedSession(id, link: link, keyURL: keyURL)
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
                guard self.liveLink(id) === link else { return }
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
                failures.append("Battery telemetry: \(UTLSession.describe(error))")
            }
        }
        if session.supportsIdentification, connections[id]?.serialNumber == nil {
            do {
                let identity = try await session.identification()
                guard liveLink(id) === link else { return }
                connections[id]?.serialNumber = identity.serialNumber
                connections[id]?.deviceMetadata = identity.metadata
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
        if let sample = batteryCache?.record(telemetry, for: id) { connections[id]?.cachedBatteryReading = sample }
        if !telemetry.hasCorruptZeroTelemetry, let percentage = telemetry.percentage { connections[id]?.battery = percentage }
        record("battery_telemetry", "Battery telemetry read from hearing aid", details: ["uuid": id.uuidString])
    }
    /// Battery refresh authenticates only the existing consumer channel when a
    /// local credential is present. It does not load EQ or write a sound setting.
    func refreshBattery(_ id: UUID) {
        guard probeConfiguration == nil, let link = liveLink(id), link.pending == nil,
              connections[id]?.advancedBusy == false, connections[id]?.actionPending == false,
              connections[id]?.groupActionPending == false else { return }
        connections[id]?.advancedBusy = true
        Task { [weak self, weak link] in
            guard let self, let link else { return }
            defer { if self.liveLink(id) === link { self.connections[id]?.advancedBusy = false } }
            do {
                let session = try await self.readyAdvancedSession(id, link: link)
                guard self.liveLink(id) === link, session.supportsBatteryTelemetry else { return }
                let telemetry = try await session.batteryTelemetry()
                guard self.liveLink(id) === link else { return }
                self.updateBatteryTelemetry(id, telemetry: telemetry)
                self.startBatteryPolling(id, link: link)
            } catch {
                guard self.liveLink(id) === link else { return }
                self.record("battery_refresh_unavailable", "Battery reading was not refreshed; retaining the previous timestamp", details: ["uuid": id.uuidString])
            }
        }
    }
    private func startAutomaticConsumerRead(_ id: UUID, link: AidLink) {
        guard probeConfiguration == nil, !link.automaticConsumerReadRequested,
              link.utlCharacteristics[UTLProtocol.information] != nil,
              link.utlCharacteristics[UTLProtocol.control] != nil,
              FileManager.default.fileExists(atPath: UTLSession.defaultKeyURL.path) else { return }
        link.automaticConsumerReadRequested = true
        Task { [weak self, weak link] in
            guard let self, let link else { return }
            let deadline = Date().addingTimeInterval(30)
            // Let discovery and the initial native reads finish first.
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            while self.liveLink(id) === link && Date() < deadline {
                if self.connections[id]?.canChangeVolume == true && link.pending == nil {
                    self.connections[id]?.advancedBusy = true
                    defer { if self.liveLink(id) === link { self.connections[id]?.advancedBusy = false } }
                    do {
                        let session = try await self.readyAdvancedSession(id, link: link)
                        guard self.liveLink(id) === link else { return }
                        await self.readConsumerFeatures(id, link: link, session: session)
                    } catch {
                        self.record("consumer_auto_read_unavailable", "Automatic device feature reading is unavailable; cached battery age is preserved", details: ["uuid": id.uuidString])
                    }
                    return
                }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
        }
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
            var retryDelay: TimeInterval? = self.connections[id]?.batteryTelemetryUpdatedAt == nil ? 300 : nil
            while !Task.isCancelled {
                guard self.liveLink(id) === link else { return }
                let retryingZero = self.connections[id]?.batteryTelemetry?.hasCorruptZeroTelemetry == true && link.batteryZeroRetryCount < 12
                let age = self.connections[id]?.batteryTelemetryUpdatedAt.map { Date().timeIntervalSince($0) } ?? 0
                let delay = retryDelay ?? (retryingZero ? 5 : max(5, BatteryRuntimeReading.refreshInterval - age))
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
                guard self.liveLink(id) === link else { return }
                if !self.deviceBackupBusy && link.pending == nil && self.connections[id]?.advancedBusy == false && self.connections[id]?.actionPending == false && self.connections[id]?.groupActionPending == false {
                    self.connections[id]?.advancedBusy = true
                    defer { if self.liveLink(id) === link { self.connections[id]?.advancedBusy = false } }
                    do {
                        let session = try await self.readyAdvancedSession(id, link: link)
                        guard session.supportsBatteryTelemetry else { return }
                        let telemetry = try await session.batteryTelemetry()
                        guard self.liveLink(id) === link else { return }
                        self.updateBatteryTelemetry(id, telemetry: telemetry)
                        link.batteryZeroRetryCount = telemetry.hasCorruptZeroTelemetry ? link.batteryZeroRetryCount + 1 : 0
                        retryDelay = nil
                    } catch { retryDelay = 300 }
                    if self.liveLink(id) === link { self.connections[id]?.advancedBusy = false }
                } else { retryDelay = 60 }
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
    func setEqualizerChannels(_ ids: [UUID], microphone: Bool, levelsByAid: [UUID: [Double]]) {
        performConsumerChange(ids, change: .equalizerChannels(microphone: microphone, levelsByAid: levelsByAid))
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
                if step.expectedVolume != nil {
                    for uuid in [OticonRemoteProtocol.volumeRanges, OticonRemoteProtocol.mainVolume] {
                        guard let characteristic = original.remoteCharacteristics[uuid], characteristic.properties.contains(.read) else {
                            throw UTLSession.SessionError.unavailable("Current volume and limits are unavailable.")
                        }
                        _ = try await self.readUtility(step.aidID, characteristic: characteristic)
                    }
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
                        try await self.awaitSetting(step.aidID, characteristicUUID: OticonRemoteProtocol.mainVolume, data: payload, label: "Volume and mute")
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
        connections[id]?.advancedServices = []
        connections[id]?.batteryHealth = nil
        connections[id]?.coreDumpInfo = nil
        link.legacySpeechBoosterData = nil
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
            if characteristic == OticonRemoteProtocol.tinnitusVolume { connections[id]?.tinnitusVolume = nil }
            if characteristic == OticonRemoteProtocol.streamingVolume { connections[id]?.streamingVolume = nil }
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
        if let validRSSI, (-127 ... -1).contains(validRSSI) {
            measuredSignals[peripheral.identifier] = .init(rssi: validRSSI, measuredAt: Date())
        }
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
                if characteristic.uuid.uuidString.uppercased() == OticonRemoteProtocol.tinnitusVolume { connections[id]?.writableTinnitusVolume = characteristic.properties.contains(.write) && characteristic.properties.contains(.read) }
                if characteristic.uuid.uuidString.uppercased() == OticonRemoteProtocol.streamingVolume { connections[id]?.writableStreamingVolume = characteristic.properties.contains(.write) && characteristic.properties.contains(.read) }
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
        startAutomaticConsumerRead(id, link: link)
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
            if connections[id]?.receiveRevision(service: service, characteristic: characteristic, data: value) != true {
                switch characteristic {
                case "2A29": connections[id]?.manufacturer = StandardGATT.informationString(value)
                case "2A24": connections[id]?.model = StandardGATT.informationString(value)
                case "2A25": connections[id]?.serialNumber = StandardGATT.informationString(value)
                default: break
                }
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
            case OticonRemoteProtocol.tinnitusVolume: connections[id]?.tinnitusVolume = OticonRemoteProtocol.Volume(data: value)
            case OticonRemoteProtocol.streamingVolume: connections[id]?.streamingVolume = OticonRemoteProtocol.Volume(data: value)
            case OticonRemoteProtocol.volumeRanges: connections[id]?.volumeRanges = OticonRemoteProtocol.VolumeRanges(data: value)
            case OticonRemoteProtocol.activeProgram:
                let program = value.count == 1 ? value.first.map(Int.init) : nil
                if let old = connections[id]?.activeProgram, old != program {
                    connections[id]?.tinnitusVolume = nil; connections[id]?.streamingVolume = nil
                    connections[id]?.tinnitusStatus = nil; connections[id]?.streamingVolumeStatus = nil
                    connections[id]?.microphoneEqualizer = nil
                    connections[id]?.streamingEqualizer = nil
                    connections[id]?.writableMicrophoneEqualizer = false
                    connections[id]?.volumeRanges = nil
                    connections[id]?.speechBoosterEnabled = nil
                    connections[id]?.writableSpeechBooster = false
                    if let link = liveLink(id), let ranges = link.remoteCharacteristics[OticonRemoteProtocol.volumeRanges], ranges.properties.contains(.read) { link.peripheral.readValue(for: ranges) }
                    if let link = liveLink(id), let eq = link.remoteCharacteristics[OticonEqualizer.legacyCharacteristic], eq.properties.contains(.read) { link.peripheral.readValue(for: eq) }
                    if let link = liveLink(id) {
                        for uuid in [OticonRemoteProtocol.tinnitusVolume, OticonRemoteProtocol.streamingVolume] {
                            if let characteristic = link.remoteCharacteristics[uuid], characteristic.properties.contains(.read) { link.peripheral.readValue(for: characteristic) }
                        }
                    }
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
