import CompanionCore
import SwiftUI

/// Consumer equalizers and fitted-program selection. Daily volume lives in Sound.
struct HearingAidControlsView: View {
    enum Mode { case sound, programs }
    @ObservedObject var store: BluetoothStore
    var mode: Mode = .sound
    var embedded = false
    var faderHeight: CGFloat = 144
    @AppStorage("microphoneEqualizerDetailed") private var microphoneDetailed = false
    @AppStorage("streamingEqualizerDetailed") private var streamingDetailed = false
    @EnvironmentObject private var preferences: AppPreferences
    @AppStorage("groupedEqualizerControls") private var grouped = true
    @AppStorage("groupedProgramControls") private var programsGrouped = true
    @AppStorage("groupedStreamingControls") private var streamingGrouped = true
    @AppStorage("groupedTinnitusControls") private var tinnitusGrouped = true
    enum SoundSection: String, CaseIterable, Identifiable {
        case microphone, streaming, streamingVolume, tinnitus
        var id: String { rawValue }
        var title: String {
            switch self {
            case .microphone: L("Microphone")
            case .streaming: L("Streaming")
            case .streamingVolume: L("Source volume")
            case .tinnitus: L("Tinnitus relief")
            }
        }
    }
    @AppStorage("equalizerSoundSection") private var soundSection: SoundSection = .microphone
    @State private var restoreRequest: RestoreRequest?
    private struct RestoreRequest: Identifiable {
        let id = UUID()
        let ids: [UUID]
        let target: String
        let scope: ConsumerControlPlan.ResetScope
    }
    private var aids: [AidConnection] {
        store.orderedConnections.sorted { $0.sideLabel == "Left" && $1.sideLabel != "Left" }
    }
    private var canLink: Bool { aids.count == 2 && Set(aids.map(\.id)) == Set(store.connectedPair.map(\.id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: embedded ? 4 : 20) {
            if mode == .sound {
                if embedded {
                    HStack(spacing: 16) {
                        Label(L("Equalizers"), systemImage: "slider.vertical.3").font(AppType.headline).fixedSize()
                        Spacer(minLength: 0)
                        ViewThatFits(in: .horizontal) {
                            sourcePicker.pickerStyle(.segmented).tint(Brand.controlTint).fixedSize()
                            sourcePicker.pickerStyle(.menu).frame(width: 200)
                        }.frame(maxWidth: 520, alignment: .trailing)
                    }.frame(height: 32)
                } else { sourcePicker.pickerStyle(.segmented).tint(Brand.controlTint) }
            }
            controlsContainer {
                VStack(spacing: embedded ? 8 : 22) {
                    if mode == .programs && aids.count == 2 {
                        EarSettingsRow { sideHeading(aids[0]) } center: { EmptyView() } right: { sideHeading(aids[1]) }
                    } else if mode == .programs, let aid = aids.first { sideHeading(aid) }
                    if mode == .programs { Divider() }
                    if mode == .programs {
                        if aids.count == 2 {
                            EarControlModePicker(together: $programsGrouped, available: canLink && !commonPrograms(aids).isEmpty,
                                                 scope: L("Listening program"), identifier: "link-program")
                            EarSettingsRow {
                                ProgramSelectionView(store: store, aid: aids[0], targetIDs: programsGrouped && canLink ? aids.map(\.id) : [aids[0].id])
                            } center: {
                                EmptyView()
                            } right: {
                                ProgramSelectionView(store: store, aid: aids[1], targetIDs: programsGrouped && canLink ? aids.map(\.id) : [aids[1].id])
                            }
                        } else if let aid = aids.first {
                            ProgramSelectionView(store: store, aid: aid, targetIDs: [aid.id])
                        }
                    } else {
                        switch soundSection {
                        case .microphone:
                            PairedEqualizerView(store: store, aids: aids, microphone: true, linked: $grouped, canLink: canLink, compact: embedded, faderHeight: faderHeight, detailPreference: embedded ? $microphoneDetailed : nil)
                        case .streaming:
                            PairedEqualizerView(store: store, aids: aids, microphone: false, linked: $streamingGrouped, canLink: canLink, compact: embedded, faderHeight: faderHeight, detailPreference: embedded ? $streamingDetailed : nil)
                        case .streamingVolume:
                            AuxiliaryVolumeSectionView(store: store, aids: aids, source: .streaming,
                                                       linked: $streamingGrouped, compact: embedded)
                        case .tinnitus:
                            AuxiliaryVolumeSectionView(store: store, aids: aids, source: .tinnitus,
                                                       linked: $tinnitusGrouped, compact: embedded)
                        }
                    }
                }
            }
            statusLine
            if mode == .sound && embedded {
                Divider().padding(.top, 2)
                HStack(spacing: 12) {
                    Label(L("Restore sound defaults"), systemImage: "arrow.counterclockwise")
                        .font(AppType.caption.weight(.semibold)).lineLimit(1)
                        .help(L("Restores consumer adjustments. Your fitted programs stay unchanged."))
                    Spacer(minLength: 0)
                    ForEach(aids) { restoreMenu($0, compact: true) }
                    if aids.count == 2 { restoreBothButton }
                }.font(AppType.caption).controlSize(.regular).frame(height: 32)
                    .accessibilityIdentifier("sound-restore-defaults")
            } else if mode == .sound {
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(L("Restore sound defaults"), systemImage: "arrow.counterclockwise").font(AppType.headline)
                                Text(L("Restores consumer adjustments. Your fitted programs stay unchanged.")).font(AppType.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if aids.count == 2 { restoreBothButton }
                        }
                        HStack {
                            ForEach(aids) { aid in restoreMenu(aid); Spacer(minLength: 0) }
                        }
                    }
                }
            }
        }
        .alert(L("Restore sound defaults?"), isPresented: Binding(get: { restoreRequest != nil }, set: { if !$0 { restoreRequest = nil } }), presenting: restoreRequest) { request in
            Button(L("Restore defaults")) { store.restoreSoundDefaults(request.ids, scope: request.scope); restoreRequest = nil }
            Button(L("Cancel"), role: .cancel) { restoreRequest = nil }
        } message: { request in
            Text(L("%@. %@ Your fitted programs and audiogram are preserved.", request.target, L(request.scope.explanation)))
        }
    }
    private var sourcePicker: some View {
        Picker(L("Sound source"), selection: $soundSection) {
            ForEach(SoundSection.allCases) { Text($0.title).tag($0) }
        }.labelsHidden().font(AppType.caption).controlSize(.regular)
            .accessibilityIdentifier("equalizer-source")
    }
    private var statusLine: some View {
        Text(store.linkedActionStatus.map(M) ?? L("EQ changes remain a draft until you choose Apply."))
            .font(AppType.caption).foregroundStyle(store.linkedActionFailed ? Color.orange : .secondary)
            .lineLimit(embedded ? 1 : 2).help(store.linkedActionStatus.map(M) ?? L("EQ changes remain a draft until you choose Apply."))
            .frame(maxWidth: .infinity, minHeight: embedded ? 18 : 34, maxHeight: embedded ? 18 : 34, alignment: .leading)
    }
    private var restoreBothButton: some View {
        Button(L("Restore both ears…")) {
            restoreRequest = .init(ids: aids.map(\.id), target: L("Both ears"), scope: .all)
        }.disabled(!canRestore(aids.map(\.id), scope: .all)).accessibilityIdentifier("restore-both-ears")
    }
    @ViewBuilder private func controlsContainer<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        if embedded { content() }
        else { Surface { content() } }
    }
    private func sideHeading(_ aid: AidConnection) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(L(aid.sideLabel), systemImage: "ear").font(AppType.headline)
            Text(aid.activeProgramName ?? L("Program not read")).font(AppType.callout).foregroundStyle(.secondary)
            if let status = aid.advancedStatus, aid.advancedBusy { Text(M(status)).font(AppType.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func canRestore(_ ids: [UUID], scope: ConsumerControlPlan.ResetScope) -> Bool {
        let targets = ids.compactMap { store.connections[$0] }
        return targets.count == ids.count && !store.linkedActionPending && (try? ConsumerControlPlan(aids: targets, change: .restore(scope))) != nil
    }
    private func restoreMenu(_ aid: AidConnection, compact: Bool = false) -> some View {
        Menu {
            ForEach(ConsumerControlPlan.ResetScope.allCases) { scope in
                if scope == .all { Divider() }
                Button(L(scope.label)) { restoreRequest = .init(ids: [aid.id], target: L(aid.sideLabel), scope: scope) }
                    .disabled(!canRestore([aid.id], scope: scope))
            }
        } label: { Text(compact ? L(aid.sideLabel) : L("Restore %@…", L(aid.sideLabel))) }
            .font(AppType.caption).fixedSize()
            .accessibilityLabel(L("Restore %@…", L(aid.sideLabel)))
    }
    private func commonPrograms(_ targets: [AidConnection]) -> [Int] {
        guard targets.count == 2 else { return [] }
        return targets[0].programIDs.filter { id in
            targets[1].programIDs.contains(id) && targets[0].programNames[id] != nil && targets[0].programNames[id] == targets[1].programNames[id]
        }
    }

}

struct EarSettingsRow<Left: View, Center: View, Right: View>: View {
    @ViewBuilder let left: () -> Left
    @ViewBuilder let center: () -> Center
    @ViewBuilder let right: () -> Right
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            left().frame(maxWidth: .infinity)
            center().frame(width: 64).padding(.top, 3)
            right().frame(maxWidth: .infinity)
        }
    }
}

