import CompanionCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: BluetoothStore
    let audiogramStore: AudiogramEditorStore
    let notifications: BatteryNotificationManager
    @ObservedObject var fittingWorkspace: FittingWorkspaceStore
    let backups: DeviceBackupStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var presets: SoundPresetStore

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) { BrandMark(); Text(Brand.name).font(.title3.weight(.semibold)) }
                    .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 24)
                List {
                    Section(L("Everyday")) { ForEach(AppPage.everydayPages) { navigationRow($0) } }
                    Section(L("Workspace")) { ForEach(AppPage.workspacePages) { navigationRow($0) } }
                }.listStyle(.sidebar)
                Spacer(minLength: 0)
                List { navigationRow(.settings); navigationRow(.developer) }
                    .listStyle(.sidebar).frame(height: 110)
                Button { navigation.page = .devices } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Brand.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.isDemo ? L("Preview mode") : L("Direct Bluetooth")).font(.caption.weight(.medium))
                            Text(L("No account. No telemetry.")).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(14)
                }.buttonStyle(.plain).padding(10)
            }.navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 250)
        } detail: {
            pageContent.frame(maxWidth: .infinity, maxHeight: .infinity).background(Brand.background)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1040, minHeight: 720)
        .tint(Brand.accent)
        .preferredColorScheme(preferences.appearance.colorScheme)
        .environment(\.locale, Localization.shared.formattingLocale)
        .navigationTitle(Brand.name)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { navigation.page = .devices } label: {
                    Label(store.isDemo ? L("Preview mode") : M(store.bluetoothStatus), systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption).foregroundStyle(.secondary)
                }.buttonStyle(.plain).help(L("Connection details"))
            }
        }
    }

    private func navigationRow(_ page: AppPage) -> some View {
        Button { navigation.page = page } label: {
            Label(page.title, systemImage: page.symbol)
                .font(.system(size: 14, weight: navigation.page == page ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).padding(.horizontal, 8)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
            .listRowBackground(navigation.page == page ? Brand.accent.opacity(0.13) : Color.clear)
            .foregroundStyle(navigation.page == page ? Brand.accent : .primary)
            .accessibilityIdentifier(page.accessibilityID)
            .accessibilityAddTraits(navigation.page == page ? [.isSelected] : [])
    }

    @ViewBuilder private var pageContent: some View {
        switch navigation.page {
        case .hearingAids: ListenView(store: store)
        case .sound:
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PageHeading(title: L("Sound"), subtitle: L("Fine-tune your existing listening program.")) { ConnectionBadge(store: store) }
                    if store.orderedConnections.isEmpty { connectPlaceholder }
                    else { HearingAidControlsView(store: store, mode: .sound) }
                }.padding(30).frame(maxWidth: 1100)
            }
        case .programs: ProgramsView(store: store)
        case .fitting:
            FittingPageView(store: store, workspace: fittingWorkspace, backups: backups, audiograms: audiogramStore)
        case .backups: DeviceBackupsView(store: store, backups: backups)
        case .devices: DevicesPageView(store: store)
        case .audiogram:
            AudiogramEditorView(store: audiogramStore, onSaved: { exam in
                presets.linkedAudiogramID = exam.id
                presets.linkedAudiogramLabel = exam.name + (exam.examDate.map { " · \($0)" } ?? "")
            }).disabled(store.isDemo)
        case .settings: AppSettingsView(notifications: notifications, isDemo: store.isDemo)
        case .developer: DeveloperView(store: store)
        }
    }

    private var connectPlaceholder: some View {
        ContentUnavailableView {
            Label(L("Connect your hearing aids"), systemImage: "ear.badge.waveform")
        } description: { Text(L("Choose your devices to load their available controls.")) }
        actions: { Button(L("Devices")) { navigation.page = .devices } }.frame(minHeight: 320)
    }
}
