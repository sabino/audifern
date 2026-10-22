import SwiftUI

struct QuickAccessSettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var help: AppHelpController
    @AppStorage("quickAccessSettingsSection") private var section = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker(L("Quick access"), selection: $section) {
                Text(L("Menu bar")).tag(0)
                Text(L("Widgets and Control Center")).tag(1)
            }.pickerStyle(.segmented).tint(Brand.controlTint).labelsHidden()
            if section == 0 {
                Surface(insets: 18) {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle(L("Show Audifern in the menu bar"), isOn: $preferences.showMenuBar).toggleStyle(.switch)
                            .accessibilityIdentifier("show-menu-bar")
                        Picker(L("Menu-bar label"), selection: $preferences.menuBarLabel) {
                            Text(L("Icon only")).tag("icon")
                            Text(L("Lowest battery")).tag("minimum")
                            Text(L("Both batteries")).tag("both")
                        }
                        Toggle(L("Expanded sound controls"), isOn: $preferences.menuBarExpanded).toggleStyle(.switch)
                    }
                }
                Surface(insets: 18) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L("Show in the menu panel")).font(AppType.headline)
                        HStack(alignment: .top, spacing: 24) {
                            VStack(alignment: .leading, spacing: 16) {
                                Toggle(L("Device images"), isOn: $preferences.menuBarArtwork)
                                Toggle(L("Estimated time remaining"), isOn: $preferences.menuBarTime)
                                Toggle(L("Volume, mute and SpeechBooster"), isOn: $preferences.menuBarSound)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 16) {
                                Toggle(L("Listening program"), isOn: $preferences.menuBarPrograms)
                                Toggle(L("Mac audio output"), isOn: $preferences.menuBarAudio)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.toggleStyle(.checkbox).font(AppType.callout)
                    }
                }
                Text(L("Hiding the menu-bar item keeps Audifern running. Reopen its window from the Dock, or quit the app to stop its connections."))
                    .font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Surface {
                    VStack(alignment: .leading, spacing: 18) {
                        Label(L("Widgets and Control Center"), systemImage: "rectangle.3.group").font(AppType.headline)
                        Toggle(L("Share quick-control state with widgets"), isOn: $preferences.widgetsEnabled).toggleStyle(.switch)
                        Text(L("Shares left/right battery, runtime and supported sound-control state locally. Device identifiers and serial numbers are excluded."))
                            .font(AppType.callout).foregroundStyle(.secondary)
                        Divider()
                        Text(L("Add Audifern using the desktop widget gallery. On macOS 26 or later, choose Edit Controls in Control Center to add individual controls and pin them to the menu bar."))
                            .font(AppType.body)
                        Text(L("Keep Audifern running for quick sound changes. Widget and Control Center actions use current values and expire instead of replaying after reconnecting."))
                            .font(AppType.caption).foregroundStyle(.secondary)
                        Button(L("Learn about quick controls")) { help.openHelp(query: L("Widgets")) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
