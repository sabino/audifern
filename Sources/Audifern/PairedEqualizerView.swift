import CompanionCore
import SwiftUI

/// Both ears remain visible. Faders edit local drafts; only Apply owns transport.
struct PairedEqualizerView: View {
    @ObservedObject var store: BluetoothStore
    let aids: [AidConnection]
    let microphone: Bool
    @Binding var linked: Bool
    let canLink: Bool
    var compact: Bool
    var detailPreference: Binding<Bool>?
    var faderHeight: CGFloat
    @EnvironmentObject private var drafts: EqualizerDraftStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var loader: EqualizerLoader
    @State private var resetIDs: [UUID] = []
    @State private var detailed: Bool
    private var detailSelection: Binding<Bool> { detailPreference ?? $detailed }
    private var showsDetailed: Bool { detailSelection.wrappedValue }
    private var appliesToBoth: Bool { linked && aids.count == 2 }

    init(store: BluetoothStore, aids: [AidConnection], microphone: Bool, linked: Binding<Bool>,
         canLink: Bool, detailed: Bool = false, compact: Bool = false, faderHeight: CGFloat = 144, detailPreference: Binding<Bool>? = nil) {
        self.store = store; self.aids = aids; self.microphone = microphone
        loader = store.equalizerLoader
        _linked = linked; self.canLink = canLink; _detailed = State(initialValue: detailed)
        self.detailPreference = detailPreference
        self.compact = compact; self.faderHeight = faderHeight
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
    // Separate also reads both ears. Changing grouping never cancels a read.
    private var loadContext: [EqualizerLoader.Context] {
        aids.filter(\.isConnected).map { .init(id: $0.id, connectedAt: $0.connectedAt, program: $0.activeProgram) }
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
        return showsDetailed ? levels[band] : OticonEqualizer.groups[band].map { levels[$0] }.min()!
    }
    private func mixedValue(_ aid: AidConnection, band: Int) -> Bool {
        let levels = targets(aid).map { displayedValue($0, band: band) }
        return levels.first.map { first in levels.contains { abs($0 - first) > 0.0001 } } ?? false
    }
    private func range(_ aid: AidConnection, band: Int) -> ClosedRange<Double>? {
        let eqs = targets(aid).compactMap(equalizer)
        guard eqs.count == targets(aid).count,
              let lower = eqs.map({ (showsDetailed ? $0.channelRangesDB : $0.threeBandRangesDB)[band].lowerBound }).max(),
              let upper = eqs.map({ (showsDetailed ? $0.channelRangesDB : $0.threeBandRangesDB)[band].upperBound }).min(), lower <= upper else { return nil }
        return lower...upper
    }
    private func ready(_ aid: AidConnection) -> Bool {
        targets(aid).allSatisfy { microphone ? $0.canChangeMicrophoneEqualizer : $0.canChangeStreamingEqualizer }
            && targets(aid).allSatisfy { loader.states[$0.id]?.status.isLoading != true }
            && !store.linkedActionPending && (!appliesToBoth || (canLink && !frequencyLayoutsConflict))
    }
    private func hasDraft(_ aid: AidConnection) -> Bool {
        drafts.hasChanges(for: targets(aid), microphone: microphone)
    }
    private func canApply(_ aid: AidConnection) -> Bool {
        hasDraft(aid) && ready(aid)
            && (try? ConsumerControlPlan(aids: targets(aid), change: .equalizerChannels(microphone: microphone, levelsByAid: requestedLevels(aid)))) != nil
    }
    private func edit(_ aid: AidConnection, band: Int, value: Double) {
        drafts.editChannels(targets(aid), microphone: microphone,
            channels: showsDetailed ? [band] : Array(OticonEqualizer.groups[band]), value: value)
    }

    var body: some View {
        VStack(spacing: compact ? 8 : 14) {
            SoundSectionHeader {
                EmptyView()
            } center: {
                if aids.count == 2 {
                    EarControlModePicker(together: $linked, available: canLink && !frequencyLayoutsConflict,
                                         scope: L(title), identifier: "\(source)-eq-mode")
                }
            } trailing: {
                ViewThatFits(in: .horizontal) {
                    detailPicker.pickerStyle(.segmented).tint(Brand.controlTint).fixedSize()
                    detailPicker.pickerStyle(.menu).frame(width: 174)
                }.frame(maxWidth: .infinity, alignment: .trailing)
            }
            if appliesToBoth {
                readStatus(aids, suffix: "together").frame(maxWidth: .infinity)
            }
            HStack(alignment: .top, spacing: 20) {
                if appliesToBoth, let aid = aids.first { editor(aid) }
                else { ForEach(aids) { editor($0) } }
            }
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: appliesToBoth)
            if !compact {
                Text(appliesToBoth ? L("≠ means the ears differ. Together keeps existing settings until you edit and Apply.")
                     : microphone ? L("Adjusts sound from the hearing-aid microphones. Apply sends your edits.")
                     : L("Adjusts streamed audio. Apply sends your edits."))
                    .font(AppType.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            }
            if appliesToBoth && frequencyLayoutsConflict {
                Text(L("The aids report different EQ frequency layouts. Adjust each ear separately."))
                    .font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: loadContext, initial: true) { _, contexts in
            store.loadEqualizersIfNeeded(contexts.map(\.id), microphone: microphone)
        }
        .onChange(of: equalizers) { _, _ in
            // App-lifetime reconciliation invalidates only the aid whose
            // program/capability changed, preserving the other ear's draft.
            store.loadEqualizersIfNeeded(loadContext.map(\.id), microphone: microphone)
        }
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

    private var detailPicker: some View {
        Picker(L("EQ detail"), selection: detailSelection) {
            Text(L("Tone controls")).tag(false)
            Text(L("8 bands")).tag(true)
        }.labelsHidden().font(AppType.caption).controlSize(.regular)
            .accessibilityIdentifier("\(source)-eq-detail")
    }

    private func editor(_ aid: AidConnection) -> some View {
        VStack(spacing: compact ? 6 : 12) {
            if !appliesToBoth {
                HStack(spacing: 8) {
                    Text(L(aid.sideLabel)).font(AppType.callout.weight(.semibold))
                    readStatus([aid], suffix: aid.sideLabel.lowercased())
                    Spacer(minLength: 0)
                    Text("dB").font(AppType.small).foregroundStyle(.tertiary)
                }.frame(height: 24)
            }
            GeometryReader { geometry in
                let count = showsDetailed ? 8 : 3
                let gap: CGFloat = showsDetailed ? 4 : 16
                let width = max(0, (geometry.size.width - CGFloat(count - 1) * gap) / CGFloat(count))
                HStack(alignment: .top, spacing: gap) {
                    ForEach(0..<count, id: \.self) { band in
                        bandControl(aid, band: band).frame(width: width)
                    }
                }
            }.frame(height: compact ? faderHeight + 84 : faderHeight + 132)
            HStack(spacing: 8) {
                if compact && hasDraft(aid) { discardButton(aid) }
                Spacer(minLength: 0)
                Button(L("Reset EQ…")) { resetIDs = targets(aid).map(\.id) }
                    .disabled(!ready(aid) || (try? ConsumerControlPlan(aids: targets(aid), change: .restore(microphone ? .microphone : .streaming))) == nil)
                    .accessibilityLabel(L("Restore %@ %@ EQ%@", L(aid.sideLabel), L(source), String(describing: appliesToBoth ? L(" for both ears") : "")))
                    .accessibilityIdentifier("\(source)-eq-reset-\(appliesToBoth ? "together" : aid.sideLabel.lowercased())")
                Button(L("Apply")) {
                    store.setEqualizerChannels(targets(aid).map(\.id), microphone: microphone, levelsByAid: requestedLevels(aid))
                    for target in targets(aid) { drafts[target.id, microphone: microphone] = nil }
                }.buttonStyle(.borderedProminent).tint(Brand.controlTint).disabled(!canApply(aid))
                    .accessibilityLabel(L("Apply %@ %@ equalizer%@", L(aid.sideLabel), L(source), String(describing: appliesToBoth ? L(" to both ears") : "")))
                    .accessibilityIdentifier("\(source)-eq-apply-\(appliesToBoth ? "together" : aid.sideLabel.lowercased())")
            }.font(AppType.caption).controlSize(.regular)
            if !compact {
                Group {
                    if hasDraft(aid) { discardButton(aid) }
                    else { Text(" ").font(AppType.caption).accessibilityHidden(true) }
                }.frame(height: 22)
                if let eq = equalizer(aid), !eq.rangesReportedByDevice {
                    Text(L("Companion consumer limits")).font(AppType.small).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(compact ? 10 : 12).frame(maxWidth: .infinity)
        .background(Brand.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Brand.accent.opacity(0.09)))
        .overlay(alignment: .topTrailing) {
            if appliesToBoth { Text("dB").font(AppType.small).foregroundStyle(.tertiary).padding(10) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(source)-eq-editor-\(appliesToBoth ? "together" : aid.sideLabel.lowercased())")
    }

    private func bandControl(_ aid: AidConnection, band: Int) -> some View {
        VStack(spacing: compact ? 4 : 8) {
            Text(showsDetailed && equalizer(aid)?.frequenciesHz == nil ? String(band + 1) : bandLabel(aid, band: band))
                .font(showsDetailed ? AppType.small : AppType.callout.weight(.medium))
                .multilineTextAlignment(.center).lineLimit(1).frame(height: compact ? 20 : 36)
            if let eq = equalizer(aid), let bounds = range(aid, band: band), bounds.lowerBound < bounds.upperBound {
                Text(bounds.upperBound, format: .number.precision(.fractionLength(0...1)))
                    .font(AppType.small.monospacedDigit()).foregroundStyle(.tertiary)
                NativeEqualizerSlider(value: displayedValue(aid, band: band), range: bounds, step: eq.stepDB,
                    enabled: ready(aid) && !store.isDemo,
                    label: L("%@ %@ EQ · %@", appliesToBoth ? L("Together") : L(aid.sideLabel), L(source), bandLabel(aid, band: band)),
                    change: { edit(aid, band: band, value: $0) })
                    .frame(width: showsDetailed ? 28 : 34, height: faderHeight)
                    .accessibilityIdentifier("\(source)-eq-band-\(appliesToBoth ? "together" : aid.sideLabel.lowercased())-\(band)")
                Text(bounds.lowerBound, format: .number.precision(.fractionLength(0...1)))
                    .font(AppType.small.monospacedDigit()).foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 8) {
                    Rectangle().fill(.quaternary).frame(width: 3, height: faderHeight)
                    Text(equalizer(aid) == nil ? L("Loading…") : L("Fixed")).font(AppType.small).foregroundStyle(.secondary)
                }.frame(height: faderHeight + 44)
            }
            if equalizer(aid) == nil { Text("—").font(AppType.caption).foregroundStyle(.secondary) }
            else if mixedValue(aid, band: band) { Text("≠").font(AppType.callout).foregroundStyle(.secondary).accessibilityLabel(L("Mixed")) }
            else {
                Text(displayedValue(aid, band: band), format: .number.precision(.fractionLength(1)).sign(strategy: .always()))
                    .font(showsDetailed ? AppType.small.monospacedDigit() : AppType.callout.monospacedDigit())
                    .foregroundStyle(hasDraft(aid) ? Brand.accent : .primary)
            }
        }.frame(maxWidth: .infinity)
            .help(targets(aid).map { L("%@ · %@ dB", L($0.sideLabel), displayedValue($0, band: band).formatted(.number.precision(.fractionLength(1)))) }.joined(separator: "\n"))
    }

    private func discardButton(_ aid: AidConnection) -> some View {
        Button(L("Discard edits")) { for target in targets(aid) { drafts[target.id, microphone: microphone] = nil } }
            .buttonStyle(.borderless).font(AppType.small)
            .accessibilityLabel(L("Discard %@ %@ EQ edits", L(aid.sideLabel), L(source)))
    }

    private func readStatus(_ targets: [AidConnection], suffix: String) -> some View {
        EqualizerReadStatusView(summary: .init(aids: targets, microphone: microphone, states: loader.states),
            identifier: "\(source)-eq-retry-\(suffix)", allowsRefresh: !store.isDemo, canRefresh: targets.contains(where: \.isConnected)) {
                store.loadEqualizersIfNeeded(targets.map(\.id), microphone: microphone, retry: true)
            }
    }
    private func bandLabel(_ aid: AidConnection, band: Int) -> String {
        guard showsDetailed else { return [L("Lows"), L("Mids"), L("Highs")][band] }
        guard let frequencies = equalizer(aid)?.frequenciesHz else { return L("Band %d", band + 1) }
        let hz = frequencies[band]
        let value = (hz >= 1000 ? hz / 1000 : hz).formatted(.number.precision(.fractionLength(0...1)))
        return hz >= 1000 ? L("%@ kHz", value) : L("%@ Hz", value)
    }
}
