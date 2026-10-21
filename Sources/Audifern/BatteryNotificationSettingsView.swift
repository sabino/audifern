import CompanionCore
import SwiftUI

struct BatteryNotificationSettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @ObservedObject var manager: BatteryNotificationManager
    @State private var showingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                Toggle(L("Battery alerts on this Mac"), isOn: Binding(
                    get: { manager.configuration.enabled },
                    set: { enabled in Task { await manager.setEnabled(enabled) } }
                ))
                .toggleStyle(.switch).disabled(manager.loadFailed || manager.isRequestingPermission)
                .accessibilityIdentifier("battery-alerts-enabled")
                HStack(alignment: .top, spacing: 8) {
                    if manager.isRequestingPermission { ProgressView().controlSize(.small) }
                    Label(L(manager.permission.label),
                          systemImage: manager.permission.canDeliver ? "checkmark.circle" : "bell.badge")
                        .font(AppType.callout).foregroundStyle(.secondary)
                }
                if manager.permission == .denied || manager.permission == .alertsDisabled {
                    Text(L("Allow Audifern in System Settings → Notifications, then choose Check permission."))
                        .font(AppType.caption).foregroundStyle(.secondary)
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
                }
            } label: {
                Label(L("Battery notifications"), systemImage: "battery.50percent")
            }
            Text(L("Alerts appear while Audifern is running and receiving battery updates.")).font(AppType.caption).foregroundStyle(.secondary)

            SettingsCard(L("Alert levels")) {
                VStack(alignment: .leading, spacing: 0) {
                ForEach(BatteryAlertThreshold.allCases, id: \.self) { threshold in
                    Toggle(threshold.label, isOn: Binding(
                        get: { manager.configuration.thresholds.contains(threshold) },
                        set: { manager.setThreshold(threshold, enabled: $0) }
                    ))
                    .toggleStyle(.switch).padding(.vertical, 10)
                    .accessibilityIdentifier("battery-alert-threshold-\(threshold.rawValue)")
                }
                }
            }
            .disabled(manager.loadFailed)

            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                ForEach(BatteryAlertSide.allCases, id: \.self) { side in
                    Toggle(L("%@ device", String(describing: side.label)), isOn: Binding(
                        get: { manager.configuration.sides.contains(side) },
                        set: { manager.setSide(side, enabled: $0) }
                    )).toggleStyle(.switch)
                }
                Toggle(L("Play a notification sound"), isOn: Binding(
                    get: { manager.configuration.playSound }, set: { manager.setPlaySound($0) }
                )).toggleStyle(.switch)
                }
            } label: {
                Text(L("Devices and sound"))
            }
            .disabled(manager.loadFailed)

            if manager.pendingDeviceCount > 0 {
                SettingsCard {
                    HStack {
                        Text(LP("%d device has an alert awaiting delivery.", "%d devices have an alert awaiting delivery.", count: manager.pendingDeviceCount))
                            .font(AppType.callout)
                        Spacer()
                        Button(L("Retry pending alerts")) { manager.retryPendingAlerts() }
                            .disabled(!manager.configuration.enabled || !manager.permission.canDeliver || manager.loadFailed)
                    }
                }
            }
            if let error = manager.error {
                SettingsCard { Label(M(error), systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
            }
            ExpandableSection(L("How battery alerts work"), isExpanded: $showingDetails) {
                Text(L("Each device keeps its own alert history. Reconnecting at the same level stays quiet; a measured recharge 5 points above a threshold re-arms it. A first reading above 30% establishes a baseline rather than reporting a missed 50% milestone."))
                    .font(AppType.caption).foregroundStyle(.secondary)
                Text(L("Alerts use confirmed battery readings while Audifern is running and receiving updates. No extra Bluetooth polling is added."))
                    .font(AppType.caption).foregroundStyle(.secondary)
            }
        }.font(AppType.body)
    }
}
