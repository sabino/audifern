import CompanionCore
import SwiftUI

struct BatteryNotificationSettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @ObservedObject var manager: BatteryNotificationManager

    var body: some View {
        Form {
            Section {
                Toggle(L("Battery alerts on this Mac"), isOn: Binding(
                    get: { manager.configuration.enabled },
                    set: { enabled in Task { await manager.setEnabled(enabled) } }
                ))
                .disabled(manager.loadFailed || manager.isRequestingPermission)
                .accessibilityIdentifier("battery-alerts-enabled")
                HStack(alignment: .top, spacing: 8) {
                    if manager.isRequestingPermission { ProgressView().controlSize(.small) }
                    Label(L(manager.permission.label),
                          systemImage: manager.permission.canDeliver ? "checkmark.circle" : "bell.badge")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if manager.permission == .denied || manager.permission == .alertsDisabled {
                    Text(L("Allow Audifern in System Settings → Notifications, then choose Check permission."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(L("Check permission")) { Task { await manager.refreshPermission() } }
                    if manager.configuration.enabled, manager.permission == .notRequested {
                        Button(L("Allow notifications…")) { Task { await manager.setEnabled(true) } }
                    }
                    Spacer()
                    Button(L("Send test alert")) { Task { await manager.sendTestNotification() } }
                        .disabled(!manager.configuration.enabled || !manager.permission.canDeliver || manager.loadFailed)
                }
            } header: {
                Label(L("Battery notifications"), systemImage: "battery.50percent")
            } footer: {
                Text(L("Alerts use confirmed battery readings while Audifern is running and receiving updates. No extra Bluetooth polling is added."))
            }

            Section(L("Alert levels")) {
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
                    Toggle(L("%@ device", String(describing: side.label)), isOn: Binding(
                        get: { manager.configuration.sides.contains(side) },
                        set: { manager.setSide(side, enabled: $0) }
                    ))
                }
                Toggle(L("Play a notification sound"), isOn: Binding(
                    get: { manager.configuration.playSound }, set: { manager.setPlaySound($0) }
                ))
            } header: {
                Text(L("Devices and sound"))
            } footer: {
                Text(L("Each device keeps its own alert history. Reconnecting at the same level stays quiet; a measured recharge 5 points above a threshold re-arms it. A first reading above 30% establishes a baseline rather than reporting a missed 50% milestone."))
            }
            .disabled(manager.loadFailed)

            if manager.pendingDeviceCount > 0 {
                Section {
                    HStack {
                        Text(LP("%d device has an alert awaiting delivery.", "%d devices have an alert awaiting delivery.", count: manager.pendingDeviceCount))
                            .font(.callout)
                        Spacer()
                        Button(L("Retry pending alerts")) { manager.retryPendingAlerts() }
                            .disabled(!manager.configuration.enabled || !manager.permission.canDeliver || manager.loadFailed)
                    }
                }
            }
            if let error = manager.error {
                Section { Label(M(error), systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 490, idealWidth: 570)
        .padding(8)
    }
}
