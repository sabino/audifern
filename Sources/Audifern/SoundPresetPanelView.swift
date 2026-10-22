import CompanionCore
import SwiftUI

struct SoundPresetPanelView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @ObservedObject var store: BluetoothStore
    @EnvironmentObject private var library: SoundPresetStore
    @EnvironmentObject private var navigation: AppNavigation
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
        VStack(alignment: .leading, spacing: 20) {
            if library.presets.isEmpty {
                Surface {
                    ContentUnavailableView {
                        Label(L("Your favorite sounds, saved"), systemImage: "bookmark")
                    } description: {
                        Text(L("Adjust your sound, then save it as a preset. You can apply it again from here."))
                    } actions: {
                        Button(L("Save current sound")) { navigation.present(.savePreset) }.buttonStyle(.borderedProminent).tint(Brand.controlTint).font(AppType.body)
                    }.frame(minHeight: 260)
                }
            }
            ForEach(library.presets) { preset in
                Surface {
                    HStack(spacing: 20) {
                        Image(systemName: "waveform").font(.system(size: 27)).foregroundStyle(Brand.accent)
                            .frame(width: 66, height: 66).background(Brand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(preset.name).font(.system(size: 23, weight: .semibold))
                            Text(preset.aids.map { L($0.side.rawValue.capitalized) }.joined(separator: " · "))
                                .font(AppType.callout).foregroundStyle(.secondary)
                            Label(L("Saved on this Mac"), systemImage: "laptopcomputer").font(AppType.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Button(L("Apply")) { selectedID = preset.id; applySelected() }
                            .buttonStyle(.borderedProminent).tint(Brand.controlTint).font(AppType.body).disabled(isApplying || !canCapture)
                        Menu {
                            Button(L("Update from current sound")) { saveCurrent(replacing: preset) }.disabled(!canCapture || isApplying)
                            Button(L("Delete preset"), role: .destructive) { selectedID = preset.id; confirmingDelete = true }.disabled(isApplying)
                        } label: { Label(L("More"), systemImage: "ellipsis") }.fixedSize()
                    }
                }
            }
            if isApplying { ProgressView(L("Checking current hearing-aid settings…")) }
            if let message = status ?? library.error { Text(M(message)).font(AppType.callout).textSelection(.enabled) }
        }
        .confirmationDialog(L("Delete this saved sound preset?"), isPresented: $confirmingDelete) {
            Button(L("Delete preset"), role: .destructive) {
                guard let selectedID else { return }
                do { try library.delete(selectedID); self.selectedID = nil; status = "Preset deleted." }
                catch { status = error.localizedDescription }
            }
        }
    }

    private func saveCurrent(replacing existing: SoundPreset?) {
        do {
            guard canCapture, let existing else { return }
            let preset = try SoundPresetCapture.make(aids: liveAids, name: existing.name,
                audiogramID: library.linkedAudiogramID, replacing: existing)
            try library.save(preset)
            selectedID = preset.id
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
