import CompanionCore
import SwiftUI

/// Left and right stay in fixed physical-side columns. Each row has its own
/// link, and linking alone never sends a command to either hearing aid.
struct HearingAidControlsView: View {
    @ObservedObject var store: BluetoothStore
    @EnvironmentObject private var navigation: AppNavigation
    @AppStorage("linkedHearingAidControls") private var linkedVolume = true
    @AppStorage("linkedHearingAidPrograms") private var linkedPrograms = false
    @AppStorage("linkedHearingAidSpeechBooster") private var linkedSpeech = false
    @AppStorage("linkedHearingAidMicrophoneEQ") private var linkedMicrophone = false
    @AppStorage("linkedHearingAidStreamingEQ") private var linkedStreaming = false
    @AppStorage("linkedHearingAidStreamingVolume") private var linkedStreamingVolume = false
    @AppStorage("linkedHearingAidTinnitusVolume") private var linkedTinnitusVolume = false
    @State private var restoreRequest: RestoreRequest?

    private struct RestoreRequest: Identifiable {
        let id = UUID()
        let ids: [UUID]
        let target: String
        let scope: ConsumerControlPlan.ResetScope
    }
    private var physicalPair: [AidConnection]? {
        let aids = store.orderedConnections
        guard aids.count == 2, let left = aids.first(where: { $0.sideLabel == "Left" }),
              let right = aids.first(where: { $0.sideLabel == "Right" }) else { return nil }
        return [left, right]
    }
    private var canLink: Bool {
        guard let pair = physicalPair else { return false }
        return Set(pair.map(\.id)) == Set(store.connectedPair.map(\.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let pair = physicalPair {
                pairedControls(pair)
            } else {
                ForEach(store.orderedConnections) { aid in singleControls(aid) }
            }
            if let status = store.linkedActionStatus {
                HStack(alignment: .top, spacing: 8) {
                    if store.linkedActionPending { ProgressView().controlSize(.mini) }
                    else { Image(systemName: store.linkedActionFailed ? "exclamationmark.circle" : "checkmark.circle") }
                    Text(status).font(.caption).textSelection(.enabled)
                }.foregroundStyle(store.linkedActionFailed ? Color.orange : Color.secondary)
                    .accessibilityIdentifier("sound-change-status")
            }
        }
        .alert("Restore sound defaults?", isPresented: Binding(get: { restoreRequest != nil }, set: { if !$0 { restoreRequest = nil } }), presenting: restoreRequest) { request in
            Button("Restore defaults") { store.restoreSoundDefaults(request.ids, scope: request.scope); restoreRequest = nil }
            Button("Cancel", role: .cancel) { restoreRequest = nil }
        } message: { request in
            Text("\(request.target): \(request.scope.explanation) Your fitted programs and audiogram are preserved.")
        }
    }

    private func pairedControls(_ pair: [AidConnection]) -> some View {
        let left = pair[0], right = pair[1], ids = pair.map(\.id)
        return VStack(spacing: 20) {
            EarSettingsRow {
                portrait(left)
            } center: {
                Text("L / R").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    .padding(.top, 30).accessibilityHidden(true)
            } right: {
                portrait(right)
            }
            Text("Link each setting in the middle. Turning a link on leaves the current sound unchanged.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Divider()
            EarSettingsRow {
                if linkedVolume { volumeReading(left) } else { VolumeButtonsView(store: store, aid: left) }
            } center: {
                EarLinkButton(title: "Volume and mute", linked: $linkedVolume, available: canLink,
                              identifier: "link-volume")
            } right: {
                if linkedVolume { volumeReading(right) } else { VolumeButtonsView(store: store, aid: right) }
            }
            if linkedVolume {
                LinkedControlsView(store: store)
            }
            Divider()
            EarSettingsRow {
                program(left, ids: linkedPrograms && canLink ? ids : [left.id])
            } center: {
                EarLinkButton(title: "Program", linked: $linkedPrograms, available: canLink && !commonPrograms(pair).isEmpty,
                              identifier: "link-program")
            } right: {
                program(right, ids: linkedPrograms && canLink ? ids : [right.id])
            }
            EarSettingsRow {
                SpeechBoosterCell(store: store, aid: left, targetIDs: linkedSpeech && canLink ? ids : [left.id])
            } center: {
                EarLinkButton(title: "SpeechBooster", linked: $linkedSpeech, available: canLink,
                              identifier: "link-speech-booster")
            } right: {
                SpeechBoosterCell(store: store, aid: right, targetIDs: linkedSpeech && canLink ? ids : [right.id])
            }
            Divider()
            PairedEqualizerView(store: store, aids: pair, microphone: true, linked: $linkedMicrophone, canLink: canLink)
            Divider()
            AuxiliaryVolumeSectionView(store: store, aids: pair, source: .streaming, linked: $linkedStreamingVolume)
            PairedEqualizerView(store: store, aids: pair, microphone: false, linked: $linkedStreaming, canLink: canLink)
            AuxiliaryVolumeSectionView(store: store, aids: pair, source: .tinnitus, linked: $linkedTinnitusVolume)
            Divider()
            EarSettingsRow {
                deviceFooter(left)
            } center: {
                Image(systemName: "info.circle").foregroundStyle(.tertiary).accessibilityHidden(true)
            } right: {
                deviceFooter(right)
            }
            Divider()
            HStack {
                Text("Defaults: volume 0 · unmuted · neutral EQ · SpeechBooster off")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Restore both ears…", systemImage: "arrow.counterclockwise") {
                    restoreRequest = .init(ids: ids, target: "Both ears", scope: .all)
                }.disabled(!canRestore(ids, scope: .all))
                    .help("Load both aids’ advanced controls before restoring all sound controls")
                    .accessibilityIdentifier("restore-both-ears")
            }
        }.padding(20)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.06)))
    }

    private func singleControls(_ aid: AidConnection) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            portrait(aid)
            VolumeButtonsView(store: store, aid: aid)
            program(aid, ids: [aid.id])
            SpeechBoosterCell(store: store, aid: aid, targetIDs: [aid.id])
            EqualizerControlsView(store: store, aidID: aid.id)
            AuxiliaryVolumeSectionView(store: store, aids: [aid], source: .streaming, linked: .constant(false))
            AuxiliaryVolumeSectionView(store: store, aids: [aid], source: .tinnitus, linked: .constant(false))
            Divider()
            deviceFooter(aid)
        }.padding(20).frame(maxWidth: 700)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 20))
    }

    private func portrait(_ aid: AidConnection) -> some View {
        let isRight = aid.sideLabel == "Right"
        return VStack(alignment: isRight ? .leading : .trailing, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                if isRight { ear(aid) }
                VStack(alignment: isRight ? .leading : .trailing, spacing: 5) {
                    Text(aid.sideLabel).font(.title3.weight(.semibold))
                    Text(aid.model ?? aid.name).font(.caption).foregroundStyle(.secondary)
                    Text(aid.volume.map { $0.level > 0 ? "+\($0.level)" : String($0.level) } ?? "—")
                        .font(.system(size: 34, weight: .light, design: .rounded)).monospacedDigit()
                    Text(aid.volume.map { $0.muted ? "Muted" : "Sound on" } ?? aid.phase.label)
                        .font(.caption).foregroundStyle(aid.volume?.muted == true ? Color.orange : Color.secondary)
                }.frame(maxWidth: .infinity, alignment: isRight ? .leading : .trailing)
                if !isRight { ear(aid) }
            }
            AidBatteryView(store: store, aid: aid)
                .frame(maxWidth: .infinity, alignment: isRight ? .leading : .trailing)
            restoreMenu(aid)
        }.frame(maxWidth: .infinity)
    }
    private func ear(_ aid: AidConnection) -> some View {
        Image(systemName: "ear").font(.system(size: 62, weight: .ultraLight))
            .foregroundStyle(.teal).frame(width: 78, height: 98)
            .background(Color.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
            .scaleEffect(x: aid.sideLabel == "Right" ? -1 : 1, y: 1)
            .accessibilityLabel("\(aid.sideLabel) ear")
    }
    private func restoreMenu(_ aid: AidConnection) -> some View {
        Menu {
            ForEach(ConsumerControlPlan.ResetScope.allCases) { scope in
                if scope == .all { Divider() }
                Button(scope.label) { restoreRequest = .init(ids: [aid.id], target: aid.sideLabel, scope: scope) }
                    .disabled(!canRestore([aid.id], scope: scope))
            }
        } label: { Label("Restore…", systemImage: "arrow.counterclockwise") }
            .menuStyle(.borderlessButton).fixedSize().font(.caption)
            .accessibilityLabel("Restore \(aid.sideLabel.lowercased()) sound defaults")
    }
    private func canRestore(_ ids: [UUID], scope: ConsumerControlPlan.ResetScope) -> Bool {
        guard !store.linkedActionPending else { return false }
        let aids = ids.compactMap { store.connections[$0] }
        return aids.count == ids.count && (try? ConsumerControlPlan(aids: aids, change: .restore(scope))) != nil
    }
    private func volumeReading(_ aid: AidConnection) -> some View {
        VStack(spacing: 6) {
            Label("Volume and mute", systemImage: "speaker.wave.2").font(.callout.weight(.medium))
            Text(aid.volume.map { "\($0.level > 0 ? "+" : "")\($0.level) · \($0.muted ? "Muted" : "Sound on")" } ?? "Not loaded")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 44)
    }
    private func commonPrograms(_ aids: [AidConnection]) -> [Int] {
        guard aids.count == 2 else { return [] }
        return aids[0].programIDs.filter { id in
            aids[1].programIDs.contains(id) && aids[0].programNames[id] != nil && aids[0].programNames[id] == aids[1].programNames[id]
        }
    }
    private func program(_ aid: AidConnection, ids: [UUID]) -> some View {
        let targets = ids.compactMap { store.connections[$0] }
        let programs = ids.count == 2 ? commonPrograms(targets) : aid.programIDs
        return VStack(alignment: .leading, spacing: 7) {
            Label("Program", systemImage: "waveform").font(.callout.weight(.medium))
            if let active = aid.activeProgram {
                Picker("\(aid.sideLabel) program", selection: Binding(get: { active }, set: { store.selectPrograms(ids, program: $0) })) {
                    ForEach(programs, id: \.self) { id in Text(aid.programNames[id] ?? "Program \(id + 1)").tag(id) }
                    if !programs.contains(active) { Text(aid.activeProgramName ?? "Current program").tag(active) }
                }.labelsHidden().disabled(programs.count < 2 || !targets.allSatisfy(\.canChangeProgram))
            } else { Text("Not loaded").font(.caption).foregroundStyle(.secondary) }
            if aid.programNames.isEmpty {
                Button("Read program names") { store.refreshProgramInfo(aid.id) }
                    .font(.caption).buttonStyle(.borderless)
                    .disabled(!aid.isConnected || aid.actionPending || aid.advancedBusy || aid.groupActionPending)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func deviceFooter(_ aid: AidConnection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DeviceDetailsView(store: store, aid: aid)
            Button("More device information") { store.select(aid.id); navigation.page = .devices }
                .font(.caption).buttonStyle(.borderless)
                .accessibilityLabel("More \(aid.sideLabel.lowercased()) device information")
            HStack {
                Circle().fill(aid.isConnected ? Color.teal : Color.secondary).frame(width: 6, height: 6)
                Text(aid.actionStatus ?? aid.phase.label).font(.caption)
                    .foregroundStyle(aid.actionFailed ? Color.orange : Color.secondary)
                Spacer(minLength: 0)
                Button { store.refresh(aid.id) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(!aid.isConnected || aid.actionPending || aid.advancedBusy || aid.groupActionPending)
                    .accessibilityLabel("Refresh \(aid.sideLabel.lowercased()) values")
            }
            if let error = aid.error { Text(error).font(.caption).foregroundStyle(.orange) }
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
                Text(linked ? "Linked" : "Separate").font(.system(size: 9, weight: .medium))
            }.foregroundStyle(linked ? accent : Color.secondary)
        }.buttonStyle(.plain).disabled(!available)
            .accessibilityLabel("Link \(title.lowercased()) between ears")
            .accessibilityValue(linked ? "Linked" : "Separate")
            .accessibilityIdentifier(identifier)
            .help(available ? "\(linked ? "Unlink" : "Link") \(title.lowercased()). Current sound stays unchanged until you use a control."
                  : "Connect both matching aids to link this setting")
    }
}

private struct VolumeButtonsView: View {
    @ObservedObject var store: BluetoothStore
    let aid: AidConnection
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Volume and mute", systemImage: "speaker.wave.2").font(.callout.weight(.medium))
            HStack(spacing: 8) {
                Button { store.adjustVolume(aid.id, by: -1) } label: { Image(systemName: "minus").frame(maxWidth: .infinity, minHeight: 24) }
                    .disabled(!aid.canChangeVolume || aid.volume?.level == aid.volumeRanges?.main.lowerBound)
                    .accessibilityLabel("Decrease \(aid.sideLabel.lowercased()) microphone level")
                Button { store.setMuted(aid.id, muted: !(aid.volume?.muted ?? false)) } label: {
                    Label(aid.volume?.muted == true ? "Unmute" : "Mute", systemImage: aid.volume?.muted == true ? "speaker.wave.2" : "speaker.slash")
                        .frame(maxWidth: .infinity, minHeight: 24)
                }.disabled(!aid.canChangeVolume)
                    .accessibilityLabel("\(aid.volume?.muted == true ? "Unmute" : "Mute") \(aid.sideLabel.lowercased()) ear")
                Button { store.adjustVolume(aid.id, by: 1) } label: { Image(systemName: "plus").frame(maxWidth: .infinity, minHeight: 24) }
                    .disabled(!aid.canChangeVolume || aid.volume?.level == aid.volumeRanges?.main.upperBound)
                    .accessibilityLabel("Increase \(aid.sideLabel.lowercased()) microphone level")
            }.buttonStyle(.bordered)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SpeechBoosterCell: View {
    @ObservedObject var store: BluetoothStore
    let aid: AidConnection
    let targetIDs: [UUID]
    private var canChange: Bool {
        let targets = targetIDs.compactMap { store.connections[$0] }
        return targets.count == targetIDs.count && targets.allSatisfy(\.canChangeSpeechBooster) && !store.linkedActionPending
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("SpeechBooster", isOn: Binding(get: { aid.speechBoosterEnabled ?? false }, set: { store.setSpeechBoosters(targetIDs, enabled: $0) }))
                .toggleStyle(.switch).disabled(!canChange)
                .accessibilityLabel("\(aid.sideLabel) SpeechBooster\(targetIDs.count == 2 ? ", changes both ears" : "")")
            if aid.speechBoosterEnabled == nil {
                Button("Load SpeechBooster") { store.refreshConsumerFeatures(aid.id) }.buttonStyle(.borderless)
                    .disabled(!aid.isConnected || aid.actionPending || aid.advancedBusy || aid.groupActionPending)
                    .accessibilityLabel("Load \(aid.sideLabel.lowercased()) SpeechBooster")
            } else if aid.activeProgram.flatMap({ aid.programBoostable[$0] }) == false {
                Text("Unavailable in this program").foregroundStyle(.secondary)
            } else if let status = aid.consumerStatus { Text(status).foregroundStyle(.secondary) }
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
    }
}
