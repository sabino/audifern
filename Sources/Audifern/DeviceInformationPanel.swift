import CompanionCore
import SwiftUI

/// One fixed-size attached panel; related information uses pages rather than
/// stacking artwork, identification and diagnostics into a long scroll view.
struct DeviceInformationPanel: View {
    enum Section: String, CaseIterable { case overview, software, diagnostics
        var title: String {
            switch self {
            case .overview: L("Overview")
            case .software: L("Software components")
            case .diagnostics: L("Diagnostics")
            }
        }
    }
    @ObservedObject var store: BluetoothStore
    let id: UUID
    @State var section: Section = .overview
    @EnvironmentObject private var navigation: AppNavigation
    private var aid: AidConnection? { store.connections[id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let aid {
                HStack(spacing: 28) {
                    HearingAidArtwork(right: aid.sideLabel == "Right", size: 0.5)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("%@ hearing aid", L(aid.sideLabel))).font(.system(size: 27, weight: .semibold))
                        Text(aid.model ?? L("Hearing aid")).font(AppType.body).foregroundStyle(.secondary)
                        Label(L(aid.phase.label), systemImage: aid.isConnected ? "checkmark.circle.fill" : "circle")
                            .font(AppType.caption).foregroundStyle(aid.isConnected ? Brand.accent : .secondary)
                    }
                    Spacer(minLength: 0)
                    AidBatteryView(store: store, aid: aid)
                }.frame(height: 92)
                Picker(L("Device information"), selection: $section) {
                    ForEach(Section.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("device-information-section")
                Surface(insets: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        switch section {
                        case .overview: DeviceDetailsView(store: store, aid: aid)
                        case .software: software(aid)
                        case .diagnostics: diagnostics(aid)
                        }
                        Spacer(minLength: 0)
                    }.frame(maxHeight: .infinity, alignment: .topLeading)
                }.frame(maxHeight: .infinity)
                HStack(spacing: 12) {
                    Button(L("Read additional information")) { store.refreshDeviceMetadata(id) }
                        .buttonStyle(.borderedProminent).font(AppType.caption)
                        .disabled(!aid.isConnected || aid.actionPending || aid.advancedBusy || aid.groupActionPending || store.isDemo)
                        .accessibilityLabel(L("Read %@ additional information", L(aid.sideLabel)))
                    if aid.advancedBusy { ProgressView().controlSize(.small) }
                    Spacer(minLength: 0)
                    Button(L("Diagnostics…")) { navigation.present(.diagnostics) }
                        .font(AppType.caption).buttonStyle(.bordered)
                }
                Text(aid.deviceMetadataStatus.map(M) ?? L("Details reported by this hearing aid."))
                    .font(AppType.caption).foregroundStyle(.secondary).lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .leading)
                    .help(aid.deviceMetadataStatus.map(M) ?? "")
            } else {
                ContentUnavailableView(L("Connect your hearing aids"), systemImage: "ear.badge.waveform")
            }
        }.padding(20).accessibilityIdentifier("device-information-panel")
    }
    private func software(_ aid: AidConnection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("Software components"), systemImage: "shippingbox").font(AppType.headline)
            field(L("Release package"), aid.deviceMetadata?.releasePackageVersion)
            field(L("Primary application"), aid.deviceMetadata?.primaryAppVersion)
            field(L("Maintenance application"), aid.deviceMetadata?.maintenanceAppVersion)
            field(L("Runtime memory map"), aid.deviceMetadata?.runtimeMemoryMapVersion)
            field(L("Identification format"), aid.deviceMetadata?.hiidVersion)
            if let metadata = aid.deviceMetadata, !metadata.invalidFields.isEmpty {
                Text(L("Some reported fields could not be decoded: %@.", metadata.invalidFields.joined(separator: ", ")))
                    .font(AppType.caption).foregroundStyle(.secondary)
            } else if aid.deviceMetadata == nil {
                Text(L("Read additional information to load the component versions reported by this aid."))
                    .font(AppType.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func diagnostics(_ aid: AidConnection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("Stored diagnostics"), systemImage: "doc.text.magnifyingglass").font(AppType.headline)
            field(L("Stored crash dumps"), aid.coreDumpInfo.map { String($0.storedCrashDumps) })
            field(L("Last dump counter"), aid.coreDumpInfo.map { String($0.lastDumpCounter) })
            Divider()
            Text(L("Battery diagnostic counters")).font(AppType.callout.weight(.medium))
            field(L("Lifespan counter"), aid.batteryHealth.map { String($0.lifespan) })
            field(L("Lifespan threshold"), aid.batteryHealth.map { String($0.lifespanThreshold) })
            field(L("Average current draw"), aid.batteryHealth.map { String($0.slowAverageCurrentDraw) })
            field(L("Full-charge capacity"), aid.batteryHealth.map { String($0.fullChargeCapacity) })
            Text(L("Raw device values. Units and their conversion into a battery-health percentage have not been established. Remaining time is shown beside the battery level."))
                .font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func field(_ label: String, _ value: String?) -> some View {
        HStack(spacing: 20) {
            Text(L(label)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value ?? L("Not reported")).font(AppType.caption.monospaced()).textSelection(.enabled)
        }.font(AppType.callout)
    }
}
