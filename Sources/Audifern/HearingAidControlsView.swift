import CompanionCore
import SwiftUI

/// Advanced sound and fitted-program controls. Daily volume lives in Listen.
struct HearingAidControlsView: View {
    enum Mode { case sound, programs }
    @ObservedObject var store: BluetoothStore
    var mode: Mode = .sound
    @EnvironmentObject private var preferences: AppPreferences
    @AppStorage("linkedHearingAidPrograms") private var linkedPrograms = false
    @AppStorage("linkedHearingAidMicrophoneEQ") private var linkedMicrophone = false
    @AppStorage("linkedHearingAidStreamingEQ") private var linkedStreaming = false
    @AppStorage("linkedHearingAidStreamingVolume") private var linkedStreamingVolume = false
    @AppStorage("linkedHearingAidTinnitusVolume") private var linkedTinnitusVolume = false
    @State private var showStreamingVolume = false
    @State private var showTinnitus = false
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
        VStack(alignment: .leading, spacing: 24) {
            if aids.count == 2 {
                Surface {
                    VStack(spacing: 22) {
                        EarSettingsRow { sideHeading(aids[0]) } center: { EmptyView() } right: { sideHeading(aids[1]) }
                        Divider()
                        if mode == .programs {
                            EarSettingsRow {
                                program(aids[0], ids: linkedPrograms && canLink ? aids.map(\.id) : [aids[0].id])
                            } center: {
                                EarLinkButton(title: "Program", linked: $linkedPrograms, available: canLink && !commonPrograms(aids).isEmpty, identifier: "link-program", accent: Brand.accent)
                            } right: {
                                program(aids[1], ids: linkedPrograms && canLink ? aids.map(\.id) : [aids[1].id])
                            }
                        } else {
                            PairedEqualizerView(store: store, aids: aids, microphone: true, linked: $linkedMicrophone, canLink: canLink)
                            Divider()
                            DisclosureGroup(L("Streaming-source volume"), isExpanded: $showStreamingVolume) {
                                AuxiliaryVolumeSectionView(store: store, aids: aids, source: .streaming, linked: $linkedStreamingVolume).padding(.top, 12)
                            }
                            PairedEqualizerView(store: store, aids: aids, microphone: false, linked: $linkedStreaming, canLink: canLink)
                            Divider()
                            DisclosureGroup(isExpanded: $showTinnitus) {
                                AuxiliaryVolumeSectionView(store: store, aids: aids, source: .tinnitus, linked: $linkedTinnitusVolume).padding(.top, 12)
                            } label: { Label(L("Tinnitus relief"), systemImage: "waveform.path").foregroundStyle(.orange).font(.headline) }
                            Text(L("Tinnitus controls require a program already fitted for you. Reported ranges alone do not enable therapy."))
                                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                            HStack {
                                Text(L("Restores consumer adjustments. Your fitted programs stay unchanged.")).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button(L("Restore both ears…"), systemImage: "arrow.counterclockwise") {
                                    restoreRequest = .init(ids: aids.map(\.id), target: L("Both ears"), scope: .all)
                                }.disabled(!canRestore(aids.map(\.id), scope: .all)).accessibilityIdentifier("restore-both-ears")
                            }
                            EarSettingsRow { restoreMenu(aids[0]) } center: { EmptyView() } right: { restoreMenu(aids[1]) }
                        }
                    }
                }
            } else {
                ForEach(aids) { aid in
                    Surface {
                        VStack(alignment: .leading, spacing: 20) {
                            sideHeading(aid)
                            if mode == .programs { program(aid, ids: [aid.id]) }
                            else {
                                EqualizerControlsView(store: store, aidID: aid.id)
                                AuxiliaryVolumeSectionView(store: store, aids: [aid], source: .streaming, linked: .constant(false))
                                AuxiliaryVolumeSectionView(store: store, aids: [aid], source: .tinnitus, linked: .constant(false))
                                restoreMenu(aid)
                            }
                        }
                    }
                }
            }
            if let status = store.linkedActionStatus {
                Label(M(status), systemImage: store.linkedActionFailed ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.caption).foregroundStyle(store.linkedActionFailed ? Color.orange : .secondary)
            }
        }
        .alert(L("Restore sound defaults?"), isPresented: Binding(get: { restoreRequest != nil }, set: { if !$0 { restoreRequest = nil } }), presenting: restoreRequest) { request in
            Button(L("Restore defaults")) { store.restoreSoundDefaults(request.ids, scope: request.scope); restoreRequest = nil }
            Button(L("Cancel"), role: .cancel) { restoreRequest = nil }
        } message: { request in
            Text(L("%@. %@ Your fitted programs and audiogram are preserved.", request.target, L(request.scope.explanation)))
        }
    }
    private func sideHeading(_ aid: AidConnection) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(L(aid.sideLabel), systemImage: "ear").font(.headline)
            Text(aid.activeProgramName ?? L("Program not read")).font(.callout).foregroundStyle(.secondary)
            if let status = aid.advancedStatus, aid.advancedBusy { Text(M(status)).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func canRestore(_ ids: [UUID], scope: ConsumerControlPlan.ResetScope) -> Bool {
        let targets = ids.compactMap { store.connections[$0] }
        return targets.count == ids.count && !store.linkedActionPending && (try? ConsumerControlPlan(aids: targets, change: .restore(scope))) != nil
    }
    private func restoreMenu(_ aid: AidConnection) -> some View {
        Menu {
            ForEach(ConsumerControlPlan.ResetScope.allCases) { scope in
                if scope == .all { Divider() }
                Button(L(scope.label)) { restoreRequest = .init(ids: [aid.id], target: L(aid.sideLabel), scope: scope) }
                    .disabled(!canRestore([aid.id], scope: scope))
            }
        } label: { Label(L("Restore %@…", L(aid.sideLabel)), systemImage: "arrow.counterclockwise") }
            .menuStyle(.borderlessButton).font(.caption).fixedSize()
    }
    private func commonPrograms(_ targets: [AidConnection]) -> [Int] {
        guard targets.count == 2 else { return [] }
        return targets[0].programIDs.filter { id in
            targets[1].programIDs.contains(id) && targets[0].programNames[id] != nil && targets[0].programNames[id] == targets[1].programNames[id]
        }
    }
    private func program(_ aid: AidConnection, ids: [UUID]) -> some View {
        let targets = ids.compactMap { store.connections[$0] }
        let programs = ids.count == 2 ? commonPrograms(targets) : aid.programIDs
        return VStack(alignment: .leading, spacing: 9) {
            Text(L("Fitted program")).font(.callout.weight(.medium))
            if let active = aid.activeProgram {
                Picker(L("%@ program", L(aid.sideLabel)), selection: Binding(get: { active }, set: { store.selectPrograms(ids, program: $0) })) {
                    ForEach(programs, id: \.self) { id in Text(aid.programNames[id] ?? L("Program %d", id + 1)).tag(id) }
                    if !programs.contains(active) { Text(aid.activeProgramName ?? L("Current program")).tag(active) }
                }.labelsHidden().disabled(programs.count < 2 || !targets.allSatisfy(\.canChangeProgram))
                if programs.count == 1 { Text(L("One program is fitted on this aid.")).font(.caption).foregroundStyle(.secondary) }
            } else { Text(L("Not loaded")).font(.caption).foregroundStyle(.secondary) }
            Button(L("Read program names")) { store.refreshProgramInfo(aid.id) }
                .font(.caption).buttonStyle(.borderless).disabled(!aid.isConnected || aid.actionPending || aid.advancedBusy || aid.groupActionPending || store.isDemo)
        }.frame(maxWidth: .infinity, alignment: .leading)
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

struct EarLinkButton: View {
    @EnvironmentObject private var preferences: AppPreferences
    let title: String
    @Binding var linked: Bool
    var available: Bool
    let identifier: String
    var accent: Color = .teal
    var body: some View {
        Button { linked.toggle() } label: {
            VStack(spacing: 5) {
                Image(systemName: linked ? "link" : "link.badge.plus")
                    .font(.system(size: 16, weight: .semibold)).frame(width: 38, height: 30)
                    .background(linked ? accent.opacity(0.14) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                Text(linked ? L("Linked") : L("Separate")).font(.system(size: 9, weight: .medium))
            }.foregroundStyle(linked ? accent : Color.secondary)
        }.buttonStyle(.plain).disabled(!available)
            .accessibilityLabel(L("Link %@ between ears", String(describing: title.lowercased())))
            .accessibilityValue(linked ? L("Linked") : L("Separate"))
            .accessibilityIdentifier(identifier)
            .help(available ? L("%@ %@. Current sound stays unchanged until you use a control.", String(describing: linked ? L("Unlink") : L("Link")), String(describing: title.lowercased()))
                  : L("Connect both matching aids to link this setting"))
    }
}

struct VolumeButtonsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @ObservedObject var store: BluetoothStore
    let aid: AidConnection
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("Volume and mute"), systemImage: "speaker.wave.2").font(.callout.weight(.medium))
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
            }.buttonStyle(.bordered)
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
            Text(L(aid.sideLabel)).font(.callout.weight(.medium))
            Toggle(L("Speech boost"), isOn: Binding(get: { aid.speechBoosterEnabled ?? false }, set: { store.setSpeechBoosters(targetIDs, enabled: $0) }))
                .toggleStyle(.switch).disabled(!canChange)
                .accessibilityLabel(L("%@ SpeechBooster%@", L(aid.sideLabel), String(describing: targetIDs.count == 2 ? L(", changes both ears") : "")))
            if aid.speechBoosterEnabled == nil {
                Button(L("Load SpeechBooster")) { store.refreshConsumerFeatures(aid.id) }.buttonStyle(.borderless)
                    .disabled(!aid.isConnected || aid.actionPending || aid.advancedBusy || aid.groupActionPending)
                    .accessibilityLabel(L("Load %@ SpeechBooster", L(aid.sideLabel)))
            } else if aid.activeProgram.flatMap({ aid.programBoostable[$0] }) == false {
                Text(L("Unavailable in this program")).foregroundStyle(.secondary)
            } else if let status = aid.consumerStatus { Text(M(status)).foregroundStyle(.secondary) }
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
    }
}
