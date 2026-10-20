import CompanionCore
import SwiftUI

/// Device identification and diagnostics stay inside the same application window.
/// Only explicitly implemented, version-bounded getters are offered here.
struct DeviceExplorerView: View {
    @ObservedObject var store: BluetoothStore
    @State private var showRegistry = false
    @State private var showGATT = false
    @State private var showFirmware = false

    private var aids: [AidConnection] {
        store.orderedConnections.sorted { left, right in
            if left.sideLabel == "Left" && right.sideLabel == "Right" { return true }
            if left.sideLabel == "Right" && right.sideLabel == "Left" { return false }
            return left.id.uuidString < right.id.uuidString
        }
    }
    private var selected: AidConnection? {
        store.selectedPeripheralID.flatMap { store.connections[$0] } ?? aids.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Device information").font(.system(size: 29, weight: .semibold, design: .rounded))
                    Text("Versions, battery data and diagnostics reported independently by each hearing aid.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if aids.isEmpty {
                    ContentUnavailableView("Connect your hearing aids", systemImage: "ear.badge.waveform",
                                           description: Text("Connect them in Hearing aids to read their device information."))
                        .frame(minHeight: 300)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(minimum: 380)), GridItem(.flexible(minimum: 380))], alignment: .leading, spacing: 20) {
                        ForEach(aids) { deviceCard($0) }
                    }
                    Divider()
                    Picker("Inspect an aid", selection: Binding(get: { selected?.id }, set: { if let id = $0 { store.select(id) } })) {
                        ForEach(aids) { aid in Text("\(aid.sideLabel) · \(aid.model ?? aid.name)").tag(Optional(aid.id)) }
                    }.frame(maxWidth: 420).accessibilityIdentifier("device-inspection-target")
                    if let aid = selected {
                        DisclosureGroup(isExpanded: $showRegistry) { registry(aid).padding(.top, 12) } label: {
                            Label("Advertised transport services", systemImage: "list.bullet.rectangle")
                        }
                        DisclosureGroup(isExpanded: $showGATT) { gatt(aid).padding(.top, 12) } label: {
                            Label("Bluetooth service inventory", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        DisclosureGroup(isExpanded: $showFirmware) { firmwareAccess(aid).padding(.top, 12) } label: {
                            Label("Firmware inspection", systemImage: "cpu")
                        }
                    }
                }
            }.padding(28)
        }.background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
    }

    private func deviceCard(_ aid: AidConnection) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(aid.sideLabel, systemImage: "ear").font(.title3.weight(.semibold))
                    Text(aid.phase.label).font(.caption).foregroundStyle(aid.isConnected ? Color.teal : Color.secondary)
                }
                Spacer()
                AidBatteryView(store: store, aid: aid)
            }
            DeviceDetailsView(store: store, aid: aid)
            Divider()
            Label("Software components", systemImage: "shippingbox").font(.callout.weight(.medium))
            if let metadata = aid.deviceMetadata {
                version("Release package", metadata.releasePackageVersion)
                version("Primary application", metadata.primaryAppVersion)
                version("Maintenance application", metadata.maintenanceAppVersion)
                version("Runtime memory map", metadata.runtimeMemoryMapVersion)
                version("Identification format", metadata.hiidVersion)
                if !metadata.invalidFields.isEmpty {
                    Text("Some reported fields could not be decoded: \(metadata.invalidFields.joined(separator: ", ")).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Read additional information to load the component versions reported by this aid.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let diagnostics = aid.coreDumpInfo {
                Divider()
                Label("Stored diagnostics", systemImage: "doc.text.magnifyingglass").font(.callout.weight(.medium))
                version("Stored crash dumps", String(diagnostics.storedCrashDumps))
                version("Last dump counter", String(diagnostics.lastDumpCounter))
            }
            if let health = aid.batteryHealth {
                Divider()
                DisclosureGroup("Battery diagnostic counters") {
                    VStack(alignment: .leading, spacing: 8) {
                        version("Lifespan counter", String(health.lifespan))
                        version("Lifespan threshold", String(health.lifespanThreshold))
                        version("Average current draw", String(health.slowAverageCurrentDraw))
                        version("Full-charge capacity", String(health.fullChargeCapacity))
                        Text("Raw device values. Units and their conversion into a battery-health percentage have not been established. Remaining time is shown beside the battery level.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 10)
                }.font(.callout)
            }
            HStack(spacing: 10) {
                Button("Read additional information") { store.refreshDeviceMetadata(aid.id) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!aid.isConnected || aid.actionPending || aid.advancedBusy || aid.groupActionPending)
                    .accessibilityLabel("Read \(aid.sideLabel.lowercased()) additional information")
                if aid.advancedBusy { ProgressView().controlSize(.small) }
                Spacer()
                Button { store.refresh(aid.id) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .disabled(!aid.isConnected || aid.actionPending || aid.advancedBusy || aid.groupActionPending)
                    .accessibilityLabel("Refresh \(aid.sideLabel.lowercased()) device information")
            }
            if let status = aid.deviceMetadataStatus { Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
    }

    private func version(_ label: String, _ value: String?) -> some View {
        LabeledContent(label) { Text(value ?? "Not reported").font(.caption.monospaced()).textSelection(.enabled) }
            .font(.caption)
    }

    private func registry(_ aid: AidConnection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The aid advertises these service IDs and versions. Their presence does not establish that every operation is supported by this app or permitted in a consumer session.")
                .font(.caption).foregroundStyle(.secondary)
            if aid.advancedServices.isEmpty {
                Text("Read additional information to load the registry.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(aid.advancedServices.sorted { $0.id < $1.id }, id: \.id) { service in
                    HStack(spacing: 18) {
                        Text(transportServiceName(service.id)).frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(format: "%08X", service.id)).monospaced().foregroundStyle(.secondary)
                        Text("\(service.major).\(service.minor)").monospaced().frame(width: 45, alignment: .trailing)
                        Text(service.isAvailable ? "Advertised" : "Unavailable").foregroundStyle(.secondary).frame(width: 88, alignment: .trailing)
                    }.font(.caption)
                    Divider()
                }
            }
        }
    }

    private func firmwareAccess(_ aid: AidConnection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            version("Firmware version", aid.firmware)
            version("Software version", aid.softwareRevision)
            version("Update service", aid.advancedServices.isEmpty ? "Registry not read"
                    : aid.advancedServices.contains { $0.id == 0x0200000A && $0.isAvailable } ? "Advertised" : "Not reported")
            version("Complete installed-image readout", "Not established")
            Text("The inspected update contracts describe uploading firmware packages. Version and diagnostic getters are available separately; no verified command for downloading the complete installed firmware image has been found in those contracts.")
                .font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: 780, alignment: .leading)
    }

    private func gatt(_ aid: AidConnection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(aid.services.count) services · \(aid.services.reduce(0) { $0 + $1.characteristics.count }) characteristics discovered. Values are read only for recognized controls.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(aid.services) { service in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(service.characteristics) { characteristic in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ReadOnlyInspection.name(service: service.uuid, characteristic: characteristic.uuid) ?? characteristic.uuid)
                                    .font(.callout.weight(.medium)).textSelection(.enabled)
                                Text(characteristic.uuid).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                Text(characteristic.properties).font(.caption).foregroundStyle(.secondary)
                                if let value = characteristic.value { Text(value).font(.caption.monospaced()).textSelection(.enabled) }
                            }
                            Divider()
                        }
                    }.padding(.top, 10)
                } label: {
                    Text("\(bluetoothServiceName(service.uuid)) · \(service.characteristics.count) characteristics").font(.callout)
                }
            }
        }
    }

    private func transportServiceName(_ id: UInt32) -> String {
        switch id {
        case 0x01000007: "Battery telemetry"
        case 0x02000004: "Device identification"
        case 0x02000006: "HIID records"
        case 0x02000009: "Sessions"
        case 0x0200000A: "Firmware updates"
        case 0x0200000C: "Stored diagnostics"
        case 0x0200000D: "Microphone volume"
        case 0x0200000E: "Listening programs"
        case 0x02000010: "Consumer equalizers"
        case 0x02000013: "SpeechBooster controls"
        case 0x02000017: "End-user settings"
        default: "Service"
        }
    }
    private func bluetoothServiceName(_ uuid: String) -> String {
        switch HearingAidDiscovery.normalizedUUID(uuid) {
        case "1800": "Generic Access"
        case "1801": "Generic Attribute"
        case "180A": "Device Information"
        case "180F": "Battery"
        case "1844": "Volume Control"
        case "1850": "Audio Capabilities"
        case "1854": "Hearing Access"
        case "FDF0": "ASHA"
        case HearingAidDiscovery.legacyRemoteService: "Oticon remote control"
        case HearingAidDiscovery.universalTransportService: "Oticon universal transport"
        default: uuid
        }
    }
}
