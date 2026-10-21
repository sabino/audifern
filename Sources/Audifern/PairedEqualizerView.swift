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
    @State private var detailed: Bool

    init(store: BluetoothStore, aids: [AidConnection], microphone: Bool, linked: Binding<Bool>,
         canLink: Bool, detailed: Bool = false) {
        self.store = store; self.aids = aids; self.microphone = microphone
        _linked = linked; self.canLink = canLink; _detailed = State(initialValue: detailed)
    }

    private var title: String { microphone ? "Microphone EQ" : "Streaming EQ" }
    private var source: String { microphone ? "microphone" : "streaming" }
    private var equalizers: [OticonEqualizer.State?] { aids.map(equalizer) }
    private var frequencyLayoutsConflict: Bool {
        let layouts = equalizers.compactMap { $0?.frequenciesHz }
        return layouts.first.map { first in layouts.contains { $0 != first } } ?? false
    }
    private func equalizer(_ aid: AidConnection) -> OticonEqualizer.State? {
        microphone ? aid.microphoneEqualizer : aid.streamingEqualizer
    }
    private func targets(_ aid: AidConnection) -> [AidConnection] { linked ? aids : [aid] }
    private func values(_ aid: AidConnection) -> [Double] {
        drafts.channelValues(for: aid, microphone: microphone) ?? Array(repeating: 0, count: 8)
    }
    private func requestedLevels(_ aid: AidConnection) -> [UUID: [Double]] {
        Dictionary(uniqueKeysWithValues: targets(aid).compactMap { target in
            drafts.channelValues(for: target, microphone: microphone).map { (target.id, $0) }
        })
    }
    private func displayedValue(_ aid: AidConnection, band: Int) -> Double {
        let levels = values(aid)
        return detailed ? levels[band] : OticonEqualizer.groups[band].map { levels[$0] }.min()!
    }
    private func range(_ aid: AidConnection, band: Int) -> ClosedRange<Double>? {
        let eqs = targets(aid).compactMap(equalizer)
        guard eqs.count == targets(aid).count,
              let lower = eqs.map({ (detailed ? $0.channelRangesDB : $0.threeBandRangesDB)[band].lowerBound }).max(),
              let upper = eqs.map({ (detailed ? $0.channelRangesDB : $0.threeBandRangesDB)[band].upperBound }).min(), lower <= upper else { return nil }
        return lower...upper
    }
    private func ready(_ aid: AidConnection) -> Bool {
        targets(aid).allSatisfy { microphone ? $0.canChangeMicrophoneEqualizer : $0.canChangeStreamingEqualizer }
            && !store.linkedActionPending && (!linked || (canLink && !frequencyLayoutsConflict))
    }
    private func canApply(_ aid: AidConnection) -> Bool {
        drafts[aid.id, microphone: microphone] != nil && ready(aid)
            && [3, 8].contains(drafts[aid.id, microphone: microphone]?.count ?? 0)
            && (try? ConsumerControlPlan(aids: targets(aid), change: .equalizerChannels(microphone: microphone, levelsByAid: requestedLevels(aid)))) != nil
    }
    private func edit(_ aid: AidConnection, band: Int, value: Double) {
        drafts.editChannels(targets(aid), microphone: microphone,
            channels: detailed ? [band] : Array(OticonEqualizer.groups[band]), value: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("EQ detail")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker(L("EQ detail"), selection: $detailed) {
                    Text(L("Tone controls")).tag(false)
                    Text(L("8 bands")).tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 220)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(source)-eq-detail")
            }
            if aids.count == 1, let aid = aids.first { editor(aid) }
            else {
                EarSettingsRow {
                    if let aid = aids.first { editor(aid) }
                } center: {
                    EarLinkButton(title: title, linked: $linked, available: canLink && (linked || !frequencyLayoutsConflict),
                                  identifier: "link-\(source)-eq")
                } right: {
                    if aids.count == 2 { editor(aids[1]) }
                }
            }
            Text(linked ? L("New edits are mirrored to both ears. Each aid keeps its other bands and confirms its own EQ.")
                 : microphone ? L("Adjusts sound from the hearing-aid microphones. Apply sends your edits.")
                 : L("Adjusts streamed audio. Apply sends your edits."))
                .font(.caption).foregroundStyle(.secondary)
            if linked && frequencyLayoutsConflict {
                Text(L("The aids report different EQ frequency layouts. Adjust each ear separately."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.fixedSize(horizontal: false, vertical: true)
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
                ForEach(0..<(detailed ? 8 : 3), id: \.self) { band in
                    HStack(spacing: 8) {
                        Text(bandLabel(aid, band: band)).font(.caption).frame(width: detailed ? 58 : 34, alignment: .leading)
                        if let bounds = range(aid, band: band), bounds.lowerBound < bounds.upperBound {
                            Slider(value: Binding(get: { min(bounds.upperBound, max(bounds.lowerBound, displayedValue(aid, band: band))) },
                                                  set: { edit(aid, band: band, value: $0) }),
                                   in: bounds, step: eq.stepDB)
                                .disabled(!ready(aid))
                                .accessibilityLabel(L("%@ %@ EQ · %@", L(aid.sideLabel), L(source), bandLabel(aid, band: band)))
                        } else {
                            Text(linked ? L("Load both EQs") : L("Fixed")).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        }
                        Text(displayedValue(aid, band: band), format: .number.precision(.fractionLength(1)).sign(strategy: .always()))
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
                        store.setEqualizerChannels(targets(aid).map(\.id), microphone: microphone, levelsByAid: requestedLevels(aid))
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
                if detailed {
                    Text(eq.frequenciesHz == nil
                         ? L("Numbered bands follow device order. This aid has not reported frequency labels.")
                         : L("Frequencies reported by this hearing aid. These are consumer EQ adjustments."))
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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

    private func bandLabel(_ aid: AidConnection, band: Int) -> String {
        guard detailed else { return [L("Lows"), L("Mids"), L("Highs")][band] }
        guard let frequencies = equalizer(aid)?.frequenciesHz else { return L("Band %d", band + 1) }
        let hz = frequencies[band]
        let value = (hz >= 1000 ? hz / 1000 : hz).formatted(.number.precision(.fractionLength(0...1)))
        return hz >= 1000 ? L("%@ kHz", value) : L("%@ Hz", value)
    }
}
