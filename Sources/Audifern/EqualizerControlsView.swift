import CompanionCore
import SwiftUI

struct EqualizerControlsView: View {
    @EnvironmentObject private var preferences: AppPreferences
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
                Label(L("Equalizer"), systemImage: "slider.vertical.3").font(AppType.headline)
                Spacer()
                if aid?.advancedBusy == true { ProgressView().controlSize(.small) }
            }
            Picker(L("Sound source"), selection: $microphone) {
                Text(L("Microphone")).tag(true)
                    .accessibilityIdentifier("eq-\(aid?.sideLabel.lowercased() ?? "aid")-microphone")
                Text(L("Streaming")).tag(false)
                    .accessibilityIdentifier("eq-\(aid?.sideLabel.lowercased() ?? "aid")-streaming")
            }.pickerStyle(.segmented).tint(Brand.controlTint).font(AppType.body)

            if let equalizer {
                ForEach(0..<3) { index in
                    let range = equalizer.threeBandRangesDB[index]
                    HStack(spacing: 10) {
                        Text([L("Lows"), L("Mids"), L("Highs")][index]).font(AppType.callout).frame(width: 42, alignment: .leading)
                        if range.lowerBound < range.upperBound {
                            Slider(value: Binding(get: { draft[index] }, set: { draft[index] = $0; edited = true }),
                                   in: range, step: equalizer.stepDB)
                                .accessibilityLabel("\(aid?.sideLabel ?? L("Hearing aid")) \(microphone ? "microphone" : "streaming") \(["lows", "mids", "highs"][index])")
                        } else { Text(L("Fixed")).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                        Text(draft[index], format: .number.precision(.fractionLength(1)).sign(strategy: .always()))
                            .font(AppType.caption.monospacedDigit()).frame(width: 42, alignment: .trailing)
                        Text("dB").font(AppType.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(aid?.actionPending == true || aid?.advancedBusy == true || aid?.groupActionPending == true)
                HStack {
                    Button(L("Use current values")) { useCurrentValues() }.buttonStyle(.borderless)
                    Spacer()
                    Button(L("Apply equalizer")) {
                        if microphone { store.setMicrophoneEqualizer(aidID, bandsDB: draft) }
                        else { store.setStreamingEqualizer(aidID, bandsDB: draft) }
                        edited = false
                    }.buttonStyle(.borderedProminent).tint(Brand.controlTint).font(AppType.body).disabled(!canApply)
                        .accessibilityLabel(L("Apply %@ %@ equalizer", String(describing: aid?.sideLabel.lowercased() ?? L("hearing aid")), String(describing: microphone ? "microphone" : "streaming")))
                }.font(AppType.caption)
                Text(microphone ? L("Adjusts sound from the hearing-aid microphones.") : L("Adjusts audio streamed to the hearing aids."))
                    .font(AppType.caption).foregroundStyle(.secondary)
                if !equalizer.rangesReportedByDevice {
                    Text(L("Limits follow Companion’s consumer controls."))
                        .font(AppType.small).foregroundStyle(.secondary)
                }
            } else {
                Text(microphone ? L("Load the aid’s advanced controls to read its microphone equalizer.") : L("The streaming equalizer has not been read yet."))
                    .font(AppType.callout).foregroundStyle(.secondary)
                Button(L("Load advanced controls")) { store.refreshAdvanced(aidID) }
                    .disabled(aid?.isConnected != true || aid?.advancedBusy == true || aid?.actionPending == true || aid?.groupActionPending == true)
                    .accessibilityLabel(L("Load %@ advanced controls", String(describing: aid?.sideLabel.lowercased() ?? L("hearing aid"))))
            }
            if let status = aid?.advancedStatus { Text(M(status)).font(AppType.caption).foregroundStyle(.secondary).textSelection(.enabled) }
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
