import AppKit
import CompanionCore
import SwiftUI

struct DeviceBackupsView: View {
    @ObservedObject var store: BluetoothStore
    @ObservedObject var backups: DeviceBackupStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var preferences: AppPreferences
    @State private var error: String?
    @State private var expandedID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: L("Backups"), subtitle: L("Keep a verified local copy of the state your hearing aids expose.")) {
                    ConnectionBadge(store: store)
                }
                Surface {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top, spacing: 18) {
                            Image(systemName: "externaldrive.badge.checkmark").font(.system(size: 34, weight: .light))
                                .foregroundStyle(Brand.accent).frame(width: 60, height: 60)
                                .background(Brand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 17))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L("Your current fitting comes first")).font(.title2.weight(.semibold))
                                Text(L("Save the data your hearing aids expose as a verified private copy."))
                                    .font(AppType.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        HStack(spacing: 12) {
                            Button { capture() } label: {
                                Label(store.deviceBackupBusy ? L("Reading your hearing aids…") : L("Back up readable state"),
                                      systemImage: "arrow.down.doc")
                            }.buttonStyle(.borderedProminent).tint(Brand.controlTint).font(AppType.body)
                                .disabled(store.connectedCount == 0 || store.deviceBackupBusy || store.programSnapshotBusy || store.isDemo)
                                .accessibilityIdentifier("create-device-backup")
                            if store.deviceBackupBusy { ProgressView().controlSize(.small) }
                            if store.connectedCount == 0 && !store.isDemo {
                                Button(L("Connect hearing aids")) { navigation.show(.devices) }.buttonStyle(.bordered).font(AppType.body)
                            }
                            Spacer(minLength: 0)
                        }
                        if let status = store.deviceBackupStatus { Text(M(status)).font(AppType.caption).foregroundStyle(.secondary) }
                        if let error { Label(error, systemImage: "exclamationmark.circle").font(AppType.caption).foregroundStyle(.orange) }
                        Text(L("Clinical restore is not available.")).font(AppType.caption).foregroundStyle(.secondary)
                        Button(L("What is captured?")) { navigation.present(.backupInformation) }
                    }
                }
                Surface {
                    HStack {
                        Label(L("Compare saved backups"), systemImage: "arrow.left.arrow.right").font(AppType.headline)
                        Spacer()
                        Button(L("Compare backups…")) { navigation.present(.backupComparison) }.disabled(backups.entries.count < 2)
                    }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("Saved on this Mac")).font(AppType.subheading.weight(.semibold))
                        Text(L("Files are verified when this library loads.")).font(AppType.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { backups.reload() } label: { Label(L("Refresh"), systemImage: "arrow.clockwise") }
                        .buttonStyle(.borderless).disabled(store.isDemo || store.deviceBackupBusy)
                    if !backups.entries.isEmpty {
                        Button(L("Show backup folder")) { NSWorkspace.shared.open(backups.folder) }.buttonStyle(.borderless)
                    }
                }
                if let status = backups.status { Text(M(status)).font(AppType.caption).foregroundStyle(.secondary) }
                if backups.failedFileCount > 0 {
                    Label(L("%d backup files need attention; their originals are preserved.", backups.failedFileCount), systemImage: "exclamationmark.shield")
                        .font(AppType.caption).foregroundStyle(.orange)
                }
                if backups.entries.isEmpty {
                    Surface {
                        ContentUnavailableView {
                            Label(L("A fresh starting point"), systemImage: "externaldrive")
                        } description: {
                            Text(store.isDemo ? L("Preview mode never reads your backup library or connects to hearing aids.")
                                 : L("Connect your hearing aids, then save your first readable-state backup."))
                        }.frame(minHeight: 180)
                    }
                } else {
                    ForEach(backups.entries) { entry in backupCard(entry) }
                }
            }.padding(30).frame(maxWidth: 1160, alignment: .leading)
        }.accessibilityIdentifier("device-backups")
    }

    private func capture() {
        error = nil
        Task {
            do {
                let result = try await store.captureDeviceBackup { checkpoint in try backups.save(checkpoint) }
                try backups.save(result)
            } catch { self.error = L("Backup stopped. Any completed checkpoint has been preserved.") }
        }
    }

    private func backupCard(_ entry: DeviceBackupStore.Entry) -> some View {
        let backup = entry.backup
        let recordCount = backup.aids.filter { $0.records.contains { $0.key == 1009 } }.count
        let eusCount = backup.aids.reduce(0) { $0 + ($1.endUserSettings?.records.count ?? 0) }
        return Surface {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(backup.capturedAt, format: .dateTime.day().month(.wide).year().hour().minute().second())
                            .font(AppType.headline)
                        Text(backup.aids.map { L($0.side.rawValue.capitalized) }.joined(separator: " · "))
                            .font(AppType.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(L("Integrity checked"), systemImage: "checkmark.shield.fill").font(AppType.caption.weight(.medium)).foregroundStyle(Brand.accent)
                }
                HStack(spacing: 12) {
                    coverage("Consumer controls", value: L("%d ears captured", backup.consumerControls.aids.count), symbol: "slider.horizontal.3")
                    coverage("Fitting-system record", value: L("%d of %d ears", recordCount, backup.aids.count), symbol: "doc.text.magnifyingglass")
                    coverage("End-user settings", value: L("%d scopes captured", eusCount), symbol: "slider.horizontal.2.square")
                }
                if backup.acquisitionStage == .partialRead {
                    Label(L("Partial capture · post-read state not verified"), systemImage: "exclamationmark.circle")
                        .font(AppType.caption).foregroundStyle(.orange)
                } else if backup.acquisitionStage == .consumerCheckpoint {
                    Text(L("Consumer checkpoint · saved before fitting reads")).font(AppType.caption).foregroundStyle(.secondary)
                }
                if recordCount > 0 {
                    Button(L("View saved fitting…")) { navigation.present(.savedSnapshot(entry.id)) }.buttonStyle(.bordered).font(AppType.body)
                }
                ExpandableSection(isExpanded: Binding(get: { expandedID == entry.id }, set: { expandedID = $0 ? entry.id : nil })) {
                    VStack(alignment: .leading, spacing: 15) {
                        ForEach(backup.aids, id: \.side) { aid in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L(aid.side.rawValue.capitalized)).font(AppType.callout.weight(.semibold))
                                LabeledContent(L("Model"), value: aid.identity.model ?? L("Not reported"))
                                LabeledContent(L("Software version"), value: aid.identity.software ?? L("Not reported"))
                                LabeledContent(L("Firmware version"), value: aid.identity.firmware ?? L("Not reported"))
                                LabeledContent(L("Program data"), value: aid.programInventoryComplete ? L("Program inventory captured") : L("Active program only"))
                                if let settings = aid.endUserSettings {
                                    LabeledContent(L("Persisted end-user scopes"), value: settings.isComplete ? L("Advertised inventory captured") : L("Partial coverage"))
                                }
                                if preferences.showIdentifiers, let serial = aid.identity.serialNumber {
                                    LabeledContent(L("Serial number"), value: serial).textSelection(.enabled)
                                }
                                ForEach(aid.notes, id: \.self) { note in Text(M(note)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                            }.font(AppType.caption)
                            Divider()
                        }
                        LabeledContent(L("SHA-256"), value: entry.digest).font(AppType.small.monospaced()).textSelection(.enabled)
                        Text(L("The checksum detects accidental file corruption. It does not certify the completeness of the clinical fitting."))
                            .font(AppType.caption).foregroundStyle(.secondary)
                    }.padding(.top, 15)
                } label: { Text(L("Coverage and device details")).font(AppType.callout) }
            }
        }
    }

    private func coverage(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L(title), systemImage: symbol).font(AppType.caption).foregroundStyle(.secondary)
            Text(value).font(AppType.callout.weight(.medium))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Brand.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}
