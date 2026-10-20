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
    init(_ peripheral: CBPeripheral) { self.peripheral = peripheral }
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
        guard let link = liveLink(id), connections[id]?.actionPending == false else { return }
        connections[id]?.error = nil
        for service in link.peripheral.services ?? [] {
            for characteristic in service.characteristics ?? [] { readIfAllowed(characteristic, service: service, link: link) }
        }
        record("refresh_requested", "Refreshing current hearing-aid values", details: ["uuid": id.uuidString])
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
    private func writeSetting(_ id: UUID, characteristicUUID: String, data: Data, label: String) {
        guard probeConfiguration == nil, let link = liveLink(id), link.pending == nil,
              let characteristic = link.remoteCharacteristics[characteristicUUID],
              characteristic.properties.contains(.write), characteristic.properties.contains(.read) else { return }
        let pending = PendingSetting(characteristic: characteristic, expected: data, label: label)
        link.pending = pending
        connections[id]?.actionPending = true
        connections[id]?.actionFailed = false
        connections[id]?.actionStatus = "Sending \(label.lowercased())…"
        record("setting_requested", "\(label) requested by user", details: ["uuid": id.uuidString, "characteristic": characteristicUUID, "payload_hex": data.hexString])
        link.peripheral.writeValue(data, for: characteristic, type: .withResponse)
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
        link.serviceIDs = [:]; link.characteristicIDs = [:]; link.remoteCharacteristics = [:]
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
            }
            readIfAllowed(characteristic, service: service, link: link)
            if ReadOnlyInspection.shouldNotify(service: service.uuid.uuidString, characteristic: characteristic.uuid.uuidString),
               characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) { peripheral.setNotifyValue(true, for: characteristic) }
        }
    }
    private func readIfAllowed(_ characteristic: CBCharacteristic, service: CBService, link: AidLink) {
        guard ReadOnlyInspection.name(service: service.uuid.uuidString, characteristic: characteristic.uuid.uuidString) != nil, characteristic.properties.contains(.read) else { return }
        link.peripheral.readValue(for: characteristic)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        let id = peripheral.identifier
        guard let link = liveLink(id), link.peripheral === peripheral else { return }
        if let error { reportGATTError(error, id: id, stage: "read"); return }
        guard let service = characteristic.service, ReadOnlyInspection.name(service: service.uuid.uuidString, characteristic: characteristic.uuid.uuidString) != nil, let value = characteristic.value else { return }
        let text = ReadOnlyInspection.displayValue(service: service.uuid.uuidString, characteristic: characteristic.uuid.uuidString, data: value)
        updateCharacteristic(id, link: link, characteristic: characteristic) { $0.value = text }
        updateLiveState(id, service: service.uuid.uuidString, characteristic: characteristic.uuid.uuidString, value: value)
        record("gatt_value", "Read-only GATT value received", details: ["uuid": id.uuidString, "service": service.uuid.uuidString, "characteristic": characteristic.uuid.uuidString, "value": text, "value_hex": value.hexString])
        if let pending = link.pending, pending.characteristic === characteristic, pending.stage == .readback {
            if value == pending.expected { completeSetting(id, link: link, message: "\(pending.label) confirmed by hearing aid", failed: false) }
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
            case OticonRemoteProtocol.activeProgram: connections[id]?.activeProgram = value.count == 1 ? value.first.map(Int.init) : nil
            case OticonRemoteProtocol.availablePrograms: connections[id]?.programIDs = OticonRemoteProtocol.programIDs(bitmap: value) ?? []
            default: break
            }
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
