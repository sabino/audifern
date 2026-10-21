import CompanionCore
import SwiftUI

/// Displays only decoded state from a verified private archive. Opening this
/// page does not read Bluetooth, select programs or change sound processing.
struct FittedConfigurationView: View {
    @ObservedObject var store: BluetoothStore
    @ObservedObject var backups: DeviceBackupStore
    let audiograms: AudiogramEditorStore?
    @EnvironmentObject private var navigation: AppNavigation
    @State private var selectedID: UUID?
    @State private var preferredSide: ConsumerProgramSnapshot.Side?
    @State private var selectedSlot = 0
    @State private var showParameters = false
    @State private var showAccessoryPrograms = false

    init(store: BluetoothStore, backups: DeviceBackupStore, audiograms: AudiogramEditorStore? = nil,
         showParameters: Bool = false) {
        self.store = store; self.backups = backups; self.audiograms = audiograms
        _showParameters = State(initialValue: showParameters)
    }
    private var available: [DeviceBackupStore.Entry] {
        backups.entries.filter { $0.backup.aids.contains { $0.records.contains { $0.key == 1009 } } }
    }
    private var selected: DeviceBackupStore.Entry? { available.first { $0.id == selectedID } ?? available.first }
    private var side: ConsumerProgramSnapshot.Side {
        if let preferredSide, selected?.backup.aids.contains(where: { $0.side == preferredSide }) == true { return preferredSide }
        return selected?.backup.aids.first(where: { $0.records.contains { $0.key == OticonFittingRead.recordKey } })?.side
            ?? selected?.backup.aids.first?.side ?? .left
    }
    private var aid: DeviceBackup.Aid? { selected?.backup.aids.first { $0.side == side } }
    private var missingRecord: Bool { aid?.records.contains { $0.key == OticonFittingRead.recordKey } != true }
    private var decoded: OticonFittedConfiguration.Snapshot? { aid.flatMap { try? SavedFitting.decode($0) } }
    private var program: OticonFittedConfiguration.Program? {
        decoded?.userPrograms.first { $0.slot.rawValue == selectedSlot } ?? decoded?.userPrograms.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: L("Your fitted sound"), subtitle: L("Explore the fitting saved in your hearing aids, with a clear record of when it was read.")) {
                    Button { navigation.page = .backups } label: { Label(L("Read a fresh backup"), systemImage: "arrow.down.doc") }
                        .buttonStyle(.bordered)
                }
                if let selected {
                    sourceBar(selected)
                    if let decoded {
                        overview(decoded)
                        programCards(decoded)
                        if let program { processing(program) }
                        if let program, let controls = try? OticonSavedControls.decode(decoded) {
                            SavedSoundControlsView(controls: controls, slot: program.slot)
                        }
                        if let gain = program?.gain { parameters(gain) }
                        if let aid, let business = try? SavedFitting.businessData(aid) {
                            StoredFittingMetadataView(snapshot: business, backup: selected.backup, audiograms: audiograms)
                                .id("\(selected.id)-\(side.rawValue)")
                        }
                        accessories(decoded)
                        if let acoustics = try? OticonSavedAcoustics.decode(decoded) { SavedAcousticsView(labels: acoustics) }
                        if let rawIdentification = aid?.identification,
                           let hardware = try? OticonHardwareProfile.decodeHiid(rawIdentification) {
                            SavedHardwareView(profile: hardware)
                        }
                        if let aid, let settings = aid.endUserSettings {
                            if let preferences = try? OticonSavedPreferences.decode(settings,
                                identity: decoded.identity, services: aid.services) {
                                SavedPreferencesView(preferences: preferences)
                            } else {
                                Surface {
                                    Label(L("Saved button and notification details are unavailable for this capture. The raw settings remain in the backup."),
                                          systemImage: "info.circle")
                                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    } else {
                        Surface {
                            ContentUnavailableView {
                                Label(missingRecord ? L("No fitting record for this ear") : L("Your data is safely preserved"), systemImage: "externaldrive.badge.checkmark")
                            } description: {
                                Text(missingRecord
                                     ? L("This capture has no fitting-system record for the selected ear. Choose another saved ear or read a fresh backup.")
                                     : L("This record does not match the fitted-parameter decoder supported by this version. Its raw backup is kept intact."))
                            }.frame(minHeight: 230)
                        }
                    }
                } else {
                    Surface {
                        ContentUnavailableView {
                            Label(L("Discover your fitted programs"), systemImage: "waveform.path")
                        } description: {
                            Text(L("Create a readable-state backup to explore your saved program structure, adaptation and fitted processing. This page never changes the hearing aids."))
                        } actions: {
                            Button(L("Open backups")) { navigation.page = .backups }.buttonStyle(.borderedProminent)
                        }.frame(minHeight: 330)
                    }
                }
            }.padding(30).frame(maxWidth: 1160, alignment: .leading)
        }.accessibilityIdentifier("saved-fitting")
            .onChange(of: side) { _, _ in selectedSlot = 0 }
            .onChange(of: selected?.id) { _, _ in preferredSide = nil; selectedSlot = 0 }
    }