struct VolumeButtonsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @ObservedObject var store: BluetoothStore
    let aid: AidConnection
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("Volume and mute"), systemImage: "speaker.wave.2").font(AppType.callout.weight(.medium))
            HStack(spacing: 8) {
                Button { store.adjustVolume(aid.id, by: -1) } label: { Image(systemName: "minus").frame(maxWidth: .infinity, minHeight: 24) }
                    .disabled(!aid.canChangeVolume || aid.volume?.level == aid.volumeRanges?.main.lowerBound)
                    .accessibilityLabel(L("Decrease %@ microphone level", L(aid.sideLabel)))
                Button { store.setMuted(aid.id, muted: !(aid.volume?.muted ?? false)) } label: {
                    Label(aid.volume?.muted == true ? L("Unmute") : L("Mute"), systemImage: aid.volume?.muted == true ? "speaker.wave.2" : "speaker.slash")
                        .frame(maxWidth: .infinity, minHeight: 24)
                }.disabled(!aid.canChangeVolume)
                    .accessibilityLabel(L("%@ %@ ear", String(describing: aid.volume?.muted == true ? L("Unmute") : L("Mute")), L(aid.sideLabel)))
                Button { store.adjustVolume(aid.id, by: 1) } label: { Image(systemName: "plus").frame(maxWidth: .infinity, minHeight: 24) }
                    .disabled(!aid.canChangeVolume || aid.volume?.level == aid.volumeRanges?.main.upperBound)
                    .accessibilityLabel(L("Increase %@ microphone level", L(aid.sideLabel)))
            }.buttonStyle(.bordered).font(AppType.body)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SpeechBoosterCell: View {
    @EnvironmentObject private var preferences: AppPreferences
    @ObservedObject var store: BluetoothStore
    let aid: AidConnection
    let targetIDs: [UUID]
    private var canChange: Bool {
        let targets = targetIDs.compactMap { store.connections[$0] }
        return targets.count == targetIDs.count && targets.allSatisfy(\.canChangeSpeechBooster) && !store.linkedActionPending
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L(aid.sideLabel)).font(AppType.callout.weight(.medium))
            Toggle(L("Speech boost"), isOn: Binding(get: { aid.speechBoosterEnabled ?? false }, set: { store.setSpeechBoosters(targetIDs, enabled: $0) }))
                .toggleStyle(.switch).labelsHidden().disabled(!canChange)
                .accessibilityLabel(L("%@ SpeechBooster%@", L(aid.sideLabel), String(describing: targetIDs.count == 2 ? L(", changes both ears") : "")))
            SpeechBoosterReadStatusView(store: store, aids: targetIDs.compactMap { store.connections[$0] })
        }.font(AppType.caption).frame(maxWidth: .infinity, minHeight: 94, maxHeight: 94, alignment: .topLeading)
    }
}
