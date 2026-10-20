import SwiftUI

struct SpeechBoosterView: View {
    @ObservedObject var store: BluetoothStore
    let ids: [UUID]

    private var aids: [AidConnection] { ids.compactMap { store.connections[$0] } }
    private var loaded: Bool { !aids.isEmpty && aids.count == ids.count && aids.allSatisfy { $0.speechBoosterEnabled != nil } }
    private var enabled: Bool { loaded && aids.allSatisfy { $0.speechBoosterEnabled == true } }
    private var mixed: Bool { loaded && aids.contains { $0.speechBoosterEnabled == true } && !enabled }
    private var canChange: Bool { loaded && aids.allSatisfy(\.canChangeSpeechBooster) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if loaded {
                Toggle(isOn: Binding(get: { enabled }, set: { value in
                    guard canChange else { return }
                    for aid in aids { store.setSpeechBooster(aid.id, enabled: value) }
                })) {
                    Label("SpeechBooster", systemImage: "person.wave.2")
                }.toggleStyle(.switch).disabled(!canChange)
                    .accessibilityLabel(ids.count == 2 ? "SpeechBooster for both ears" : "\(aids.first?.sideLabel ?? "Hearing aid") SpeechBooster")
                if mixed { Text("Enabled for one ear. Turn on to enable both.").font(.caption).foregroundStyle(.secondary) }
            } else {
                HStack {
                    Label("SpeechBooster", systemImage: "person.wave.2")
                    Spacer()
                    Text("Not loaded").font(.caption).foregroundStyle(.secondary)
                    Button("Load") { for id in ids { store.refreshConsumerFeatures(id) } }
                        .disabled(aids.isEmpty || aids.contains { !$0.isConnected || $0.actionPending || $0.advancedBusy || $0.groupActionPending })
                        .accessibilityLabel(ids.count == 2 ? "Load both SpeechBooster controls" : "Load \(aids.first?.sideLabel.lowercased() ?? "aid") SpeechBooster")
                }
            }
            ForEach(aids) { aid in
                if let status = aid.consumerStatus {
                    Text(ids.count == 2 ? "\(aid.sideLabel): \(status)" : status)
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }.font(.callout)
    }
}
