import CompanionCore
import SwiftUI

/// Capture is shared with the library's Update action. This only saves local
/// consumer adjustments; it never creates or writes a fitted program.
enum SoundPresetCapture {
    static func make(aids: [AidConnection], name: String, audiogramID: UUID?, replacing existing: SoundPreset? = nil) throws -> SoundPreset {
        guard !aids.isEmpty, aids.allSatisfy({ $0.isConnected && !$0.actionPending && !$0.advancedBusy && !$0.groupActionPending }) else {
            throw SoundPreset.ValidationError.invalid("Wait for the current hearing-aid request to finish before saving.")
        }
        let captured: [SoundPreset.Aid] = try aids.map { aid in
            guard let model = aid.model, let program = aid.activeProgram, let volume = aid.volume,
                  let side = SoundPreset.Side(rawValue: aid.sideLabel.lowercased()) else {
                throw SoundPreset.ValidationError.invalid("Read the hearing-aid model, side, program and volume first.")
            }
            return try .init(side: side, model: model, programID: program, volume: volume.level, muted: volume.muted,
                microphoneSteps: aid.microphoneEqualizer?.rawSteps, streamingSteps: aid.streamingEqualizer?.rawSteps,
                microphoneStepDB: aid.microphoneEqualizer?.stepDB, streamingStepDB: aid.streamingEqualizer?.stepDB)
        }
        return try SoundPreset(id: existing?.id ?? UUID(), name: existing?.name ?? name,
            createdAt: existing?.createdAt ?? Date(), updatedAt: Date(), audiogramID: audiogramID ?? existing?.audiogramID, aids: captured)
    }
}

struct SaveSoundPresetView: View {
    @ObservedObject var store: BluetoothStore
    @EnvironmentObject private var library: SoundPresetStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var preferences: AppPreferences
    @State private var status: String?
    private var aids: [AidConnection] {
        store.orderedConnections.filter { $0.isConnected && ["Left", "Right"].contains($0.sideLabel) }
    }
    private var canSave: Bool {
        !store.isDemo && (try? SoundPresetCapture.make(aids: aids, name: navigation.presetNameDraft, audiogramID: library.linkedAudiogramID)) != nil
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeading(title: L("Save current sound"), subtitle: L("Give this sound a name so you can return to it later.")) { EmptyView() }
                if store.connectedCount == 0 {
                    Label(L("Connect your hearing aids"), systemImage: "ear.badge.waveform").foregroundStyle(.secondary)
                    Button(L("Devices")) { navigation.show(.devices) }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 22) {
                        Text(L("Preset name")).font(AppType.headline)
                        TextField(L("Everyday clarity"), text: $navigation.presetNameDraft)
                            .font(.system(size: 22)).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("preset-name")
                        if let label = library.linkedAudiogramLabel {
                            Label(label, systemImage: "chart.xyaxis.line").font(AppType.callout)
                            Button(L("Unlink")) { library.linkedAudiogramID = nil; library.linkedAudiogramLabel = nil }
                        } else {
                            Button(L("Add audiogram reference…")) { navigation.present(.audiograms) }
                        }
                        Text(L("This saves volume and EQ for your existing fitted program. An audiogram reference is optional."))
                            .font(AppType.callout).foregroundStyle(.secondary)
                    }
                }
                if let status { Label(M(status), systemImage: "exclamationmark.circle").font(AppType.callout).foregroundStyle(.orange) }
                HStack {
                    Spacer()
                    Button(L("Cancel")) { navigation.closeSheet() }
                    Button(L("Save preset")) { save() }.buttonStyle(.borderedProminent).font(AppType.body).disabled(!canSave)
                        .keyboardShortcut(.defaultAction).accessibilityIdentifier("save-sound-preset")
                }
            }.padding(36).frame(maxWidth: 850)
        }
    }
    private func save() {
        do {
            guard canSave else { return }
            let preset = try SoundPresetCapture.make(aids: aids, name: navigation.presetNameDraft, audiogramID: library.linkedAudiogramID)
            try library.save(preset)
            navigation.presetNameDraft = ""
            navigation.closeSheet()
        } catch { status = error.localizedDescription }
    }
}
