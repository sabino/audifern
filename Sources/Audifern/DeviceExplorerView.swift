import CompanionCore
import SwiftUI

/// Device identification and diagnostics stay inside the same application window.
/// Only explicitly implemented, version-bounded getters are offered here.
struct DeviceExplorerView: View {
    @ObservedObject var store: BluetoothStore
    var technicalOnly = false
    var targetID: UUID? = nil
    @EnvironmentObject private var preferences: AppPreferences
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
                if technicalOnly { VStack(alignment: .leading, spacing: 7) {
                    Text(L("Device information")).font(.system(size: 29, weight: .semibold, design: .rounded))
                    Text(L("Versions, battery data and diagnostics reported independently by each hearing aid."))
                        .font(AppType.callout).foregroundStyle(.secondary)
                } }
                if aids.isEmpty {
                    ContentUnavailableView(L("Connect your hearing aids"), systemImage: "ear.badge.waveform",
                                           description: Text(L("Connect them in Hearing aids to read their device information.")))
                        .frame(minHeight: 300)
                } else {
                    if let targetID, let aid = store.connections[targetID] {
                        PageHeading(title: L("%@ hearing aid", L(aid.sideLabel)), subtitle: L("Details reported by this hearing aid.")) { EmptyView() }
                        deviceCard(aid)
                    } else if !technicalOnly { LazyVGrid(columns: [GridItem(.flexible(minimum: 300)), GridItem(.flexible(minimum: 300))], alignment: .leading, spacing: 20) {
                        ForEach(aids) { deviceCard($0) }
                    } }
                    if technicalOnly {
                    Picker(L("Inspect an aid"), selection: Binding(get: { selected?.id }, set: { if let id = $0 { store.select(id) } })) {
                        ForEach(aids) { aid in Text("\(L(aid.sideLabel)) · \(aid.model ?? aid.name)").tag(Optional(aid.id)) }
                    }.frame(maxWidth: 420).accessibilityIdentifier("device-inspection-target")
                    if let aid = selected {
                        ExpandableSection(isExpanded: $showRegistry) { registry(aid).padding(.top, 12) } label: {
                            Label(L("Advertised transport services"), systemImage: "list.bullet.rectangle")
                        }
                        ExpandableSection(isExpanded: $showGATT) { gatt(aid).padding(.top, 12) } label: {
                            Label(L("Bluetooth service inventory"), systemImage: "antenna.radiowaves.left.and.right")
                        }
                        ExpandableSection(isExpanded: $showFirmware) { firmwareAccess(aid).padding(.top, 12) } label: {
                            Label(L("Firmware inspection"), systemImage: "cpu")
                        }
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
                    Label(L(aid.sideLabel), systemImage: "ear").font(AppType.subheading.weight(.semibold))
                    Text(L(aid.phase.label)).font(AppType.caption).foregroundStyle(aid.isConnected ? Color.teal : Color.secondary)
                }
                Spacer()
                AidBatteryView(store: store, aid: aid)
            }
            if let error = aid.error {
                Label(M(DiagnosticPrivacy.redact(error, identifiers: [aid.id.uuidString, aid.name, aid.serialNumber].compactMap { $0 })),
                      systemImage: "exclamationmark.circle").font(AppType.caption).foregroundStyle(.orange)
            }
            if targetID == aid.id { HearingAidArtwork(right: aid.sideLabel == "Right").frame(maxWidth: .infinity).padding(.vertical, 18) }
            DeviceDetailsView(store: store, aid: aid)
            Divider()
            Label(L("Software components"), systemImage: "shippingbox").font(AppType.callout.weight(.medium))
            if let metadata = aid.deviceMetadata {
                version("Release package", metadata.releasePackageVersion)
                version("Primary application", metadata.primaryAppVersion)
                version("Maintenance application", metadata.maintenanceAppVersion)
                version("Runtime memory map", metadata.runtimeMemoryMapVersion)
                version("Identification format", metadata.hiidVersion)
                if !metadata.invalidFields.isEmpty {
                    Text(L("Some reported fields could not be decoded: %@.", String(describing: metadata.invalidFields.joined(separator: ", "))))
                        .font(AppType.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(L("Read additional information to load the component versions reported by this aid."))
                    .font(AppType.caption).foregroundStyle(.secondary)
            }
            if let diagnostics = aid.coreDumpInfo {
                Divider()
                Label(L("Stored diagnostics"), systemImage: "doc.text.magnifyingglass").font(AppType.callout.weight(.medium))
                version(L("Stored crash dumps"), String(diagnostics.storedCrashDumps))
                version(L("Last dump counter"), String(diagnostics.lastDumpCounter))
            }
            if let health = aid.batteryHealth {
                Divider()
                ExpandableSection(L("Battery diagnostic counters")) {
                    VStack(alignment: .leading, spacing: 8) {
                        version("Lifespan counter", String(health.lifespan))
                        version("Lifespan threshold", String(health.lifespanThreshold))
                        version("Average current draw", String(health.slowAverageCurrentDraw))
                        version("Full-charge capacity", String(health.fullChargeCapacity))
                        Text(L("Raw device values. Units and their conversion into a battery-health percentage have not been established. Remaining time is shown beside the battery level."))
                            .font(AppType.caption).foregroundStyle(.secondary)
                    }.padding(.top, 10)
                }.font(AppType.callout)
            }
            HStack(spacing: 10) {
                Button(L("Read additional information")) { store.refreshDeviceMetadata(aid.id) }
                    .buttonStyle(.borderedProminent).tint(Brand.controlTint).font(AppType.body)
                    .disabled(!aid.isConnected || aid.actionPending || aid.advancedBusy || aid.groupActionPending || store.isDemo)
                    .accessibilityLabel(L("Read %@ additional information", L(aid.sideLabel)))
                if aid.advancedBusy { ProgressView().controlSize(.small) }
                Spacer()
                Button { store.refresh(aid.id) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .disabled(!aid.isConnected || aid.actionPending || aid.advancedBusy || aid.groupActionPending || store.isDemo)
                    .accessibilityLabel(L("Refresh %@ device information", L(aid.sideLabel)))
            }
            if let status = aid.deviceMetadataStatus { Text(M(status)).font(AppType.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
    }

    private func version(_ label: String, _ value: String?) -> some View {
        LabeledContent(L(label)) { Text(value ?? L("Not reported")).font(AppType.caption.monospaced()).textSelection(.enabled) }
            .font(AppType.caption)
    }

    private func registry(_ aid: AidConnection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("The aid advertises these service IDs and versions. Their presence does not establish that every operation is supported by this app or permitted in a consumer session."))
                .font(AppType.caption).foregroundStyle(.secondary)
            if aid.advancedServices.isEmpty {
                Text(L("Read additional information to load the registry.")).font(AppType.callout).foregroundStyle(.secondary)
            } else {
                ForEach(aid.advancedServices.sorted { $0.id < $1.id }, id: \.id) { service in
                    HStack(spacing: 18) {
                        Text(L(transportServiceName(service.id))).frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(format: "%08X", service.id)).monospaced().foregroundStyle(.secondary)
                        Text("\(service.major).\(service.minor)").monospaced().frame(width: 45, alignment: .trailing)
                        Text(service.isAvailable ? L("Advertised") : L("Unavailable")).foregroundStyle(.secondary).frame(width: 88, alignment: .trailing)
                    }.font(AppType.caption)
                    Divider()
                }
            }
        }
    }

    private func firmwareAccess(_ aid: AidConnection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            version("Firmware version", aid.firmware)
            version("Software version", aid.softwareRevision)
            version("Update service", aid.advancedServices.isEmpty ? L("Registry not read")
                    : aid.advancedServices.contains { $0.id == 0x0200000A && $0.isAvailable } ? L("Advertised") : L("Not reported"))
            version("Complete installed-image readout", L("Not established"))
            Text(L("The inspected update contracts describe uploading firmware packages. Version and diagnostic getters are available separately; no verified command for downloading the complete installed firmware image has been found in those contracts."))
                .font(AppType.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: 780, alignment: .leading)
    }

    private func gatt(_ aid: AidConnection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("%@ services · %@ characteristics discovered. Values are read only for recognized controls.", String(describing: aid.services.count), String(describing: aid.services.reduce(0) { $0 + $1.characteristics.count })))
                .font(AppType.caption).foregroundStyle(.secondary)
            ForEach(aid.services) { service in
                ExpandableSection {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(service.characteristics) { characteristic in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ReadOnlyInspection.name(service: service.uuid, characteristic: characteristic.uuid) ?? characteristic.uuid)
                                    .font(AppType.callout.weight(.medium)).textSelection(.enabled)
                                Text(characteristic.uuid).font(AppType.small.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                Text(characteristic.properties).font(AppType.caption).foregroundStyle(.secondary)
                                if let value = characteristic.value {
                                    Text(visibleValue(value, service: service.uuid, characteristic: characteristic.uuid))
                                        .font(AppType.caption.monospaced()).textSelection(.enabled)
                                }
                            }
                            Divider()
                        }
                    }.padding(.top, 10)
                } label: {
                    Text(L("%@ · %@ characteristics", String(describing: bluetoothServiceName(service.uuid)), String(describing: service.characteristics.count))).font(AppType.callout)
                }
            }
        }
    }

    private func visibleValue(_ value: String, service: String, characteristic: String) -> String {
        if preferences.showIdentifiers { return value }
        let uuid = HearingAidDiscovery.normalizedUUID(characteristic)
        guard uuid != "2A25", ReadOnlyInspection.name(service: service, characteristic: characteristic) != nil else { return L("Hidden for privacy") }
        let known = store.connections.values.flatMap { [$0.id.uuidString, $0.name, $0.serialNumber ?? ""] }
        return DiagnosticPrivacy.redact(value, identifiers: known)
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
