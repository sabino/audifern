import CompanionCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: BluetoothStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage("linkedHearingAidControls") private var linkedControls = true
    @State private var showAllDevices = false
    @State private var showInspector = false
    @State private var showEvents = false

    private var visibleDevices: [NearbyDevice] { store.devices.filter { showAllDevices || $0.isCandidate } }
    private var aidColumns: [GridItem] {
        store.orderedConnections.count > 1
            ? [GridItem(.flexible(minimum: 330)), GridItem(.flexible(minimum: 330))]
            : [GridItem(.flexible(minimum: 330, maximum: 700))]
    }

    var body: some View {
        HSplitView {
            discoveryPane.frame(minWidth: 260, idealWidth: 290, maxWidth: 320)
            dashboard.frame(minWidth: 730, maxWidth: .infinity)
        }
        .frame(minWidth: 1050, minHeight: 700)
        .tint(Color.teal)
        .toolbar {
            ToolbarItem(placement: .principal) { Label("Open Companion", systemImage: "ear.badge.waveform").font(.headline) }
            ToolbarItem { Button("Audiogram", systemImage: "chart.xyaxis.line") { openWindow(id: "audiogram") } }
            ToolbarItem {
                Button("Battery alerts", systemImage: "bell.badge") { openSettings() }
                    .help("Battery notification settings")
            }
            ToolbarItem {
                Label(store.bluetoothStatus, systemImage: store.isPoweredOn ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                    .font(.caption).foregroundStyle(store.isPoweredOn ? Color.secondary : Color.orange)
            }
        }
    }

    private var discoveryPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "ear.badge.waveform").font(.title2).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Companion").font(.headline)
                    Text("Your hearing, within reach").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 12)
            HStack {
                Text("DEVICES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if store.isScanning { ProgressView().controlSize(.mini) }
                Button { store.isScanning ? store.stopScan() : store.startScan() } label: {
                    Image(systemName: store.isScanning ? "stop.circle" : "arrow.clockwise")
                }
                .buttonStyle(.borderless).disabled(!store.isPoweredOn)
                .help(store.isScanning ? "Stop scanning" : "Scan nearby")
                .accessibilityLabel(store.isScanning ? "Stop scanning" : "Scan nearby")
            }
            if visibleDevices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Find your hearing aids").font(.headline)
                    Text("Keep them nearby, then scan. Devices already connected to your Mac appear here too.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Scan nearby") { store.startScan() }.disabled(!store.isPoweredOn)
                }.padding(.vertical, 28).frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) { ForEach(visibleDevices) { device in deviceRow(device) } }
                }
            }
            if store.pairCandidateIDs.count == 2 {
                Button { store.connectPair() } label: { Label("Connect both hearing aids", systemImage: "link") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(!store.isPoweredOn || store.pairCandidateIDs.allSatisfy { store.connections[$0]?.isConnected == true })
                    .accessibilityIdentifier("connect-matched-pair")
            }
            Toggle("Show all nearby BLE devices", isOn: $showAllDevices).toggleStyle(.checkbox).font(.caption)
            Text("Connect uses Bluetooth directly. No account or cloud session is needed for the verified remote service.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func deviceRow(_ device: NearbyDevice) -> some View {
        let state = store.connections[device.id]
        let selected = store.selectedPeripheralID == device.id
        let busy = state?.phase == .connecting || state?.phase == .disconnecting
        return VStack(alignment: .leading, spacing: 10) {
            Button { store.select(device.id) } label: {
                HStack(spacing: 10) {
                    Image(systemName: device.isCandidate ? "ear" : "wave.3.right")
                        .font(.title2).foregroundStyle(device.isCandidate ? Color.teal : Color.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state?.model ?? device.name).font(.callout.weight(.semibold)).lineLimit(1)
                        Text(state.map { $0.isConnected ? "\($0.sideLabel) · Connected" : $0.phase.label } ?? (device.isSystemConnected ? "Available on this Mac" : "Nearby"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if state?.isConnected == true { Circle().fill(.teal).frame(width: 6, height: 6) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            HStack {
                if let rssi = device.rssi { Text("\(rssi) dBm").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
                Spacer()
                if busy { ProgressView().controlSize(.mini) }
                if state?.isConnected == true || state?.phase == .connecting {
                    Button("Disconnect") { store.disconnect(device.id) }.font(.caption).buttonStyle(.borderless)
                } else {
                    Button("Connect") { store.connect(to: device.id) }
                        .font(.caption).buttonStyle(.borderless)
                        .disabled(!store.isPoweredOn || busy || (device.isConnectable == false && !device.isSystemConnected))
                }
            }
        }
        .padding(12)
        .background(selected ? Color.teal.opacity(0.09) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.teal.opacity(0.4) : Color.primary.opacity(0.07)))
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your hearing aids").font(.system(size: 29, weight: .semibold, design: .rounded))
                        Text(store.connectedCount > 0 ? "\(store.connectedCount) connected · Direct Bluetooth control" : "A quieter place to manage your hearing.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Link ears", isOn: $linkedControls).toggleStyle(.switch)
                        .fixedSize().accessibilityIdentifier("link-ear-controls")
                        .help("Use one volume and mute control for both ears")
                    Label("LOCAL", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.teal)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.teal.opacity(0.09), in: Capsule())
                }
                if let error = store.lastError { Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange) }

                if store.orderedConnections.isEmpty {
                    ContentUnavailableView {
                        Label("Ready when you are", systemImage: "ear.badge.waveform")
                    } description: {
                        Text("Choose your hearing aids in the sidebar, or connect both when the pair is available.")
                    }.frame(minHeight: 310)
                } else {
                    if linkedControls {
                        LinkedControlsView(store: store)
                        if store.connectedPair.count == 2 {
                            SpeechBoosterView(store: store, ids: store.connectedPair.map(\.id))
                                .padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    LazyVGrid(columns: aidColumns, spacing: 16) {
                        ForEach(store.orderedConnections) { state in aidCard(state) }
                    }
                }
                SoundPresetPanelView(store: store)

                Text("Controls adjust the microphone level on the selected aid. Changes are confirmed from the device; streaming audio volume is separate.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                DisclosureGroup(isExpanded: $showInspector) {
                    inspector.padding(.top, 14)
                } label: {
                    Label("Connection inspector", systemImage: "slider.horizontal.3").font(.callout.weight(.medium))
                }
                DisclosureGroup(isExpanded: $showEvents) {
                    eventList.padding(.top, 12)
                } label: {
                    Label("This session", systemImage: "clock").font(.callout.weight(.medium))
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
    }

    private func aidCard(_ state: AidConnection) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(state.sideLabel).font(.title3.weight(.semibold))
                    Text(state.model ?? state.name).font(.caption).foregroundStyle(.secondary)
                    if linkedControls {
                        Text(state.volume.map { $0.muted ? "Muted" : "Sound on" } ?? state.phase.label)
                            .font(.caption2).foregroundStyle(state.volume?.muted == true ? Color.orange : Color.secondary)
                    }
                }
                Spacer()
                AidBatteryView(store: store, aid: state)
            }
            if !linkedControls {
              HStack {
                Image(systemName: "ear").font(.system(size: 58, weight: .ultraLight))
                    .foregroundStyle(.teal).frame(width: 80, height: 86)
                    .background(Color.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                    .scaleEffect(x: state.sideLabel == "Right" ? -1 : 1, y: 1)
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(state.volume.map { $0.level > 0 ? "+\($0.level)" : String($0.level) } ?? "—")
                        .font(.system(size: 42, weight: .light, design: .rounded)).monospacedDigit()
                    Text("Microphone level").font(.caption).foregroundStyle(.secondary)
                    Text(state.volume.map { $0.muted ? "Muted" : "Sound on" } ?? state.phase.label)
                        .font(.caption.weight(.medium)).foregroundStyle(state.isConnected ? Color.teal : Color.secondary)
                }
            }
            HStack(spacing: 10) {
                Button { store.adjustVolume(state.id, by: -1) } label: { Image(systemName: "minus").frame(maxWidth: .infinity, minHeight: 26) }
                    .disabled(!state.canChangeVolume || state.volume?.level == state.volumeRanges?.main.lowerBound)
                    .accessibilityLabel("Decrease \(state.sideLabel.lowercased()) microphone level")
                Button { store.setMuted(state.id, muted: !(state.volume?.muted ?? false)) } label: {
                    Label(state.volume?.muted == true ? "Unmute" : "Mute", systemImage: state.volume?.muted == true ? "speaker.wave.2" : "speaker.slash")
                        .frame(maxWidth: .infinity, minHeight: 26)
                }.disabled(!state.canChangeVolume)
                Button { store.adjustVolume(state.id, by: 1) } label: { Image(systemName: "plus").frame(maxWidth: .infinity, minHeight: 26) }
                    .disabled(!state.canChangeVolume || state.volume?.level == state.volumeRanges?.main.upperBound)
                    .accessibilityLabel("Increase \(state.sideLabel.lowercased()) microphone level")
              }.buttonStyle(.bordered).controlSize(.large)
            }
            Divider()
            HStack {
                Label("Program", systemImage: "waveform").font(.callout).foregroundStyle(.secondary)
                Spacer()
                if let active = state.activeProgram {
                    Picker("Program", selection: Binding(get: { active }, set: { store.selectProgram(state.id, program: $0) })) {
                        ForEach(Array(state.programIDs.enumerated()), id: \.element) { offset, id in
                            Text(state.programNames[id] ?? "Program \(offset + 1)").tag(id)
                        }
                        if !state.programIDs.contains(active) { Text(state.programNames[active] ?? "Current program").tag(active) }
                    }.labelsHidden().frame(maxWidth: 145).disabled(!state.canChangeProgram || state.programIDs.count < 2)
                } else { Text("—").foregroundStyle(.secondary) }
            }
            if state.programNames.isEmpty && state.isConnected {
                Button("Read program names") { store.refreshProgramInfo(state.id) }
                    .font(.caption).buttonStyle(.borderless)
                    .disabled(state.actionPending || state.advancedBusy || state.groupActionPending)
            }
            if !linkedControls {
                SpeechBoosterView(store: store, ids: [state.id])
            }
            Divider()
            EqualizerControlsView(store: store, aidID: state.id)
            Divider()
            DeviceDetailsView(store: store, aid: state)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if state.actionPending || state.phase == .connecting { ProgressView().controlSize(.mini) }
                    else { Circle().fill(state.isConnected ? Color.teal : Color.secondary).frame(width: 6, height: 6) }
                    Text(state.actionStatus ?? (state.isConnected ? "Live status from your hearing aid" : state.phase.label))
                        .font(.caption).foregroundStyle(state.actionFailed ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(minHeight: 30, alignment: .top)
                if let error = state.error { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    Button("Details") { store.select(state.id); showInspector = true }.buttonStyle(.borderless)
                    Spacer()
                    Button { store.refresh(state.id) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).disabled(!state.isConnected || state.actionPending || state.advancedBusy || state.groupActionPending).help("Refresh current values")
                        .accessibilityLabel("Refresh \(state.sideLabel.lowercased()) values")
                }.font(.caption)
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.06)))
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let state = store.selectedConnection {
                HStack {
                    Text("\(state.sideLabel) · \(state.model ?? state.name)").font(.headline)
                    Spacer()
                    if state.isConnected { Button("Disconnect") { store.disconnect(state.id) }.buttonStyle(.borderless) }
                }
                Text(state.id.uuidString).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                if let firmware = state.firmware { Text("Firmware \(firmware)").font(.caption).foregroundStyle(.secondary) }
                if !state.isConnected { Text("Disconnected. Previous values have been cleared.").font(.callout).foregroundStyle(.secondary) }
                ForEach(state.services) { service in serviceSection(service) }
            } else { Text("Choose Details on a hearing aid to inspect its connection.").font(.callout).foregroundStyle(.secondary) }
        }
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Spacer(); Button("Clear") { store.clearEvents() }.buttonStyle(.borderless).font(.caption) }
            ForEach(store.events.suffix(35).reversed()) { event in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(event.timestamp, style: .time).monospacedDigit().foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                    Text(event.message).textSelection(.enabled)
                    Spacer(minLength: 0)
                }.font(.caption)
            }
        }
    }

    private func serviceSection(_ service: GATTServiceInfo) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(service.characteristics) { characteristic in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(ReadOnlyInspection.name(service: service.uuid, characteristic: characteristic.uuid) ?? characteristic.uuid)
                                .font(.callout.weight(.medium)).textSelection(.enabled)
                            Spacer(minLength: 4)
                            if characteristic.isNotifying { Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.teal).help("Live notifications enabled") }
                        }
                        if ReadOnlyInspection.name(service: service.uuid, characteristic: characteristic.uuid) != nil {
                            Text(characteristic.uuid).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Text(characteristic.properties).font(.caption).foregroundStyle(.secondary)
                        if let value = characteristic.value { Text(value).font(.callout.monospaced()).textSelection(.enabled) }
                    }
                    if characteristic.id != service.characteristics.last?.id { Divider() }
                }
                if service.characteristics.isEmpty { Text("Discovering characteristics…").font(.caption).foregroundStyle(.secondary) }
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(serviceName(service.uuid)).font(.headline)
                if serviceName(service.uuid) != service.uuid { Text(service.uuid).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
            }
        }
    }

    private func serviceName(_ uuid: String) -> String {
        switch HearingAidDiscovery.normalizedUUID(uuid) {
        case "1800": "Generic Access"
        case "1801": "Generic Attribute"
        case "180A": "Device Information"
        case "180F": "Battery"
        case "1844": "Volume Control"
        case "1850": "Published Audio Capabilities"
        case "1854": "Hearing Access"
        case "FDF0": "Audio Streaming for Hearing Aids"
        case HearingAidDiscovery.legacyRemoteService: "Oticon remote control"
        case HearingAidDiscovery.universalTransportService: "Oticon universal transport"
        default: uuid
        }
    }
}
