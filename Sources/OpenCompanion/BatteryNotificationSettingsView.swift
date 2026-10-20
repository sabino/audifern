import CompanionCore
import SwiftUI

struct BatteryNotificationSettingsView: View {
    @ObservedObject var manager: BatteryNotificationManager

    var body: some View {
        Form {
            Section {
                Toggle("Battery alerts on this Mac", isOn: Binding(
                    get: { manager.configuration.enabled },
                    set: { enabled in Task { await manager.setEnabled(enabled) } }
                ))
                .disabled(manager.loadFailed || manager.isRequestingPermission)
                .accessibilityIdentifier("battery-alerts-enabled")
                HStack(alignment: .top, spacing: 8) {
                    if manager.isRequestingPermission { ProgressView().controlSize(.small) }
                    Label(manager.permission.label,
                          systemImage: manager.permission.canDeliver ? "checkmark.circle" : "bell.badge")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if manager.permission == .denied || manager.permission == .alertsDisabled {
                    Text("Allow Open Companion in System Settings → Notifications, then choose Check permission.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Check permission") { Task { await manager.refreshPermission() } }
                    if manager.configuration.enabled, manager.permission == .notRequested {
                        Button("Allow notifications…") { Task { await manager.setEnabled(true) } }
                    }
                    Spacer()
                    Button("Send test alert") { Task { await manager.sendTestNotification() } }
                        .disabled(!manager.configuration.enabled || !manager.permission.canDeliver || manager.loadFailed)
                }
            } header: {
                Label("Battery notifications", systemImage: "battery.50percent")
            } footer: {
                Text("Alerts use confirmed battery readings while Open Companion is running and receiving updates. No extra Bluetooth polling is added.")
            }

            Section("Alert levels") {
                ForEach(BatteryAlertThreshold.allCases, id: \.self) { threshold in
                    Toggle(threshold.label, isOn: Binding(
                        get: { manager.configuration.thresholds.contains(threshold) },
                        set: { manager.setThreshold(threshold, enabled: $0) }
                    ))
                    .accessibilityIdentifier("battery-alert-threshold-\(threshold.rawValue)")
                }
            }
            .disabled(manager.loadFailed)

            Section {
                ForEach(BatteryAlertSide.allCases, id: \.self) { side in
                    Toggle("\(side.label) device", isOn: Binding(
                        get: { manager.configuration.sides.contains(side) },
                        set: { manager.setSide(side, enabled: $0) }
                    ))
                }
                Toggle("Play a notification sound", isOn: Binding(
                    get: { manager.configuration.playSound }, set: { manager.setPlaySound($0) }
                ))
            } header: {
                Text("Devices and sound")
            } footer: {
                Text("Each device keeps its own alert history. Reconnecting at the same level stays quiet; a measured recharge 5 points above a threshold re-arms it. A first reading above 30% establishes a baseline rather than reporting a missed 50% milestone.")
            }
            .disabled(manager.loadFailed)

            if manager.pendingDeviceCount > 0 {
                Section {
                    HStack {
                        Text("\(manager.pendingDeviceCount) device\(manager.pendingDeviceCount == 1 ? " has" : "s have") an alert awaiting delivery.")
                            .font(.callout)
                        Spacer()
                        Button("Retry pending alerts") { manager.retryPendingAlerts() }
                            .disabled(!manager.configuration.enabled || !manager.permission.canDeliver || manager.loadFailed)
                    }
                }
            }
            if let error = manager.error {
                Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 490, idealWidth: 570, minHeight: 640)
        .padding(8)
    }
}
