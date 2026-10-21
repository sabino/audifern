import SwiftUI

struct DeviceDetailsView: View {
    @ObservedObject var store: BluetoothStore
    @EnvironmentObject private var preferences: AppPreferences
    let aid: AidConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("Device information"), systemImage: "info.circle").font(AppType.callout.weight(.medium))
            field(L("Manufacturer"), value: aid.manufacturer, identifier: "manufacturer")
            field(L("Model"), value: aid.model, identifier: "model")
            field(L("Firmware"), value: aid.firmware, identifier: "firmware")
            field("Software", value: aid.softwareRevision, identifier: "software")
                .help(aid.softwareRevisionSource.map { "Software revision reported by \($0)" } ?? "Software revision has not been reported")
            field("Hardware", value: aid.hardwareRevision, identifier: "hardware")
                .help(aid.hardwareRevisionSource.map { "Hardware revision reported by \($0)" } ?? "Hardware revision has not been reported")
            field("Serial number", value: aid.serialNumber.map { preferences.showIdentifiers ? $0 : "••••••••" }, identifier: "serial")
            if aid.serialNumber != nil, !preferences.showIdentifiers {
                Text(L("Hidden for privacy. Change this in Settings.")).font(AppType.small).foregroundStyle(.secondary)
            }
            if aid.serialNumber == nil {
                Button(L("Read device details")) { store.refreshDeviceMetadata(aid.id) }
                    .buttonStyle(.borderless)
                    .disabled(!aid.isConnected || aid.actionPending || aid.advancedBusy || aid.groupActionPending || store.isDemo)
                    .accessibilityLabel(L("Read %@ device details", L(aid.sideLabel)))
            }
        }.font(AppType.callout).textSelection(.enabled)
    }

    private func field(_ label: String, value: String?, identifier: String) -> some View {
        HStack(spacing: 20) {
            Text(L(label)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value ?? "—").monospaced().foregroundStyle(value == nil ? Color.secondary : Color.primary)
                .accessibilityIdentifier("device-\(aid.sideLabel.lowercased())-\(identifier)")
        }
    }
}
