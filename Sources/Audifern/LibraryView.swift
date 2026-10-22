import SwiftUI

struct LibraryView: View {
    @ObservedObject var store: BluetoothStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var preferences: AppPreferences
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeading(title: L("Library"), subtitle: L("Your fitted programs and the sounds you save.")) {
                    Button(L("Save current sound"), systemImage: "plus") { navigation.present(.savePreset) }
                        .buttonStyle(.borderedProminent).tint(Brand.controlTint).font(AppType.body)
                }
                Picker(L("Library content"), selection: $navigation.libraryPresets) {
                    Text(L("Fitted programs")).tag(false)
                    Text(L("My presets")).tag(true)
                }.pickerStyle(.segmented).tint(Brand.controlTint).font(AppType.body).frame(maxWidth: 620)
                if navigation.libraryPresets { SoundPresetPanelView(store: store).disabled(store.isDemo) }
                else {
                    if store.orderedConnections.isEmpty {
                        ContentUnavailableView(L("Connect your hearing aids"), systemImage: "ear.badge.waveform")
                    } else { HearingAidControlsView(store: store, mode: .programs) }
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            Label(L("Programs and presets"), systemImage: "info.circle").font(AppType.headline)
                            Text(L("Fitted programs come from your hearing aids. Presets save your own volume and EQ adjustments on this Mac."))
                                .font(AppType.body).foregroundStyle(.secondary)
                            Button(L("Inspect program details…")) { navigation.present(.programDetails) }
                        }
                    }
                }
            }.padding(32).frame(maxWidth: 1150)
        }
    }
}