    private func sourceBar(_ entry: DeviceBackupStore.Entry) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label(L("Saved state · read-only"), systemImage: "checkmark.shield").font(.caption.weight(.medium)).foregroundStyle(Brand.accent)
                Text(entry.backup.capturedAt, format: .dateTime.day().month(.wide).year().hour().minute())
                    .font(.callout.weight(.medium))
                if entry.backup.acquisitionStage == .partialRead {
                    Text(L("Partial capture · post-read state not verified")).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            Picker(L("Backup"), selection: Binding(get: { entry.id }, set: { selectedID = $0 })) {
                ForEach(available) { item in
                    Text(item.backup.capturedAt, format: .dateTime.month().day().hour().minute().second()).tag(item.id)
                }
            }.labelsHidden().frame(maxWidth: 200)
            Picker(L("Hearing aid"), selection: Binding(get: { side }, set: { preferredSide = $0 })) {
                ForEach(entry.backup.aids, id: \.side) { aid in Text(L(aid.side.rawValue.capitalized)).tag(aid.side) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 170)
        }.padding(18).background(Brand.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
    }

    private func overview(_ fitting: OticonFittedConfiguration.Snapshot) -> some View {
        HStack(alignment: .top, spacing: 20) {
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    Label(L("Listening programs"), systemImage: "square.grid.2x2").font(.headline)
                    Text(LP("%ld fitted listening program", "%ld fitted listening programs", count: fitting.userPrograms.count))
                        .font(.title2.weight(.semibold))
                    Text(L("Accessory and automatic programs are listed separately below."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    Label(L("Adaptation"), systemImage: "leaf").font(.headline)
                    Text(L("Step %@", fitting.adaptation.currentStep.formatted(.number.precision(.fractionLength(0...2)))))
                        .font(.title2.weight(.semibold))
                    Text(adaptationMode(fitting.adaptation.mode)).font(.callout).foregroundStyle(.secondary)
                    Text(L("Start %d · final %d", fitting.adaptation.startStep, fitting.adaptation.endStep))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func programCards(_ fitting: OticonFittedConfiguration.Snapshot) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Explore a program")).font(.headline)
                Text(L("This selection only changes the inspector. Use Programs to change what you hear."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(fitting.userPrograms, id: \.slot) { item in
                        Button { selectedSlot = item.slot.rawValue } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack { Text(item.slot.title).font(.caption.weight(.semibold)); Spacer(); Image(systemName: "waveform") }
                                Text(item.displayName).font(.headline).lineLimit(2)
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(program?.slot == item.slot ? Brand.accent.opacity(0.12) : Brand.background.opacity(0.5),
                                            in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(program?.slot == item.slot ? Brand.accent.opacity(0.5) : Color.primary.opacity(0.08)))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func processing(_ program: OticonFittedConfiguration.Program) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 18) {
                Label(L("Fitted processing"), systemImage: "waveform.path").font(.headline)
                HStack(alignment: .top, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Noise management")).font(.callout.weight(.medium))
                        reportedToggle(program.noiseManagement?.isEnabled)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Feedback management")).font(.callout.weight(.medium))
                        reportedToggle(program.feedback?.isEnabled)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.fixedSize(horizontal: false, vertical: true)
                Text(L("These are fitted settings read from the archive. Everyday SpeechBooster and equalizers remain in Sound."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func parameters(_ gain: OticonFittedConfiguration.Gain) -> some View {
        Surface {
            DisclosureGroup(isExpanded: $showParameters) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("These are stored fitting parameter coordinates across 24 internal bands. Their mapping to acoustic dB, input levels and frequencies has not been established in Audifern. This is a read-only table, not a prescription or measured response."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ScrollView(.horizontal) {
                        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                            GridRow {
                                Text(L("Parameter")).frame(width: 110, alignment: .leading)
                                ForEach(0..<24) { index in Text("\(index + 1)").frame(width: 35) }
                            }.font(.caption2.weight(.medium)).foregroundStyle(.secondary).padding(.bottom, 9)
                            ForEach(Array(gain.map.enumerated()), id: \.offset) { row in
                                parameterRow(L("Gain row %d", row.offset + 1), values: row.element)
                            }
                            parameterRow(L("MPO"), values: gain.mpo)
                        }.font(.caption.monospacedDigit())
                    }
                }.padding(.top, 16)
            } label: {
                HStack {
                    Label(L("Advanced gain and output data"), systemImage: "tablecells").font(.headline)
                    Spacer()
                    Text(L("4 × 24 + MPO")).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func parameterRow(_ title: String, values: [Int]) -> some View {
        GridRow {
            Text(title).frame(width: 110, alignment: .leading).font(.caption.weight(.medium))
            ForEach(Array(values.enumerated()), id: \.offset) { value in
                Text(String(value.element)).frame(width: 35, height: 34)
                    .background(Brand.accent.opacity(value.offset % 2 == 0 ? 0.065 : 0.025))
            }
        }
    }

    private func accessories(_ fitting: OticonFittedConfiguration.Snapshot) -> some View {
        DisclosureGroup(isExpanded: $showAccessoryPrograms) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Stored accessory programs do not prove that an accessory is paired or currently in use."))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(fitting.accessoryPrograms, id: \.slot) { program in
                    HStack {
                        Image(systemName: "hifispeaker").foregroundStyle(Brand.accent).frame(width: 24)
                        Text(L(program.slot.title)).font(.callout)
                        Spacer()
                        Text(L("Stored")).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }.padding(.top, 14)
        } label: { Text(L("Accessory and automatic programs")).font(.headline) }
            .padding(22).background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func reportedToggle(_ value: Bool?) -> some View {
        Label(value.map { $0 ? L("Enabled") : L("Disabled") } ?? L("Not reported"),
              systemImage: value == true ? "checkmark.circle.fill" : "circle")
            .font(.callout).foregroundStyle(value == true ? Brand.accent : Color.secondary)
    }
    private func adaptationMode(_ mode: OticonFittedConfiguration.Adaptation.Mode) -> String {
        switch mode { case .manual: L("Manual"); case .automatic: L("Automatic"); case .paused: L("Paused") }
    }
}
