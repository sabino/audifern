import SwiftUI

/// Reserves one small status line so loading does not move the sound controls.
struct SpeechBoosterReadStatusView: View {
    @ObservedObject var store: BluetoothStore
    let aids: [AidConnection]
    @ObservedObject private var loader: DeviceReadLoader
    init(store: BluetoothStore, aids: [AidConnection]) {
        self.store = store; self.aids = aids; loader = store.consumerFeatureLoader
    }
    private var loading: Bool { aids.contains { loader.states[$0.id]?.status.isLoading == true } }
    private var unsupportedProgram: Bool {
        aids.contains { aid in aid.activeProgram.flatMap { aid.programBoostable[$0] } == false }
    }
    private var missing: Bool {
        aids.contains { aid in aid.speechBoosterEnabled == nil || aid.activeProgram.flatMap { aid.programBoostable[$0] } == nil }
    }
    private var details: String {
        aids.compactMap { aid -> String? in
            if case .failed(let error) = loader.states[aid.id]?.status { return L("%@ · %@", L(aid.sideLabel), M(error)) }
            return aid.consumerStatus.map { L("%@ · %@", L(aid.sideLabel), M($0)) }
        }.joined(separator: "\n")
    }
    var body: some View {
        Group {
            if !aids.allSatisfy(\.isConnected) { Text(L("Connect your hearing aids")) }
            else if unsupportedProgram { Text(L("Unavailable in this program")) }
            else if loading { Text(L("Reading SpeechBooster…")) }
            else if missing && !store.isDemo {
                Button(L("Retry SpeechBooster")) { for aid in aids { store.refreshConsumerFeatures(aid.id) } }
                    .buttonStyle(.borderless).disabled(store.linkedActionPending)
            } else { Text(" ").accessibilityHidden(true) }
        }.font(AppType.small).foregroundStyle(.secondary).lineLimit(1).help(details)
            .frame(height: 18).accessibilityIdentifier("speech-booster-read-status")
    }
}
