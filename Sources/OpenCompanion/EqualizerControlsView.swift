import CompanionCore
import SwiftUI

struct EqualizerControlsView: View {
    @ObservedObject var store: BluetoothStore
    let aidID: UUID
    @State private var microphone = true
    @State private var draft = [Double](repeating: 0, count: 3)
    @State private var edited = false

    private var aid: AidConnection? { store.connections[aidID] }
    private var equalizer: OticonEqualizer.State? {
        microphone ? aid?.microphoneEqualizer : aid?.streamingEqualizer
    }
    private var canApply: Bool {
        let supported = microphone ? aid?.canChangeMicrophoneEqualizer : aid?.canChangeStreamingEqualizer
        return supported == true && edited && (try? equalizer?.steps(forThreeBandDB: draft)) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Equalizer", systemImage: "slider.vertical.3").font(.headline)
                Spacer()
                if aid?.advancedBusy == true { ProgressView().controlSize(.small) }
            }
            Picker("Sound source", selection: $microphone) {
                Text("Microphone").tag(true)
                    .accessibilityIdentifier("eq-\(aid?.sideLabel.lowercased() ?? "aid")-microphone")
                Text("Streaming").tag(false)
                    .accessibilityIdentifier("eq-\(aid?.sideLabel.lowercased() ?? "aid")-streaming")
            }.pickerStyle(.segmented)

            if let equalizer {
                ForEach(0..<3) { index in
                    let range = equalizer.threeBandRangesDB[index]
                    HStack(spacing: 10) {
                        Text(["Lows", "Mids", "Highs"][index]).font(.callout).frame(width: 42, alignment: .leading)
                        if range.lowerBound < range.upperBound {
                            Slider(value: Binding(get: { draft[index] }, set: { draft[index] = $0; edited = true }),
                                   in: range, step: equalizer.stepDB)
                                .accessibilityLabel("\(aid?.sideLabel ?? "Hearing aid") \(microphone ? "microphone" : "streaming") \(["lows", "mids", "highs"][index])")
                        } else { Text("Fixed").foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                        Text(draft[index], format: .number.precision(.fractionLength(1)).sign(strategy: .always()))
                            .font(.caption.monospacedDigit()).frame(width: 42, alignment: .trailing)
                        Text("dB").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(aid?.actionPending == true || aid?.advancedBusy == true)
                HStack {
                    Button("Use current values") { useCurrentValues() }.buttonStyle(.borderless)
                    Spacer()
                    Button("Apply equalizer") {
                        if microphone { store.setMicrophoneEqualizer(aidID, bandsDB: draft) }
                        else { store.setStreamingEqualizer(aidID, bandsDB: draft) }
                        edited = false
                    }.buttonStyle(.borderedProminent).disabled(!canApply)
                        .accessibilityLabel("Apply \(aid?.sideLabel.lowercased() ?? "hearing aid") \(microphone ? "microphone" : "streaming") equalizer")
                }.font(.caption)
                Text(microphone ? "Adjusts sound from the hearing-aid microphones." : "Adjusts audio streamed to the hearing aids.")
                    .font(.caption).foregroundStyle(.secondary)
                if !equalizer.rangesReportedByDevice {
                    Text("Limits follow Companion’s consumer controls.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text(microphone ? "Load the aid’s advanced controls to read its microphone equalizer." : "The streaming equalizer has not been read yet.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Load advanced controls") { store.refreshAdvanced(aidID) }
                    .disabled(aid?.isConnected != true || aid?.advancedBusy == true || aid?.actionPending == true)
                    .accessibilityLabel("Load \(aid?.sideLabel.lowercased() ?? "hearing aid") advanced controls")
            }
            if let status = aid?.advancedStatus { Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }
        .onAppear { useCurrentValues() }
        .onChange(of: microphone) { _, _ in useCurrentValues() }
        .onChange(of: equalizer) { old, new in
            if !edited || old == nil || new == nil { useCurrentValues() }
        }
        .onChange(of: aid?.activeProgram) { _, _ in useCurrentValues() }
    }

    private func useCurrentValues() {
        draft = equalizer?.threeBandDB ?? [0, 0, 0]
        edited = false
    }
}
