import CompanionCore
import SwiftUI

struct LinkedControlsView: View {
    @ObservedObject var store: BluetoothStore
    @EnvironmentObject private var preferences: AppPreferences
    private var pair: [AidConnection] { store.connectedPair }
    private var controls: LinkedHearingControls? {
        let values = pair.compactMap { state -> LinkedHearingControls.Aid? in
            guard let volume = state.volume, let range = state.volumeRanges?.main else { return nil }
            return .init(level: volume.level, muted: volume.muted, range: range)
        }
        return LinkedHearingControls(aids: values)
    }
    private var canControl: Bool { pair.count == 2 && pair.allSatisfy(\.canChangeVolume) && !store.linkedActionPending }
    private var level: String {
        let levels = pair.compactMap { $0.volume?.level }
        guard levels.count == 2 else { return "—" }
        return levels[0] == levels[1] ? String(levels[0]) : levels.map(String.init).joined(separator: " / ")
    }
    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 30) {
                Button { store.applyLinkedVolume(by: -1) } label: { Image(systemName: "minus").font(.title2).frame(width: 56, height: 56) }
                    .buttonStyle(RoundControlButtonStyle())
                    .disabled(!canControl || controls?.levels(adjustingBy: -1) == nil)
                    .accessibilityLabel(L("Decrease both microphone levels"))
                VStack(spacing: 3) {
                    Text(level).font(.system(size: 36, weight: .semibold)).monospacedDigit().accessibilityIdentifier("linked-volume-value")
                    Text(L("Volume")).font(.caption).foregroundStyle(.secondary)
                }.frame(minWidth: 90)
                Button { store.applyLinkedVolume(by: 1) } label: { Image(systemName: "plus").font(.title2).frame(width: 56, height: 56) }
                    .buttonStyle(RoundControlButtonStyle())
                    .disabled(!canControl || controls?.levels(adjustingBy: 1) == nil)
                    .accessibilityLabel(L("Increase both microphone levels"))
            }.frame(maxWidth: .infinity)
            Button { store.setLinkedMuted(!(controls?.allMuted ?? false)) } label: {
                Label(controls?.allMuted == true ? L("Unmute") : L("Mute"), systemImage: controls?.allMuted == true ? "speaker.wave.2" : "speaker.slash")
                    .frame(minWidth: 110, minHeight: 24)
            }.buttonStyle(.bordered).controlSize(.large).disabled(!canControl || controls == nil)
                .accessibilityIdentifier("linked-mute")
            Text(L("Volume steps preserve your left/right balance.")).font(.caption).foregroundStyle(.secondary)
        }
    }
}
