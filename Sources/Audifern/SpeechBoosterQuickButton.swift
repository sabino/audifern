import SwiftUI

/// A small, anchored control instead of an entire daily-control card.
struct SpeechBoosterQuickButton: View {
    @ObservedObject var store: BluetoothStore
    let aids: [AidConnection]
    @AppStorage("groupedSpeechBoosterControls") private var together = true
    @State private var showing = false
    private var canLink: Bool { aids.count == 2 && store.connectedPair.count == 2 }
    private var state: String {
        if aids.isEmpty || aids.contains(where: { $0.speechBoosterEnabled == nil }) { return L("Not loaded") }
        if aids.allSatisfy({ $0.speechBoosterEnabled == true }) { return L("On") }
        if aids.allSatisfy({ $0.speechBoosterEnabled == false }) { return L("Off") }
        return L("Mixed")
    }
    var body: some View {
        Button { showing.toggle() } label: {
            Label(L("SpeechBooster"), systemImage: "mic.fill")
                .font(AppType.small).foregroundStyle(.purple)
        }.buttonStyle(.bordered).controlSize(.regular)
            .help(L("SpeechBooster") + ": " + state)
            .accessibilityValue(state).accessibilityIdentifier("speech-booster-quick")
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                VStack(spacing: 16) {
                    HStack {
                        Label(L("SpeechBooster"), systemImage: "mic.fill").font(AppType.headline).foregroundStyle(.purple)
                        Spacer()
                        Button(L("Done")) { showing = false }.controlSize(.regular)
                    }
                    if aids.count == 2 {
                        EarControlModePicker(together: $together, available: canLink, accent: .purple,
                                             scope: L("SpeechBooster"), identifier: "link-speech-booster")
                    }
                    HStack(spacing: 20) {
                        if together && aids.count == 2 {
                            booster(aids, label: L("SpeechBooster for both ears"))
                        } else {
                            ForEach(aids) { booster([$0], label: L($0.sideLabel)) }
                        }
                    }.disabled(store.isDemo)
                }.padding(20).frame(width: 340).tint(.purple)
            }
    }
    private func booster(_ targets: [AidConnection], label: String) -> some View {
        VStack(spacing: 8) {
            Text(label).font(AppType.callout).lineLimit(2)
            Toggle(label, isOn: Binding(get: { targets.allSatisfy { $0.speechBoosterEnabled == true } },
                set: { store.setSpeechBoosters(targets.map(\.id), enabled: $0) }))
                .toggleStyle(.switch).labelsHidden()
                .disabled(!targets.allSatisfy(\.canChangeSpeechBooster) || store.linkedActionPending)
                .accessibilityLabel(label)
            SpeechBoosterReadStatusView(store: store, aids: targets)
        }.frame(maxWidth: .infinity)
    }
}
