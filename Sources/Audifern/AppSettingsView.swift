import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var notifications: BatteryNotificationManager
    var isDemo = false
    var connectionAutomation: ConnectionAutomation? = nil
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var navigation: AppNavigation
    @AppStorage("settingsSection") private var section = "general"
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("Development") }
    private var title: String {
        switch section {
        case "battery": L("Battery alerts")
        case "privacy": L("Privacy")
        case "diagnostics": L("Diagnostics")
        case "about": L("About Audifern")
        case "connections": L("Connections")
        case "quickAccess": L("Quick access")
        default: L("General")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                category("general", title: L("General"), symbol: "gearshape")
                category("connections", title: L("Connections"), symbol: "antenna.radiowaves.left.and.right")
                category("quickAccess", title: L("Quick access"), symbol: "menubar.rectangle")
                category("battery", title: L("Battery alerts"), symbol: "battery.75percent")
                category("privacy", title: L("Privacy"), symbol: "lock.shield")
                category("diagnostics", title: L("Diagnostics"), symbol: "waveform.path.ecg")
                category("about", title: L("About"), symbol: "info.circle")
                Spacer()
                Text(Brand.name + " " + version).font(AppType.caption).foregroundStyle(.secondary)
            }.padding(14).frame(width: 214)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .background(Brand.surface.opacity(0.65))
            Divider()
            if section == "about" { AboutView() }
            else {
                VStack(alignment: .leading, spacing: 18) {
                    Text(title).font(.system(size: 30, weight: .bold))
                    switch section {
                    case "connections":
                        if let connectionAutomation { ConnectionSettingsView(automation: connectionAutomation) }
                    case "battery": BatteryNotificationSettingsView(manager: notifications).disabled(isDemo)
                    case "privacy": privacy
                    case "diagnostics": diagnostics
                    case "quickAccess": QuickAccessSettingsView()
                    default: general
                    }
                    Spacer(minLength: 0)
                }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func category(_ id: String, title: String, symbol: String) -> some View {
        SidebarNavigationButton(title: title, symbol: symbol, selected: section == id,
                                identifier: "settings-\(id)") { section = id }
    }
    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            Surface(insets: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Label(L("Appearance"), systemImage: "circle.lefthalf.filled").font(AppType.headline)
                    Picker(L("Appearance"), selection: $preferences.appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).tint(Brand.controlTint).accessibilityIdentifier("appearance-choice")
                    Text(L("System follows macOS automatically. Your sound settings do not change."))
                        .font(AppType.caption).foregroundStyle(.secondary)
                    Divider()
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(L("Language"), systemImage: "globe").font(AppType.headline)
                            Text(L("Device program names stay exactly as reported by the hearing aids."))
                                .font(AppType.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Picker(L("Language"), selection: $preferences.language) {
                            ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                        }.labelsHidden().frame(width: 230).accessibilityIdentifier("language-choice")
                    }
                }
            }
            Text(L("Closing the window keeps your Bluetooth connections and battery monitoring running in the menu bar. Quit Audifern to stop them."))
                .font(AppType.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Surface(insets: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(L("Open source"), systemImage: "chevron.left.forwardslash.chevron.right").font(AppType.headline)
                    Text(L("An independent project, licensed under GNU GPLv3. Not affiliated with or endorsed by the hearing-aid manufacturer."))
                        .font(AppType.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private var privacy: some View {
        Surface {
            VStack(alignment: .leading, spacing: 22) {
                Toggle(L("Show device identifiers on this Mac"), isOn: $preferences.showIdentifiers)
                    .toggleStyle(.switch).accessibilityIdentifier("show-device-identifiers")
                Text(L("Serial numbers and private connection identifiers are hidden by default. Diagnostic exports stay redacted even when this is enabled."))
                    .font(AppType.callout).foregroundStyle(.secondary)
                Divider()
                Label(L("No account. No telemetry. Direct Bluetooth."), systemImage: "checkmark.shield")
                    .font(AppType.body).foregroundStyle(Brand.accent)
                Text(L("Audiograms and sound presets stay on this Mac. Exporting a file is always an explicit action."))
                    .font(AppType.callout).foregroundStyle(.secondary)
            }
        }
    }
    private var diagnostics: some View {
        Surface {
            VStack(alignment: .leading, spacing: 20) {
                Label(L("Connection and device diagnostics"), systemImage: "waveform.path.ecg").font(AppType.headline)
                Text(L("Inspect connection status, supported services and redacted logs when you need them."))
                    .font(AppType.body).foregroundStyle(.secondary)
                Button(L("Open diagnostics…")) { navigation.present(.diagnostics) }.buttonStyle(.borderedProminent).tint(Brand.controlTint).font(AppType.body)
                Text(L("Advanced controls require a compatible credential provisioned locally. No vendor credential, SDK or firmware is included."))
                    .font(AppType.caption).foregroundStyle(.secondary)
            }
        }
    }
}
