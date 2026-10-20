import CompanionCore
import SwiftUI

struct LinkedControlsView: View {
    @ObservedObject var store: BluetoothStore

    private var pair: [AidConnection] { store.connectedPair }
    private var controls: LinkedHearingControls? {
        let values = pair.compactMap { state -> LinkedHearingControls.Aid? in
            guard let volume = state.volume, let range = state.volumeRanges?.main else { return nil }
            return .init(level: volume.level, muted: volume.muted, range: range)
        }
        return LinkedHearingControls(aids: values)
    }
    private var canControl: Bool { pair.count == 2 && pair.allSatisfy(\.canChangeVolume) && !store.linkedActionPending }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button { store.applyLinkedVolume(by: -1) } label: {
                    Image(systemName: "minus").frame(maxWidth: .infinity, minHeight: 28)
                }.disabled(!canControl || controls?.levels(adjustingBy: -1) == nil)
                    .accessibilityLabel("Decrease both microphone levels")
                Button { store.setLinkedMuted(!(controls?.allMuted ?? false)) } label: {
                    Label(controls?.allMuted == true ? "Unmute both" : "Mute both",
                          systemImage: controls?.allMuted == true ? "speaker.wave.2" : "speaker.slash")
                        .frame(maxWidth: .infinity, minHeight: 28)
                }.disabled(!canControl || controls == nil)
                    .accessibilityIdentifier("linked-mute")
                Button { store.applyLinkedVolume(by: 1) } label: {
                    Image(systemName: "plus").frame(maxWidth: .infinity, minHeight: 28)
                }.disabled(!canControl || controls?.levels(adjustingBy: 1) == nil)
                    .accessibilityLabel("Increase both microphone levels")
            }.buttonStyle(.bordered).controlSize(.large)
            Text("Volume steps preserve your left/right balance.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12).background(Color.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
}
