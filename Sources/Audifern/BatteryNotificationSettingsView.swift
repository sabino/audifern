import CompanionCore
import SwiftUI

struct BatteryNotificationSettingsView: View {
    @ObservedObject var manager: BatteryNotificationManager
    @State private var showingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(L("Battery alerts"), selection: $showingDetails) {
                Text(L("Alert settings")).tag(false)
                Text(L("How alerts work")).tag(true)
            }.pickerStyle(.segmented).tint(Brand.controlTint).labelsHidden()
            if showingDetails {
                Surface(insets: 20) {
                    VStack(alignment: .leading, spacing: 18) {
                        Label(L("How battery alerts work"), systemImage: "info.circle").font(AppType.headline)
                        Text(L("Each device keeps its own alert history. Reconnecting at the same level stays quiet; a measured recharge 5 points above a threshold re-arms it. A first reading above 30% establishes a baseline rather than reporting a missed 50% milestone."))
                        Text(L("Alerts use confirmed battery readings while Audifern is running and receiving updates. No extra Bluetooth polling is added."))
                    }.font(AppType.callout).fixedSize(horizontal: false, vertical: true)
                }
            } else { controls }
        }.font(AppType.body)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Surface(insets: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(L("Battery alerts on this Mac"), isOn: Binding(
                        get: { manager.configuration.enabled },
                        set: { enabled in Task { await manager.setEnabled(enabled) } }))
                        .toggleStyle(.switch).disabled(manager.loadFailed || manager.isRequestingPermission)
                        .accessibilityIdentifier("battery-alerts-enabled")
                    HStack(spacing: 8) {
                        if manager.isRequestingPermission { ProgressView().controlSize(.small) }
                        Label(L(manager.permission.label), systemImage: manager.permission.canDeliver ? "checkmark.circle" : "bell.badge")
                            .font(AppType.caption).foregroundStyle(.secondary)
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
                    }.font(AppType.callout)
                }
            }
            HStack(alignment: .top, spacing: 14) {
                Surface(insets: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Alert levels")).font(AppType.headline)
                        ForEach(BatteryAlertThreshold.allCases, id: \.self) { threshold in
                            Toggle(L(threshold.label), isOn: Binding(
                                get: { manager.configuration.thresholds.contains(threshold) },
                                set: { manager.setThreshold(threshold, enabled: $0) }))
                                .toggleStyle(.switch).frame(minHeight: 30)
                                .accessibilityIdentifier("battery-alert-threshold-\(threshold.rawValue)")
                        }
                    }
                }
                Surface(insets: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Devices and sound")).font(AppType.headline)
                        ForEach(BatteryAlertSide.allCases, id: \.self) { side in
                            Toggle(L("%@ device", L(side.label)), isOn: Binding(
                                get: { manager.configuration.sides.contains(side) },
                                set: { manager.setSide(side, enabled: $0) })).toggleStyle(.switch).frame(minHeight: 30)
                        }
                        Toggle(L("Play a notification sound"), isOn: Binding(
                            get: { manager.configuration.playSound }, set: { manager.setPlaySound($0) }))
                            .toggleStyle(.switch).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.disabled(manager.loadFailed)
            Text(L("Alerts appear while Audifern is running and receiving battery updates."))
                .font(AppType.caption).foregroundStyle(.secondary)
            if manager.pendingDeviceCount > 0 {
                HStack {
                    Text(LP("%d device has an alert awaiting delivery.", "%d devices have an alert awaiting delivery.", count: manager.pendingDeviceCount)).font(AppType.caption)
                    Spacer()
                    Button(L("Retry pending alerts")) { manager.retryPendingAlerts() }
                        .font(AppType.callout).disabled(!manager.configuration.enabled || !manager.permission.canDeliver || manager.loadFailed)
                }
            }
            if let error = manager.error {
                Label(M(error), systemImage: "exclamationmark.circle").font(AppType.caption).foregroundStyle(.orange)
            }
        }
    }
}
