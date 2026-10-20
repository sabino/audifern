import SwiftUI

struct DeviceDetailsView: View {
    @ObservedObject var store: BluetoothStore
    let aid: AidConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Device information", systemImage: "info.circle").font(.callout.weight(.medium))
            field("Manufacturer", value: aid.manufacturer, identifier: "manufacturer")
            field("Model", value: aid.model, identifier: "model")
            field("Firmware", value: aid.firmware, identifier: "firmware")
            field("Software", value: aid.softwareRevision, identifier: "software")
                .help(aid.softwareRevisionSource.map { "Software revision reported by \($0)" } ?? "Software revision has not been reported")
            field("Hardware", value: aid.hardwareRevision, identifier: "hardware")
                .help(aid.hardwareRevisionSource.map { "Hardware revision reported by \($0)" } ?? "Hardware revision has not been reported")
            field("Serial number", value: aid.serialNumber, identifier: "serial")
            if aid.serialNumber == nil {
                Button("Read device details") { store.refreshDeviceMetadata(aid.id) }
                    .buttonStyle(.borderless)
                    .disabled(!aid.isConnected || aid.actionPending || aid.advancedBusy || aid.groupActionPending)
                    .accessibilityLabel("Read \(aid.sideLabel.lowercased()) device details")
            }
        }.font(.caption).textSelection(.enabled)
    }

    private func field(_ label: String, value: String?, identifier: String) -> some View {
        LabeledContent(label) {
            Text(value ?? "—").monospaced().foregroundStyle(value == nil ? Color.secondary : Color.primary)
                .accessibilityIdentifier("device-\(aid.sideLabel.lowercased())-\(identifier)")
        }
    }
}
