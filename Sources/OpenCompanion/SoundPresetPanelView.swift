import CompanionCore
import SwiftUI

struct SoundPresetPanelView: View {
    @ObservedObject var store: BluetoothStore
    @EnvironmentObject private var library: SoundPresetStore
    @EnvironmentObject private var navigation: AppNavigation
    @State private var name = ""
    @State private var selectedID: UUID?
    @State private var status: String?
    @State private var isApplying = false
    @State private var confirmingDelete = false

    private var selected: SoundPreset? { library.presets.first { $0.id == selectedID } }
    private var liveAids: [AidConnection] {
        store.orderedConnections.filter { $0.isConnected && $0.volume != nil && $0.activeProgram != nil && ["Left", "Right"].contains($0.sideLabel) }
    }
    private var canCapture: Bool {
        !liveAids.isEmpty && liveAids.allSatisfy { !$0.actionPending && !$0.advancedBusy && !$0.groupActionPending }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text("Save your current volume and equalizers as a named preset on this Mac. Applying a preset adjusts the existing hearing-aid program.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    TextField("New preset name", text: $name).textFieldStyle(.roundedBorder)
                    Button("Save current sound") { saveCurrent(replacing: nil) }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !canCapture || isApplying)
                }
                if !library.presets.isEmpty {
                    HStack {
                        Picker("Saved preset", selection: $selectedID) {
                            Text("Choose a preset").tag(nil as UUID?)
                            ForEach(library.presets) { Text($0.name).tag(Optional($0.id)) }
                        }
                        Button("Apply") { applySelected() }.disabled(selected == nil || isApplying || !canCapture)
                        if isApplying { ProgressView().controlSize(.small) }
                    }
                    if let selected {
                        HStack {
                            Button("Update from current sound") { saveCurrent(replacing: selected) }.disabled(!canCapture || isApplying)
                            Spacer()
                            Button("Delete preset", role: .destructive) { confirmingDelete = true }.disabled(isApplying)
                        }.font(.caption)
                        Text("Saved for \(selected.aids.map { $0.side.rawValue.capitalized }.joined(separator: " and ")). Selecting it does not change the aids until you press Apply.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Audiogram") { navigation.page = .audiogram }
                    if let label = library.linkedAudiogramLabel {
                        Text("Linked exam: \(label)").font(.caption).foregroundStyle(.secondary)
                        Button("Unlink") { library.linkedAudiogramID = nil; library.linkedAudiogramLabel = nil }.font(.caption)
                    } else { Text("A saved exam can be attached for reference.").font(.caption).foregroundStyle(.secondary) }
                }
                if let message = status ?? library.error { Text(message).font(.caption).textSelection(.enabled) }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        } label: { Label("Sound presets on this Mac", systemImage: "bookmark") }
        .confirmationDialog("Delete this saved sound preset?", isPresented: $confirmingDelete) {
            Button("Delete preset", role: .destructive) {
                guard let selectedID else { return }
                do { try library.delete(selectedID); self.selectedID = nil; status = "Preset deleted." }
                catch { status = error.localizedDescription }
            }
        }
    }

    private func saveCurrent(replacing existing: SoundPreset?) {
        do {
            guard canCapture else { throw SoundPreset.ValidationError.invalid("Wait for the current hearing-aid request to finish before saving.") }
            let aids: [SoundPreset.Aid] = try liveAids.map { aid in
                guard let model = aid.model, let program = aid.activeProgram, let volume = aid.volume,
                      let side = SoundPreset.Side(rawValue: aid.sideLabel.lowercased()) else {
                    throw SoundPreset.ValidationError.invalid("Read the hearing-aid model, side, program and volume first.")
                }
                return try .init(side: side, model: model, programID: program, volume: volume.level, muted: volume.muted,
                                 microphoneSteps: aid.microphoneEqualizer?.rawSteps,
                                 streamingSteps: aid.streamingEqualizer?.rawSteps,
                                 microphoneStepDB: aid.microphoneEqualizer?.stepDB,
                                 streamingStepDB: aid.streamingEqualizer?.stepDB)
            }
            let preset = try SoundPreset(id: existing?.id ?? UUID(), name: existing?.name ?? name,
                                         createdAt: existing?.createdAt ?? Date(), updatedAt: Date(),
                                         audiogramID: library.linkedAudiogramID ?? existing?.audiogramID, aids: aids)
            try library.save(preset)
            selectedID = preset.id; name = ""
            status = "Saved \(preset.name) on this Mac. Audiogram values are stored for reference; they do not prescribe amplification."
        } catch { status = error.localizedDescription }
    }

    private func applySelected() {
        guard let preset = selected, !isApplying else { return }
        isApplying = true; status = "Checking current hearing-aid settings…"
        Task { @MainActor in
            var completed: [String] = []
            defer { isApplying = false }
            do {
                // Check every side before changing either. The transport checks
                // live ranges and confirms each individual operation again.
                var targets: [(SoundPreset.Aid, UUID)] = []
                for saved in preset.aids {
                    guard let live = liveAids.first(where: { $0.sideLabel.lowercased() == saved.side.rawValue }),
                          live.model == saved.model, live.programIDs.contains(saved.programID),
                          live.activeProgram == saved.programID, !live.actionPending, !live.advancedBusy, !live.groupActionPending,
                          live.volumeRanges?.main.contains(saved.volume) == true else {
                        throw SoundPreset.ValidationError.invalid("Connect the matching \(saved.side.rawValue) aid and read its current program and volume limits first.")
                    }
                    for (steps, savedStep, current) in [(saved.microphoneSteps, saved.microphoneStepDB, live.microphoneEqualizer),
                                                        (saved.streamingSteps, saved.streamingStepDB, live.streamingEqualizer)] {
                        if let steps {
                            guard let current, let savedStep, abs(current.stepDB - savedStep) < 0.000_001 else {
                                throw SoundPreset.ValidationError.invalid("Load the matching equalizer before applying this preset.")
                            }
                            try current.validate(steps)
                        }
                    }
                    targets.append((saved, live.id))
                }
                for (saved, id) in targets {
                    try await store.applySoundSettings(id, program: saved.programID, volume: saved.volume, muted: saved.muted,
                                                       microphoneSteps: saved.microphoneSteps, streamingSteps: saved.streamingSteps)
                    completed.append(saved.side.rawValue.capitalized)
                }
                status = "\(preset.name) confirmed for \(completed.joined(separator: " and "))."
            } catch {
                status = (completed.isEmpty ? "" : "Applied to \(completed.joined(separator: ", ")). ") + "Stopped: \(error.localizedDescription)"
            }
        }
    }
}
