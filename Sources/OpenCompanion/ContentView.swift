import CompanionCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: BluetoothStore
    let audiogramStore: AudiogramEditorStore
    let notifications: BatteryNotificationManager
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var presets: SoundPresetStore
    @State private var showAllDevices = false
    @State private var showInspector = false
    @State private var showEvents = false

    private var visibleDevices: [NearbyDevice] { store.devices.filter { showAllDevices || $0.isCandidate } }

    var body: some View {
        TabView(selection: $navigation.page) {
            HSplitView {
                discoveryPane.frame(minWidth: 260, idealWidth: 290, maxWidth: 320)
                dashboard.frame(minWidth: 730, maxWidth: .infinity)
            }
            .tabItem { Label(AppPage.hearingAids.title, systemImage: AppPage.hearingAids.symbol).accessibilityIdentifier("navigation-hearing-aids") }
            .tag(AppPage.hearingAids)

            DeviceExplorerView(store: store)
                .tabItem { Label(AppPage.devices.title, systemImage: AppPage.devices.symbol).accessibilityIdentifier("navigation-devices") }
                .tag(AppPage.devices)

            AudiogramEditorView(store: audiogramStore, onSaved: { exam in
                presets.linkedAudiogramID = exam.id
                presets.linkedAudiogramLabel = exam.name + (exam.examDate.map { " · \($0)" } ?? "")
            })
            .tabItem { Label(AppPage.audiogram.title, systemImage: AppPage.audiogram.symbol).accessibilityIdentifier("navigation-audiogram") }
            .tag(AppPage.audiogram)

            AppSettingsView(notifications: notifications)
                .tabItem { Label(AppPage.settings.title, systemImage: AppPage.settings.symbol).accessibilityIdentifier("navigation-settings") }
                .tag(AppPage.settings)
        }
        .frame(minWidth: 1050, minHeight: 700)
        .tint(Color.teal)
        .toolbar {
            ToolbarItem(placement: .principal) { Label("Open Companion", systemImage: "ear.badge.waveform").font(.headline) }
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
                    HearingAidControlsView(store: store)
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
