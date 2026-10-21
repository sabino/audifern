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
                List(selection: $navigation.page) {
                    ForEach(AppPage.mainPages) { navigationRow($0) }
                }.listStyle(.sidebar)
                Spacer(minLength: 0)
                Button { navigation.present(.settings) } label: {
                    Label(L("Settings"), systemImage: "gearshape").font(AppType.body)
                        .labelStyle(AlignedLabelStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4).padding(.vertical, 16)
                }.buttonStyle(.plain).padding(.horizontal, 12)
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
            }.navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 280)
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
            ToolbarItem(placement: .automatic) {
                Button { navigation.show(.devices) } label: {
                    Label(store.isDemo ? L("Preview mode") : M(store.bluetoothStatus), systemImage: "dot.radiowaves.left.and.right")
                        .font(AppType.caption).foregroundStyle(.secondary)
                }.buttonStyle(.plain).help(L("Connection details"))
            }
            ToolbarItem(placement: .automatic) {
                Button { navigation.present(.settings) } label: { Label(L("Settings"), systemImage: "gearshape") }
                    .help(L("Settings"))
            }
        }
        .sheet(item: $navigation.sheet, onDismiss: { navigation.sheetPath = [] }) { _ in
            AppTaskSheet(store: store, workspace: fittingWorkspace, backups: backups,
                         audiograms: audiogramStore, notifications: notifications,
                         availableSize: CGSize(width: windowContentSize.width - 40, height: windowContentSize.height - 40), connectionAutomation: connectionAutomation)
        }
    }

    private func navigationRow(_ page: AppPage) -> some View {
        Label(page.title, systemImage: page.symbol)
            .labelStyle(AlignedLabelStyle())
            .font(.system(size: 17, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .contentShape(Rectangle())
            .tag(page)
            .accessibilityIdentifier(page.accessibilityID)
            .accessibilityAddTraits(navigation.page == page ? [.isSelected] : [])
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
        case .devices: DevicesPageView(store: store)
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
