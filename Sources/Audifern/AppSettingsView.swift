import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var notifications: BatteryNotificationManager
    var isDemo = false
    @EnvironmentObject private var preferences: AppPreferences
    @State private var showNotifications = true
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("Development") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: L("Settings"), subtitle: L("Make Audifern feel at home on your Mac.")) {
                    Text(Brand.name + " " + version).font(.caption).foregroundStyle(.secondary)
                }
                Surface {
                    VStack(alignment: .leading, spacing: 20) {
                        Label(L("Appearance"), systemImage: "circle.lefthalf.filled").font(.headline)
                        Picker(L("Appearance"), selection: $preferences.appearance) {
                            ForEach(AppAppearance.allCases) { item in Text(item.title).tag(item) }
                        }.pickerStyle(.segmented).frame(maxWidth: 420).accessibilityIdentifier("appearance-choice")
                        Text(L("System follows macOS automatically. Your sound settings do not change."))
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        LabeledContent {
                            Picker(L("Language"), selection: $preferences.language) {
                                ForEach(AppLanguage.allCases) { item in Text(item.displayName).tag(item) }
                            }.labelsHidden().frame(maxWidth: 260).accessibilityIdentifier("language-choice")
                        } label: { Label(L("Language"), systemImage: "globe") }
                        Text(L("Device program names stay exactly as reported by the hearing aids."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(L("Privacy"), systemImage: "hand.raised").font(.headline)
                        Toggle(L("Show device identifiers on this Mac"), isOn: $preferences.showIdentifiers)
                            .toggleStyle(.switch).accessibilityIdentifier("show-device-identifiers")
                        Text(L("Serial numbers and private connection identifiers are hidden by default. Diagnostic exports stay redacted even when this is enabled."))
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Label(L("No account. No telemetry. Direct Bluetooth."), systemImage: "checkmark.shield")
                            .font(.callout).foregroundStyle(Brand.accent)
                        Text(L("Audiograms and sound presets stay on this Mac. Exporting a file is always an explicit action."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                DisclosureGroup(L("Battery notifications"), isExpanded: $showNotifications) {
                    BatteryNotificationSettingsView(manager: notifications).padding(.top, 12).disabled(isDemo)
                }.font(.headline)
                Text(L("Closing the window keeps your Bluetooth connections and battery monitoring running in the menu bar. Quit Audifern to stop them."))
                    .font(.callout).foregroundStyle(.secondary)
                Surface {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L("Open source"), systemImage: "chevron.left.forwardslash.chevron.right").font(.headline)
                        Text(L("An independent project, licensed under GNU GPLv3. Not affiliated with or endorsed by the hearing-aid manufacturer."))
                            .font(.callout).foregroundStyle(.secondary)
                        Text(L("Advanced controls require a compatible credential provisioned locally. No vendor credential, SDK or firmware is included."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(30).frame(maxWidth: 920)
        }
    }
}
