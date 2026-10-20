import CompanionCore
import SwiftUI

struct PairedEqualizerView: View {
    @ObservedObject var store: BluetoothStore
    let aids: [AidConnection]
    let microphone: Bool
    @Binding var linked: Bool
    let canLink: Bool
    @State private var drafts: [UUID: [Double]] = [:]
    @State private var resetIDs: [UUID] = []

    private var title: String { microphone ? "Microphone EQ" : "Streaming EQ" }
    private var source: String { microphone ? "microphone" : "streaming" }
    private var equalizers: [OticonEqualizer.State?] { aids.map(equalizer) }
    private func equalizer(_ aid: AidConnection) -> OticonEqualizer.State? {
        microphone ? aid.microphoneEqualizer : aid.streamingEqualizer
    }
    private func targets(_ aid: AidConnection) -> [AidConnection] { linked ? aids : [aid] }
    private func values(_ aid: AidConnection) -> [Double] { drafts[aid.id] ?? equalizer(aid)?.threeBandDB ?? [0, 0, 0] }
    private func range(_ aid: AidConnection, band: Int) -> ClosedRange<Double>? {
        let eqs = targets(aid).compactMap(equalizer)
        guard eqs.count == targets(aid).count,
              let lower = eqs.map({ $0.threeBandRangesDB[band].lowerBound }).max(),
              let upper = eqs.map({ $0.threeBandRangesDB[band].upperBound }).min(), lower <= upper else { return nil }
        return lower...upper
    }
    private func ready(_ aid: AidConnection) -> Bool {
        targets(aid).allSatisfy { microphone ? $0.canChangeMicrophoneEqualizer : $0.canChangeStreamingEqualizer }
            && !store.linkedActionPending && (!linked || canLink)
    }
    private func canApply(_ aid: AidConnection) -> Bool {
        drafts[aid.id] != nil && ready(aid)
            && (try? ConsumerControlPlan(aids: targets(aid), change: .equalizer(microphone: microphone, bandsDB: values(aid)))) != nil
    }
    private func edit(_ aid: AidConnection, band: Int, value: Double) {
        var levels = values(aid)
        levels[band] = value
        if linked {
            // One edit becomes a shared draft; each aid still quantizes the
            // requested dB values with its own scale when Apply is pressed.
            for index in 0..<3 {
                if let bounds = range(aid, band: index) { levels[index] = min(bounds.upperBound, max(bounds.lowerBound, levels[index])) }
            }
        }
        for target in targets(aid) { drafts[target.id] = levels }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EarSettingsRow {
                if let aid = aids.first { editor(aid) }
            } center: {
                EarLinkButton(title: title, linked: $linked, available: canLink,
                              identifier: "link-\(source)-eq")
            } right: {
                if aids.count == 2 { editor(aids[1]) }
            }
            Text(linked ? "Edit either side, then Apply to both. Each aid confirms its own EQ."
                 : microphone ? "Adjusts sound from the hearing-aid microphones. Apply sends your edits."
                 : "Adjusts streamed audio. Apply sends your edits.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: equalizers) { old, new in
            for (index, aid) in aids.enumerated() where index >= old.count || index >= new.count || old[index] == nil || new[index] == nil {
                drafts.removeValue(forKey: aid.id)
            }
        }
        .onChange(of: aids.map(\.activeProgram)) { _, _ in drafts.removeAll() }
        .alert("Restore \(title.lowercased())?", isPresented: Binding(get: { !resetIDs.isEmpty }, set: { if !$0 { resetIDs = [] } })) {
            Button("Restore neutral EQ") {
                store.restoreSoundDefaults(resetIDs, scope: microphone ? .microphone : .streaming)
                for id in resetIDs { drafts.removeValue(forKey: id) }
                resetIDs = []
            }
            Button("Cancel", role: .cancel) { resetIDs = [] }
        } message: {
            Text("Set every \(source) EQ band to 0 dB on \(resetIDs.count == 2 ? "both ears" : "this ear"). The fitted program is preserved.")
        }
    }

    private func editor(_ aid: AidConnection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: "slider.vertical.3").font(.callout.weight(.semibold))
                Spacer()
                if aid.advancedBusy { ProgressView().controlSize(.mini) }
            }
            if let eq = equalizer(aid) {
                ForEach(0..<3) { band in
                    HStack(spacing: 8) {
                        Text(["Lows", "Mids", "Highs"][band]).font(.caption).frame(width: 34, alignment: .leading)
                        if let bounds = range(aid, band: band), bounds.lowerBound < bounds.upperBound {
                            Slider(value: Binding(get: { min(bounds.upperBound, max(bounds.lowerBound, values(aid)[band])) },
                                                  set: { edit(aid, band: band, value: $0) }),
                                   in: bounds, step: eq.stepDB)
                                .disabled(!ready(aid))
                                .accessibilityLabel("\(aid.sideLabel) \(source) \(["lows", "mids", "highs"][band])")
                        } else {
                            Text(linked ? "Load both EQs" : "Fixed").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        }
                        Text(values(aid)[band], format: .number.precision(.fractionLength(1)).sign(strategy: .always()))
                            .font(.caption.monospacedDigit()).frame(width: 34, alignment: .trailing)
                        Text("dB").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Button("Reset EQ…") { resetIDs = targets(aid).map(\.id) }
                        .disabled(!ready(aid) || (try? ConsumerControlPlan(aids: targets(aid), change: .restore(microphone ? .microphone : .streaming))) == nil)
                        .accessibilityLabel("Restore \(aid.sideLabel.lowercased()) \(source) EQ\(linked ? " for both ears" : "")")
                    Spacer(minLength: 0)
                    Button(linked ? "Apply to both" : "Apply") {
                        store.setEqualizers(targets(aid).map(\.id), microphone: microphone, bandsDB: values(aid))
                        for target in targets(aid) { drafts.removeValue(forKey: target.id) }
                    }.buttonStyle(.borderedProminent).disabled(!canApply(aid))
                        .accessibilityLabel("Apply \(aid.sideLabel.lowercased()) \(source) equalizer\(linked ? " to both ears" : "")")
                }.font(.caption)
                if drafts[aid.id] != nil {
                    Button("Discard edits") { for target in targets(aid) { drafts.removeValue(forKey: target.id) } }
                        .buttonStyle(.borderless).font(.caption)
                        .accessibilityLabel("Discard \(aid.sideLabel.lowercased()) \(source) EQ edits")
                }
                if !eq.rangesReportedByDevice {
                    Text("Companion consumer limits").font(.caption2).foregroundStyle(.tertiary)
                }
            } else {
                Text("Load advanced controls to read this equalizer.").font(.caption).foregroundStyle(.secondary)
                Button("Load advanced controls") { store.refreshAdvanced(aid.id) }
                    .disabled(!aid.isConnected || aid.advancedBusy || aid.actionPending || aid.groupActionPending)
                    .accessibilityLabel("Load \(aid.sideLabel.lowercased()) \(source) controls")
            }
            if equalizer(aid) == nil, let status = aid.advancedStatus {
                Text(status).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
