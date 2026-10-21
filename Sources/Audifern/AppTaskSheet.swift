import AppKit
import CompanionCore
import SwiftUI

/// One native, attached sheet hosts related tasks. Drilling into another task
/// keeps the same sheet and provides a clear Back action.
struct AppTaskSheet: View {
    @ObservedObject var store: BluetoothStore
    @ObservedObject var workspace: FittingWorkspaceStore
    @ObservedObject var backups: DeviceBackupStore
    let audiograms: AudiogramEditorStore
    let notifications: BatteryNotificationManager
    var availableSize: CGSize? = nil
    // Keep the presentation geometry for the sheet's lifetime. Switching a
    // settings category or opening a child editor must not renegotiate its size.
    @State private var presentationSize: CGSize?
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var presets: SoundPresetStore
    private var destination: AppSheet? { navigation.sheetPath.last ?? navigation.sheet }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                if !navigation.sheetPath.isEmpty {
                    Button { navigation.sheetPath.removeLast() } label: { Label(L("Back"), systemImage: "chevron.left") }
                        .labelStyle(AlignedLabelStyle(iconSize: 15, iconWidth: 18, spacing: 6))
                        .keyboardShortcut("[", modifiers: .command)
                }
                Text(destination?.title ?? Brand.name).font(AppType.callout.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button(L("Done")) { navigation.closeSheet() }.font(AppType.body).keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("close-task-sheet")
            }.frame(height: 38).padding(.horizontal, 24).padding(.vertical, 12)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
        .font(AppType.body).controlSize(.large).tint(Brand.accent)
        .background(Brand.background)
        .frame(width: sheetSize.width, height: sheetSize.height, alignment: .topLeading)
        .fixedSize()
        .onAppear { if presentationSize == nil { presentationSize = sheetSize } }
        .preferredColorScheme(preferences.appearance.colorScheme)
        .environment(\.locale, Localization.shared.formattingLocale)
    }

    private var sheetSize: CGSize {
        presentationSize ?? CGSize(
            width: min(1000, max(840, availableSize?.width ?? (NSScreen.main?.visibleFrame.width ?? 1200) - 100)),
            height: min(920, max(660, availableSize?.height ?? (NSScreen.main?.visibleFrame.height ?? 1000) - 130)))
    }

    @ViewBuilder private var content: some View {
        switch destination {
        case .equalizers:
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PageHeading(title: L("Equalizers"), subtitle: L("Fine-tune your existing listening program.")) { EmptyView() }
                    if store.orderedConnections.isEmpty {
                        ContentUnavailableView(L("Connect your hearing aids"), systemImage: "ear.badge.waveform")
                    } else { HearingAidControlsView(store: store) }
                }.padding(28)
            }
        case .savePreset: SaveSoundPresetView(store: store)
        case .settings: AppSettingsView(notifications: notifications, isDemo: store.isDemo)
        case .about: AboutView()
        case .diagnostics: DeveloperView(store: store)
        case .backups: DeviceBackupsView(store: store, backups: backups)
        case .backupComparison:
            ScrollView { VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: L("Compare backups"), subtitle: L("See what changed between two saved states.")) { EmptyView() }
                BackupComparisonView(backups: backups)
            }.padding(30) }
        case .backupInformation:
            ScrollView { VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: L("About backups"), subtitle: L("A private copy of readable hearing-aid state.")) { EmptyView() }
                Text(L("Audifern saves a consumer-state checkpoint before trying the supported read-only fitting record. Each file is checked after saving and never replaces an older backup."))
                Text(L("These private files can contain device identifiers and fitting data. They stay on this Mac."))
                Text(L("A fitting-system record is only part of a clinical fitting. Any captured end-user settings are listed separately. Live RAM, calibration and firmware are not backed up here, and clinical restore is not available."))
            }.font(AppType.body).padding(30) }
        case .audiograms:
            AudiogramEditorView(store: audiograms, onSaved: { exam in
                presets.linkedAudiogramID = exam.id
                presets.linkedAudiogramLabel = exam.name + (exam.examDate.map { " · \($0)" } ?? "")
            }).disabled(store.isDemo)
        case .savedFitting: FittedConfigurationView(store: store, backups: backups, audiograms: audiograms)
        case .savedSnapshot(let id): FittedConfigurationView(store: store, backups: backups, audiograms: audiograms, initialSelection: id)
        case .fittingReport(let id):
            if let backup = backups.entries.first(where: { $0.id == id })?.backup,
               let report = try? SavedFittingReport(backup: backup) {
                SavedFittingReportView(report: report, close: {
                    if !navigation.sheetPath.isEmpty { navigation.sheetPath.removeLast() } else { navigation.closeSheet() }
                })
            } else { ContentUnavailableView(L("The summary could not be prepared. Your backup has not changed."), systemImage: "doc") }
        case .fittingPlan:
            FittingWorkspaceView(store: store, audiograms: audiograms, draft: $workspace.draft,
                saveDraft: { workspace.save() }, loadDraft: { workspace.reload() },
                persistenceStatus: workspace.status, canLoadDraft: workspace.canLoadDraft && !workspace.loadFailed,
                history: workspace, guided: true, saveAndClose: { workspace.save() })
        case .programDetails: ProgramsView(store: store, detailsOnly: true)
        case .fittingReference:
            FittingWorkspaceView(store: store, audiograms: audiograms, draft: $workspace.draft,
                saveDraft: {}, loadDraft: {}, referenceOnly: true)
        case .device(let id): DeviceExplorerView(store: store, targetID: id)
        case nil: EmptyView()
        }
    }
}
