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
            field("Serial number", value: aid.serialNumber, identifier: "serial")
            if aid.serialNumber == nil {
                Button("Read device details") { store.refreshConsumerFeatures(aid.id) }
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
