import SwiftUI

struct AidBatteryView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @ObservedObject var store: BluetoothStore
    let aid: AidConnection
    var compact = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let percentage = aid.battery {
                Label("\(percentage)%", systemImage: batterySymbol(percentage))
                    .font(AppType.callout.monospacedDigit())
                    .foregroundStyle(percentage < 20 ? Color.orange : Color.primary)
                    .accessibilityIdentifier("battery-\(aid.sideLabel.lowercased())-percentage")
            } else { Text(L("Battery —")).foregroundStyle(.secondary) }
            if aid.batteryTelemetry?.chargingDone == true {
                Text(L("Charged")).foregroundStyle(.secondary)
            } else if aid.batteryTelemetry?.isCharging == true {
                Label(L("Charging"), systemImage: "bolt.fill").foregroundStyle(.secondary)
            } else if let seconds = aid.estimatedTimeLeftSeconds, let duration = duration(seconds) {
                Text(compact ? L("About %@ left", duration) : L("Estimated time left: %@", String(describing: duration))).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(L("Estimated time left: %@", String(describing: duration)))
                    .accessibilityIdentifier("battery-\(aid.sideLabel.lowercased())-time")
                    .help(L("Calculated from the hearing aid’s reported remaining charge and measured current draw"))
            } else {
                HStack(spacing: 6) {
                    Text(aid.batteryTelemetry == nil ? L("Time left not loaded") : L("Time estimate unavailable"))
                        .foregroundStyle(.secondary)
                    Button { store.refreshConsumerFeatures(aid.id) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .disabled(!aid.isConnected || aid.actionPending || aid.advancedBusy || aid.groupActionPending)
                        .accessibilityLabel(L("Read %@ battery time", L(aid.sideLabel)))
                }
            }
        }.font(AppType.caption)
    }

    private func batterySymbol(_ percentage: Int) -> String {
        if percentage < 10 { return "battery.0percent" }
        if percentage <= 30 { return "battery.25percent" }
        if percentage <= 60 { return "battery.50percent" }
        if percentage <= 85 { return "battery.75percent" }
        return "battery.100percent"
    }

    private func duration(_ seconds: TimeInterval) -> String? {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max / 60) else { return nil }
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "<1 min" }
        let hours = minutes / 60
        return hours > 0 ? "\(hours) h \(minutes % 60) min" : "\(minutes) min"
    }
}
