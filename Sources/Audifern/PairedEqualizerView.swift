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
    @ObservedObject private var loader: EqualizerLoader
    @State private var resetIDs: [UUID] = []
    @State private var detailed: Bool
    @State private var selectedID: UUID?
    private enum Target: Hashable { case left, both, right }
    private var appliesToBoth: Bool { linked && aids.count == 2 }
    private var selectedAid: AidConnection? { aids.first { $0.id == selectedID } ?? aids.first }

    init(store: BluetoothStore, aids: [AidConnection], microphone: Bool, linked: Binding<Bool>,
         canLink: Bool, detailed: Bool = false) {
        self.store = store; self.aids = aids; self.microphone = microphone
        loader = store.equalizerLoader
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
    private func targets(_ aid: AidConnection) -> [AidConnection] { appliesToBoth ? aids : [aid] }
    private var requestedAids: [AidConnection] { selectedAid.map(targets) ?? [] }
    private var loadContext: [EqualizerLoader.Context] {
        requestedAids.filter(\.isConnected).map { .init(id: $0.id, connectedAt: $0.connectedAt, program: $0.activeProgram) }
    }
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
            && targets(aid).allSatisfy { loader.states[$0.id]?.status.isLoading != true }
            && !store.linkedActionPending && (!appliesToBoth || (canLink && !frequencyLayoutsConflict))
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
                Text(L("EQ detail")).font(AppType.caption).foregroundStyle(.secondary)
                Spacer()
                Picker(L("EQ detail"), selection: $detailed) {
                    Text(L("Tone controls")).tag(false)
                    Text(L("8 bands")).tag(true)
                }.pickerStyle(.segmented).font(AppType.body).labelsHidden().frame(maxWidth: 340)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(source)-eq-detail")
            }
            if aids.count == 2 {
                Picker(L("Adjust"), selection: Binding(get: {
                    appliesToBoth ? Target.both : selectedAid?.id == aids.last?.id ? .right : .left
                }, set: { target in
                    linked = target == .both
                    if target == .left { selectedID = aids[0].id }
                    if target == .right { selectedID = aids[1].id }
                })) {
                    Text(L(aids[0].sideLabel)).tag(Target.left)
                    Text(L("Both ears")).tag(Target.both).disabled(!canLink || frequencyLayoutsConflict)
                    Text(L(aids[1].sideLabel)).tag(Target.right)
                }.pickerStyle(.segmented).font(AppType.body).accessibilityIdentifier("\(source)-eq-target")
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(requestedAids) { aid in loadingStatus(aid) }
            }
            if let aid = selectedAid {
                editor(aid)
            }
            Text(appliesToBoth ? L("New edits are mirrored to both ears. Each aid keeps its other bands and confirms its own EQ.")
                 : microphone ? L("Adjusts sound from the hearing-aid microphones. Apply sends your edits.")
                 : L("Adjusts streamed audio. Apply sends your edits."))
                .font(AppType.caption).foregroundStyle(.secondary)
            if appliesToBoth && frequencyLayoutsConflict {
                Text(L("The aids report different EQ frequency layouts. Adjust each ear separately."))
                    .font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.fixedSize(horizontal: false, vertical: true)
        .onChange(of: loadContext, initial: true) { _, contexts in
            store.loadEqualizersIfNeeded(contexts.map(\.id), microphone: microphone)
        }
        .onChange(of: equalizers) { old, new in
            for (index, aid) in aids.enumerated() where index >= old.count || index >= new.count || old[index] == nil || new[index] == nil {
                drafts[aid.id, microphone: microphone] = nil
            }
            store.loadEqualizersIfNeeded(loadContext.map(\.id), microphone: microphone)
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

    private func loadingStatus(_ aid: AidConnection) -> some View {
        let status = loader.states[aid.id]?.status
        let loading = status?.isLoading == true
        let hasEQ = equalizer(aid) != nil
        return HStack(alignment: .top, spacing: 10) {
            if loading { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 4) {
                if !aid.isConnected {
                    Text(L("%@ is disconnected.", L(aid.sideLabel))).foregroundStyle(.secondary)
                } else if loading {
                    Text(L("Loading %@ EQ…", L(aid.sideLabel)))
                    Text(L("Reading current EQ settings…")).foregroundStyle(.secondary)
                } else if case .failed(let error) = status {
                    Text(L("Could not load %@ EQ.", L(aid.sideLabel))).foregroundStyle(.orange)
                    Text(M(error)).foregroundStyle(.secondary)
                } else if hasEQ {
                    Label(L("%@ EQ loaded", L(aid.sideLabel)), systemImage: "checkmark.circle").foregroundStyle(.secondary)
                } else if status == .loaded {
                    Text(L("This equalizer was not reported by the hearing aid.")).foregroundStyle(.secondary)
                } else { Text(L("%@ EQ is not loaded.", L(aid.sideLabel))).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !loading && !store.isDemo {
                Button(hasEQ ? L("Refresh") : L("Retry")) {
                    store.loadEqualizersIfNeeded([aid.id], microphone: microphone, retry: true)
                }.disabled(!aid.isConnected)
                    .accessibilityIdentifier("\(source)-eq-retry-\(aid.sideLabel.lowercased())")
            }
        }.font(AppType.caption)
    }

    private func editor(_ aid: AidConnection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L(title), systemImage: "slider.vertical.3").font(AppType.callout.weight(.semibold))
                Spacer()
                if aid.advancedBusy { ProgressView().controlSize(.mini) }
            }
            if let eq = equalizer(aid) {
                if detailed {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(0..<8, id: \.self) { band in
                            VStack(spacing: 12) {
                                Text(bandLabel(aid, band: band)).font(AppType.caption.weight(.medium)).lineLimit(2)
                                if let bounds = range(aid, band: band), bounds.lowerBound < bounds.upperBound {
                                    Text(bounds.upperBound, format: .number.precision(.fractionLength(0...1))).font(AppType.small).foregroundStyle(.secondary)
                                    NativeEqualizerSlider(value: displayedValue(aid, band: band), range: bounds, step: eq.stepDB,
                                        enabled: ready(aid) && !store.isDemo,
                                        label: L("%@ %@ EQ · %@", L(aid.sideLabel), L(source), bandLabel(aid, band: band)),
                                        change: { edit(aid, band: band, value: $0) })
                                        .frame(width: 34, height: 190).disabled(!ready(aid) || store.isDemo)
                                    Text(bounds.lowerBound, format: .number.precision(.fractionLength(0...1))).font(AppType.small).foregroundStyle(.secondary)
                                } else { Text(unavailableBandLabel(aid)).font(AppType.caption).foregroundStyle(.secondary).frame(height: 230) }
                                Text(displayedValue(aid, band: band), format: .number.precision(.fractionLength(1)).sign(strategy: .always()))
                                    .font(AppType.callout.monospacedDigit())
                                Text("dB").font(AppType.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity)
                        }
                    }.padding(.vertical, 14)
                } else { ForEach(0..<3, id: \.self) { band in
                    HStack(spacing: 8) {
                        Text(bandLabel(aid, band: band)).font(AppType.callout).frame(width: 72, alignment: .leading)
                        if let bounds = range(aid, band: band), bounds.lowerBound < bounds.upperBound {
                            Slider(value: Binding(get: { min(bounds.upperBound, max(bounds.lowerBound, displayedValue(aid, band: band))) },
                                                  set: { edit(aid, band: band, value: $0) }),
                                   in: bounds, step: eq.stepDB)
                                .disabled(!ready(aid))
                                .accessibilityLabel(L("%@ %@ EQ · %@", L(aid.sideLabel), L(source), bandLabel(aid, band: band)))
                        } else {
                            Text(unavailableBandLabel(aid)).font(AppType.small).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        }
                        Text(displayedValue(aid, band: band), format: .number.precision(.fractionLength(1)).sign(strategy: .always()))
                            .font(AppType.caption.monospacedDigit()).frame(width: 34, alignment: .trailing)
                        Text("dB").font(AppType.small).foregroundStyle(.secondary)
                    }
                } }
                HStack(spacing: 8) {
                    Button(L("Reset EQ…")) { resetIDs = targets(aid).map(\.id) }
                        .disabled(!ready(aid) || (try? ConsumerControlPlan(aids: targets(aid), change: .restore(microphone ? .microphone : .streaming))) == nil)
                        .accessibilityLabel(L("Restore %@ %@ EQ%@", L(aid.sideLabel), L(source), String(describing: linked ? L(" for both ears") : "")))
                    Spacer(minLength: 0)
                    Button(appliesToBoth ? L("Apply to both") : L("Apply")) {
                        store.setEqualizerChannels(targets(aid).map(\.id), microphone: microphone, levelsByAid: requestedLevels(aid))
                        for target in targets(aid) { drafts[target.id, microphone: microphone] = nil }
                    }.buttonStyle(.borderedProminent).font(AppType.body).disabled(!canApply(aid))
                        .accessibilityLabel(L("Apply %@ %@ equalizer%@", L(aid.sideLabel), L(source), String(describing: linked ? L(" to both ears") : "")))
                }.font(AppType.caption)
                if drafts[aid.id, microphone: microphone] != nil {
                    Button(L("Discard edits")) { for target in targets(aid) { drafts[target.id, microphone: microphone] = nil } }
                        .buttonStyle(.borderless).font(AppType.caption)
                        .accessibilityLabel(L("Discard %@ %@ EQ edits", L(aid.sideLabel), L(source)))
                }
                if !eq.rangesReportedByDevice {
                    Text(L("Companion consumer limits")).font(AppType.small).foregroundStyle(.tertiary)
                }
                if detailed {
                    Text(eq.frequenciesHz == nil
                         ? L("Numbered bands follow device order. This aid has not reported frequency labels.")
                         : L("Frequencies reported by this hearing aid. These are consumer EQ adjustments."))
                        .font(AppType.small).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(L("EQ controls appear after the hearing aid finishes loading.")).font(AppType.caption).foregroundStyle(.secondary)
            }
            if appliesToBoth && requestedAids.contains(where: { equalizer($0) == nil }) {
                Text(L("Both ears becomes available when each EQ has finished loading."))
                    .font(AppType.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func unavailableBandLabel(_ aid: AidConnection) -> String {
        if targets(aid).contains(where: { equalizer($0) == nil }) {
            return targets(aid).contains(where: { loader.states[$0.id]?.status.isLoading == true }) ? L("Loading…") : L("Unavailable")
        }
        return L("Fixed")
    }

    private func bandLabel(_ aid: AidConnection, band: Int) -> String {
        guard detailed else { return [L("Lows"), L("Mids"), L("Highs")][band] }
        guard let frequencies = equalizer(aid)?.frequenciesHz else { return L("Band %d", band + 1) }
        let hz = frequencies[band]
        let value = (hz >= 1000 ? hz / 1000 : hz).formatted(.number.precision(.fractionLength(0...1)))
        return hz >= 1000 ? L("%@ kHz", value) : L("%@ Hz", value)
    }
}
