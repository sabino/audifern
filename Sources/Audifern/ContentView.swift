import CompanionCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: BluetoothStore
    let audiogramStore: AudiogramEditorStore
    let notifications: BatteryNotificationManager
    @ObservedObject var fittingWorkspace: FittingWorkspaceStore
    let backups: DeviceBackupStore
    var connectionAutomation: ConnectionAutomation? = nil
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var presets: SoundPresetStore
    @State private var windowContentSize = CGSize(width: 1060, height: 740)

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    BrandMark()
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Brand.name).font(AppType.subheading.weight(.semibold)).foregroundStyle(.primary)
                        Text(L("Your listening space")).font(AppType.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 20)
                VStack(spacing: 6) {
                    ForEach(AppPage.mainPages) { navigationRow($0) }
                }.padding(.horizontal, 12)
                Spacer(minLength: 0)
                SidebarNavigationButton(title: L("Settings"), symbol: "gearshape", selected: navigation.sheet == .settings,
                                        identifier: "navigation-settings") { navigation.present(.settings) }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                Button { navigation.show(.devices) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 18, weight: .medium))
                            .frame(width: 24, height: 26).foregroundStyle(Brand.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.isDemo ? L("Preview mode") : L("Direct Bluetooth")).font(AppType.caption.weight(.medium)).foregroundStyle(.primary)
                            Text(L("Local and private")).font(AppType.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 6).padding(.vertical, 14)
                }.buttonStyle(.plain).padding(10)
            }.navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 280)
        } detail: {
            pageContent.frame(maxWidth: .infinity, maxHeight: .infinity).background(Brand.background)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1060, minHeight: 740)
        .font(AppType.body)
        .controlSize(.large)
        .tint(Brand.accent)
        .preferredColorScheme(preferences.appearance.colorScheme)
        .environment(\.locale, Localization.shared.formattingLocale)
        .navigationTitle(Brand.name)
        .background {
            GeometryReader { geometry in Color.clear.preference(key: AppWindowSizeKey.self, value: geometry.size) }
        }
        .onPreferenceChange(AppWindowSizeKey.self) { size in
            if size.width > 0, size.height > 0, size != windowContentSize { windowContentSize = size }
        }
        .toolbar {
            ToolbarItem(id: "audifern-window-actions", placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button { navigation.show(.devices) } label: {
                        Image(systemName: "dot.radiowaves.left.and.right").frame(width: 28, height: 28)
                    }
                    .help(L("Connection details") + " · " + (store.isDemo ? L("Preview mode") : M(store.bluetoothStatus)))
                    .accessibilityLabel(L("Connection details"))
                    .accessibilityIdentifier("toolbar-connection")
                    Button { navigation.present(.settings) } label: {
                        Image(systemName: "gearshape").frame(width: 28, height: 28)
                    }
                    .help(L("Settings")).accessibilityLabel(L("Settings"))
                    .accessibilityIdentifier("toolbar-settings")
                }.buttonStyle(.borderless).controlSize(.regular).fixedSize()
            }
        }
        .sheet(item: $navigation.sheet, onDismiss: { navigation.sheetPath = [] }) { _ in
            AppTaskSheet(store: store, workspace: fittingWorkspace, backups: backups,
                         audiograms: audiogramStore, notifications: notifications,
                         availableSize: CGSize(width: windowContentSize.width - 40, height: windowContentSize.height - 40), connectionAutomation: connectionAutomation)
        }
    }

    private func navigationRow(_ page: AppPage) -> some View {
        SidebarNavigationButton(title: page.title, symbol: page.symbol, selected: navigation.page == page,
                                identifier: page.accessibilityID) { navigation.show(page) }
    }

    @ViewBuilder private var pageContent: some View {
        switch navigation.page {
        case .hearingAids: ListenView(store: store)
        case .sound:
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PageHeading(title: L("Equalizers"), subtitle: L("Fine-tune your existing listening program.")) { ConnectionBadge(store: store) }
                    if store.orderedConnections.isEmpty { connectPlaceholder }
                    else { HearingAidControlsView(store: store, mode: .sound) }
                }.padding(30).frame(maxWidth: 1100)
            }
        case .presets:
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PageHeading(title: L("Presets"), subtitle: L("Save a sound you like and return to it later.")) { ConnectionBadge(store: store) }
                    Surface { SoundPresetPanelView(store: store).disabled(store.isDemo) }
                }.padding(30).frame(maxWidth: 1100)
            }
        case .programs: LibraryView(store: store)
        case .fitting:
            HearingProfileView(store: store, workspace: fittingWorkspace, backups: backups, audiograms: audiogramStore)
        case .backups: DeviceBackupsView(store: store, backups: backups)
        case .devices: ListenView(store: store)
        case .audiogram:
            AudiogramEditorView(store: audiogramStore, onSaved: { exam in
                presets.linkedAudiogramID = exam.id
                presets.linkedAudiogramLabel = exam.name + (exam.examDate.map { " · \($0)" } ?? "")
            }).disabled(store.isDemo)
        case .settings: AppSettingsView(notifications: notifications, isDemo: store.isDemo, connectionAutomation: connectionAutomation)
        case .developer: DeveloperView(store: store)
        }
    }

    private var connectPlaceholder: some View {
        ContentUnavailableView {
            Label(L("Connect your hearing aids"), systemImage: "ear.badge.waveform")
        } description: { Text(L("Choose your devices to load their available controls.")) }
        actions: { Button(L("Devices")) { navigation.show(.devices) } }.frame(minHeight: 320)
    }
}

private struct AppWindowSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
