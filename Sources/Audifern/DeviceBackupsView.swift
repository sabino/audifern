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
    @State private var showComparison = false

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
                                Text(L("Audifern saves a consumer-state checkpoint before trying the supported read-only fitting record. Each file is checked after saving and never replaces an older backup."))
                                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        HStack(spacing: 12) {
                            Button { capture() } label: {
                                Label(store.deviceBackupBusy ? L("Reading your hearing aids…") : L("Back up readable state"),
                                      systemImage: "arrow.down.doc")
                            }.buttonStyle(.borderedProminent)
                                .disabled(store.connectedCount == 0 || store.deviceBackupBusy || store.programSnapshotBusy || store.isDemo)
                                .accessibilityIdentifier("create-device-backup")
                            if store.deviceBackupBusy { ProgressView().controlSize(.small) }
                            if store.connectedCount == 0 && !store.isDemo {
                                Button(L("Connect hearing aids")) { navigation.page = .devices }.buttonStyle(.bordered)
                            }
                            Spacer(minLength: 0)
                        }
                        if let status = store.deviceBackupStatus { Text(M(status)).font(.caption).foregroundStyle(.secondary) }
                        if let error { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                        Divider()
                        Label(L("These private files can contain device identifiers and fitting data. They stay on this Mac."), systemImage: "lock.shield")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(L("A fitting-system record is only part of a clinical fitting. Any captured end-user settings are listed separately. Live RAM, calibration and firmware are not backed up here, and clinical restore is not available."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Surface {
                    DisclosureGroup(isExpanded: $showComparison) {
                        BackupComparisonView(backups: backups).padding(.top, 18)
                    } label: {
                        Label(L("Compare saved backups"), systemImage: "arrow.left.arrow.right").font(.headline)
                    }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("Saved on this Mac")).font(.title3.weight(.semibold))
                        Text(L("Files are verified when this library loads.")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { backups.reload() } label: { Label(L("Refresh"), systemImage: "arrow.clockwise") }
                        .buttonStyle(.borderless).disabled(store.isDemo || store.deviceBackupBusy)
                    if !backups.entries.isEmpty {
                        Button(L("Show backup folder")) { NSWorkspace.shared.open(backups.folder) }.buttonStyle(.borderless)
                    }
                }
                if let status = backups.status { Text(M(status)).font(.caption).foregroundStyle(.secondary) }
                if backups.failedFileCount > 0 {
                    Label(L("%d backup files need attention; their originals are preserved.", backups.failedFileCount), systemImage: "exclamationmark.shield")
                        .font(.caption).foregroundStyle(.orange)
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
                            .font(.headline)
                        Text(backup.aids.map { L($0.side.rawValue.capitalized) }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(L("Integrity checked"), systemImage: "checkmark.shield.fill").font(.caption.weight(.medium)).foregroundStyle(Brand.accent)
                }
                HStack(spacing: 12) {
                    coverage("Consumer controls", value: L("%d ears captured", backup.consumerControls.aids.count), symbol: "slider.horizontal.3")
                    coverage("Fitting-system record", value: L("%d of %d ears", recordCount, backup.aids.count), symbol: "doc.text.magnifyingglass")
                    coverage("End-user settings", value: L("%d scopes captured", eusCount), symbol: "slider.horizontal.2.square")
                    coverage("Clinical restore", value: L("Not available"), symbol: "stethoscope")
                }
                if backup.acquisitionStage == .partialRead {
                    Label(L("Partial capture · post-read state not verified"), systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                } else if backup.acquisitionStage == .consumerCheckpoint {
                    Text(L("Consumer checkpoint · saved before fitting reads")).font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup(isExpanded: Binding(get: { expandedID == entry.id }, set: { expandedID = $0 ? entry.id : nil })) {
                    VStack(alignment: .leading, spacing: 15) {
                        ForEach(backup.aids, id: \.side) { aid in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L(aid.side.rawValue.capitalized)).font(.callout.weight(.semibold))
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
                            }.font(.caption)
                            Divider()
                        }
                        LabeledContent(L("SHA-256"), value: entry.digest).font(.caption2.monospaced()).textSelection(.enabled)
                        Text(L("The checksum detects accidental file corruption. It does not certify the completeness of the clinical fitting."))
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 15)
                } label: { Text(L("Coverage and device details")).font(.callout) }
            }
        }
    }

    private func coverage(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L(title), systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Brand.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}
