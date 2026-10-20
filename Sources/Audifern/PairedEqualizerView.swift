import CompanionCore
import SwiftUI

struct PairedEqualizerView: View {
    @ObservedObject var store: BluetoothStore
    let aids: [AidConnection]
    let microphone: Bool
    @Binding var linked: Bool
    let canLink: Bool
    @EnvironmentObject private var drafts: EqualizerDraftStore
    @EnvironmentObject private var preferences: AppPreferences
    @State private var resetIDs: [UUID] = []

    private var title: String { microphone ? "Microphone EQ" : "Streaming EQ" }
    private var source: String { microphone ? "microphone" : "streaming" }
    private var equalizers: [OticonEqualizer.State?] { aids.map(equalizer) }
    private func equalizer(_ aid: AidConnection) -> OticonEqualizer.State? {
        microphone ? aid.microphoneEqualizer : aid.streamingEqualizer
    }
    private func targets(_ aid: AidConnection) -> [AidConnection] { linked ? aids : [aid] }
    private func values(_ aid: AidConnection) -> [Double] { drafts[aid.id, microphone: microphone] ?? equalizer(aid)?.threeBandDB ?? [0, 0, 0] }
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
        drafts[aid.id, microphone: microphone] != nil && ready(aid)
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
        for target in targets(aid) { drafts[target.id, microphone: microphone] = levels }
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
            Text(linked ? L("Edit either side, then Apply to both. Each aid confirms its own EQ.")
                 : microphone ? L("Adjusts sound from the hearing-aid microphones. Apply sends your edits.")
                 : L("Adjusts streamed audio. Apply sends your edits."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: equalizers) { old, new in
            for (index, aid) in aids.enumerated() where index >= old.count || index >= new.count || old[index] == nil || new[index] == nil {
                drafts[aid.id, microphone: microphone] = nil
            }
        }
        .onChange(of: aids.map(\.activeProgram)) { _, _ in drafts.clear(microphone: microphone) }
        .alert(L("Restore %@?", String(describing: title.lowercased())), isPresented: Binding(get: { !resetIDs.isEmpty }, set: { if !$0 { resetIDs = [] } })) {
            Button(L("Restore neutral EQ")) {
                store.restoreSoundDefaults(resetIDs, scope: microphone ? .microphone : .streaming)
                for id in resetIDs { drafts[id, microphone: microphone] = nil }
                resetIDs = []
            }
            Button(L("Cancel"), role: .cancel) { resetIDs = [] }
        } message: {
            Text(L("Set every %@ EQ band to 0 dB on %@. The fitted program is preserved.", L(source), String(describing: resetIDs.count == 2 ? L("both ears") : L("this ear"))))
        }
    }

    private func editor(_ aid: AidConnection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L(title), systemImage: "slider.vertical.3").font(.callout.weight(.semibold))
                Spacer()
                if aid.advancedBusy { ProgressView().controlSize(.mini) }
            }
            if let eq = equalizer(aid) {
                ForEach(0..<3) { band in
                    HStack(spacing: 8) {
                        Text([L("Lows"), L("Mids"), L("Highs")][band]).font(.caption).frame(width: 34, alignment: .leading)
                        if let bounds = range(aid, band: band), bounds.lowerBound < bounds.upperBound {
                            Slider(value: Binding(get: { min(bounds.upperBound, max(bounds.lowerBound, values(aid)[band])) },
                                                  set: { edit(aid, band: band, value: $0) }),
                                   in: bounds, step: eq.stepDB)
                                .disabled(!ready(aid))
                                .accessibilityLabel("\(aid.sideLabel) \(source) \(["lows", "mids", "highs"][band])")
                        } else {
                            Text(linked ? L("Load both EQs") : L("Fixed")).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        }
                        Text(values(aid)[band], format: .number.precision(.fractionLength(1)).sign(strategy: .always()))
                            .font(.caption.monospacedDigit()).frame(width: 34, alignment: .trailing)
                        Text("dB").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Button(L("Reset EQ…")) { resetIDs = targets(aid).map(\.id) }
                        .disabled(!ready(aid) || (try? ConsumerControlPlan(aids: targets(aid), change: .restore(microphone ? .microphone : .streaming))) == nil)
                        .accessibilityLabel(L("Restore %@ %@ EQ%@", L(aid.sideLabel), L(source), String(describing: linked ? L(" for both ears") : "")))
                    Spacer(minLength: 0)
                    Button(linked ? L("Apply to both") : L("Apply")) {
                        store.setEqualizers(targets(aid).map(\.id), microphone: microphone, bandsDB: values(aid))
                        for target in targets(aid) { drafts[target.id, microphone: microphone] = nil }
                    }.buttonStyle(.borderedProminent).disabled(!canApply(aid))
                        .accessibilityLabel(L("Apply %@ %@ equalizer%@", L(aid.sideLabel), L(source), String(describing: linked ? L(" to both ears") : "")))
                }.font(.caption)
                if drafts[aid.id, microphone: microphone] != nil {
                    Button(L("Discard edits")) { for target in targets(aid) { drafts[target.id, microphone: microphone] = nil } }
                        .buttonStyle(.borderless).font(.caption)
                        .accessibilityLabel(L("Discard %@ %@ EQ edits", L(aid.sideLabel), L(source)))
                }
                if !eq.rangesReportedByDevice {
                    Text(L("Companion consumer limits")).font(.caption2).foregroundStyle(.tertiary)
                }
            } else {
                Text(L("Load advanced controls to read this equalizer.")).font(.caption).foregroundStyle(.secondary)
                Button(L("Load advanced controls")) { store.refreshAdvanced(aid.id) }
                    .disabled(!aid.isConnected || aid.advancedBusy || aid.actionPending || aid.groupActionPending)
                    .accessibilityLabel(L("Load %@ %@ controls", L(aid.sideLabel), L(source)))
            }
            if equalizer(aid) == nil, let status = aid.advancedStatus {
                Text(M(status)).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
