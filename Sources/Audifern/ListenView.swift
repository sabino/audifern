import CompanionCore
import SwiftUI

/// Daily controls contain no device identifiers or protocol/debug fields.
struct ListenView: View {
    @ObservedObject var store: BluetoothStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var preferences: AppPreferences
    @AppStorage("groupedHearingAidControls") private var together = true
    @AppStorage("groupedSpeechBoosterControls") private var speechTogether = true
    @AppStorage("groupedProgramControls") private var programsTogether = true

    private var aids: [AidConnection] {
        store.orderedConnections.sorted { $0.sideLabel == "Left" && $1.sideLabel != "Left" }
    }
    private var pair: [AidConnection]? {
        guard let left = aids.first(where: { $0.sideLabel == "Left" }),
              let right = aids.first(where: { $0.sideLabel == "Right" }) else { return nil }
        return [left, right]
    }
    private var canLink: Bool { pair != nil && store.connectedPair.count == 2 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeading(title: L("Sound"), subtitle: L("Make room for what you want to hear.")) { ConnectionBadge(store: store) }
                if store.isDemo {
                    Label(L("Preview only. Sample devices; Bluetooth and sound changes are disabled."), systemImage: "eye")
                        .font(AppType.callout).foregroundStyle(.secondary)
                }
                if let error = store.lastError {
                    Label(M(error), systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(AppType.callout)
                }
                if !aids.isEmpty { soundActions }
                if let pair {
                    PairedSoundCard(store: store, left: pair[0], right: pair[1], together: $together)
                    speechCard(pair)
                    programCard(pair)
                } else if let aid = aids.first {
                    Surface {
                        VStack(spacing: 18) {
                            DailyEarControls(store: store, aid: aid, targets: [aid]).frame(maxWidth: 320)
                            actionFeedback
                            Button(L("Connect the other ear")) { navigation.show(.devices) }
                        }.frame(maxWidth: .infinity)
                    }
                    speechCard([aid])
                    programCard([aid])
                } else {
                    Surface {
                        ContentUnavailableView {
                            Label(L("Ready when you are"), systemImage: "ear.badge.waveform")
                        } description: { Text(L("Keep your hearing aids nearby, then connect over Bluetooth.")) }
                        actions: {
                            if store.pairCandidateIDs.count == 2 {
                                Button(L("Connect hearing aids")) { store.connectPair() }.buttonStyle(.borderedProminent).font(AppType.body).disabled(!store.isPoweredOn)
                            }
                            Button(L("Find hearing aids")) { navigation.show(.devices) }
                        }.frame(minHeight: 330)
                    }
                }
            }.padding(28).frame(maxWidth: 1120)
        }
    }

    @ViewBuilder private var actionFeedback: some View {
        if let status = store.linkedActionStatus {
            Label(M(status), systemImage: store.linkedActionFailed ? "exclamationmark.circle" : "checkmark.circle")
                .font(AppType.caption).foregroundStyle(store.linkedActionFailed ? Color.orange : .secondary)
                .accessibilityIdentifier("sound-change-status")
        }
    }

    private func speechCard(_ targets: [AidConnection]) -> some View {
        Surface(insets: 20) {
            VStack(spacing: 14) {
                featureHeading(L("SpeechBooster"), subtitle: L("Bring conversations into focus."), symbol: "mic", color: .purple)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if targets.count == 2 {
                    ZStack {
                        SoundEarColumns { sideTitle(targets[0]) } center: { Color.clear.frame(height: 38) } right: { sideTitle(targets[1]) }
                        EarControlModePicker(together: $speechTogether, available: canLink, accent: .purple,
                                             scope: L("SpeechBooster"), identifier: "link-speech-booster")
                    }
                    ZStack {
                        SoundEarColumns {
                            speechControl(targets[0], grouped: speechTogether)
                        } center: { Color.clear } right: {
                            speechControl(targets[1], grouped: speechTogether)
                        }
                        if speechTogether {
                            Toggle(L("SpeechBooster"), isOn: Binding(
                                get: { targets.allSatisfy { $0.speechBoosterEnabled == true } },
                                set: { store.setSpeechBoosters(targets.map(\.id), enabled: $0) }))
                                .toggleStyle(.switch).labelsHidden().tint(.purple)
                                .disabled(!targets.allSatisfy(\.canChangeSpeechBooster) || store.linkedActionPending)
                                .accessibilityLabel(L("SpeechBooster for both ears"))
                        }
                    }.frame(height: 48)
                } else if let aid = targets.first { speechControl(aid, grouped: false) }
            }.disabled(store.isDemo)
        }
    }

    private func sideTitle(_ aid: AidConnection) -> some View {
        Text(L(aid.sideLabel)).font(AppType.callout.weight(.medium)).foregroundStyle(.secondary)
    }

    private func speechControl(_ aid: AidConnection, grouped: Bool) -> some View {
        VStack(spacing: 6) {
            if !grouped {
                Toggle(L("SpeechBooster"), isOn: Binding(get: { aid.speechBoosterEnabled == true },
                    set: { store.setSpeechBoosters([aid.id], enabled: $0) }))
                    .toggleStyle(.switch).labelsHidden().tint(.purple)
                    .disabled(!aid.canChangeSpeechBooster || store.linkedActionPending)
                    .accessibilityLabel(L("%@ SpeechBooster", L(aid.sideLabel)))
            }
            if aid.speechBoosterEnabled == nil {
                Button(L("Load SpeechBooster")) { store.refreshConsumerFeatures(aid.id) }
                    .buttonStyle(.borderless).disabled(!aid.isConnected || aid.actionPending || aid.advancedBusy)
            } else {
                Text(aid.activeProgram.flatMap { aid.programBoostable[$0] } == false ? L("Unavailable in this program")
                     : aid.speechBoosterEnabled == true ? L("On") : L("Off"))
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
            }
        }.font(AppType.caption).frame(height: 48)
    }

    private func programCard(_ targets: [AidConnection]) -> some View {
        Surface(insets: 20) {
            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    featureHeading(L("Listening program"), subtitle: L("Choose from your fitted programs."), symbol: "waveform", color: Brand.accent)
                    Spacer(minLength: 0)
                    Button(L("Manage programs")) { navigation.show(.programs) }
                        .font(AppType.callout).accessibilityIdentifier("open-listening-programs")
                }
                if targets.count == 2 {
                    ZStack {
                        SoundEarColumns { sideTitle(targets[0]) } center: { Color.clear.frame(height: 38) } right: { sideTitle(targets[1]) }
                        EarControlModePicker(together: $programsTogether, available: canLink,
                                             scope: L("Listening program"), identifier: "link-program")
                    }
                    SoundEarColumns {
                        programControl(targets[0], targets: targets)
                    } center: { EmptyView() } right: {
                        programControl(targets[1], targets: targets)
                    }
                } else if let aid = targets.first { programControl(aid, targets: [aid]) }
            }.disabled(store.isDemo)
        }
    }

    private func programControl(_ aid: AidConnection, targets: [AidConnection]) -> some View {
        ProgramSelectionView(store: store, aid: aid, targetIDs: programsTogether && canLink ? targets.map(\.id) : [aid.id],
                             compact: true, showsSide: false, centered: true)
            .frame(maxWidth: 250, minHeight: 32)
    }

    private var connectionActions: some View {
        HStack(spacing: 12) {
            if store.connectedCount > 0 {
                Button(L("Disconnect")) { store.disconnect() }.font(AppType.callout).disabled(store.isDemo)
                    .accessibilityIdentifier("disconnect-sound-devices")
            } else if store.pairCandidateIDs.count == 2 {
                Button(L("Reconnect")) { store.connectPair() }.font(AppType.callout).disabled(!store.isPoweredOn || store.isDemo)
                    .accessibilityIdentifier("reconnect-sound-devices")
            }
            Button { navigation.show(.devices) } label: { Image(systemName: "magnifyingglass").frame(width: 22, height: 24) }
                .help(L("Find hearing aids")).accessibilityLabel(L("Find hearing aids"))
                .accessibilityIdentifier("find-hearing-aids")
        }
    }

    private var soundActions: some View {
        HStack(spacing: 16) {
            Button { navigation.present(.equalizers) } label: { Label(L("Equalizer…"), systemImage: "slider.horizontal.3") }
                .labelStyle(AlignedLabelStyle(iconSize: 16, iconWidth: 20, spacing: 8))
                .buttonStyle(.borderedProminent).font(AppType.body).controlSize(.large)
            Button { navigation.present(.savePreset) } label: { Label(L("Save sound…"), systemImage: "bookmark") }
                .labelStyle(AlignedLabelStyle(iconSize: 16, iconWidth: 20, spacing: 8))
                .buttonStyle(.bordered).font(AppType.body).controlSize(.large)
            Spacer()
            connectionActions
        }
    }

    private func featureHeading(_ title: String, subtitle: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(AppType.subheading.weight(.medium)).foregroundStyle(color)
                .frame(width: 42, height: 42).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(AppType.headline)
                Text(subtitle).font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct DailyEarControls: View {
    @ObservedObject var store: BluetoothStore
    let aid: AidConnection
    let targets: [AidConnection]
    @EnvironmentObject private var preferences: AppPreferences
    @State private var previewLevel: Int?
    private var selection: MainVolumeSelection? { .init(aids: targets, anchorID: aid.id) }
    private var canChange: Bool { !store.isDemo && !store.linkedActionPending && selection != nil }
    private var muted: Bool { targets.allSatisfy { $0.volume?.muted == true } }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(aid.isConnected ? Brand.accent : Color.secondary).frame(width: 6, height: 6)
                Text(L(aid.sideLabel)).font(AppType.subheading.weight(.semibold))
            }
            Text(aid.model ?? L("Hearing aid")).font(AppType.caption).foregroundStyle(.secondary)
            HStack(spacing: 18) {
                HearingAidArtwork(right: aid.sideLabel == "Right")
                VStack(spacing: 4) {
                    Image(systemName: "speaker.wave.3").foregroundStyle(.tertiary)
                    NativeVolumeSlider(value: aid.volume?.level ?? 0,
                        range: selection?.range ?? aid.volumeRanges?.main ?? 0...0,
                        enabled: canChange, label: L("%@ volume", L(aid.sideLabel)),
                        preview: { previewLevel = $0 }, commit: { target in
                            guard let selection, target != selection.level else { return }
                            store.setMainVolume(selection, level: target)
                        })
                        .frame(width: 36, height: 154)
                        .disabled(!canChange)
                        .accessibilityIdentifier("volume-fader-\(aid.sideLabel.lowercased())")
                    Image(systemName: "speaker.wave.1").foregroundStyle(.tertiary)
                }
            }.frame(height: 190)
            HStack(spacing: 12) {
                Button { setLevel((aid.volume?.level ?? 0) - 1) } label: {
                    Image(systemName: "minus").font(.system(size: 17, weight: .medium)).frame(width: 24, height: 26)
                }
                    .disabled(!canChange || !allows(-1)).accessibilityLabel(L("Decrease %@ microphone level", L(aid.sideLabel)))
                VStack(spacing: 0) {
                    Text(previewLevel.map(String.init) ?? aid.volume.map { String($0.level) } ?? "—")
                        .font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                        .accessibilityIdentifier("volume-value-\(aid.sideLabel.lowercased())")
                    Text(L("Level")).font(AppType.small).foregroundStyle(.secondary)
                }.frame(width: 60, height: 55)
                Button { setLevel((aid.volume?.level ?? 0) + 1) } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .medium)).frame(width: 24, height: 26)
                }
                    .disabled(!canChange || !allows(1)).accessibilityLabel(L("Increase %@ microphone level", L(aid.sideLabel)))
            }.buttonStyle(.bordered).font(AppType.body)
            HStack(spacing: 12) {
                AidBatteryView(store: store, aid: aid, compact: true)
                Spacer(minLength: 0)
                StableMuteToggle(store: store, targets: targets)
            }.font(AppType.caption)
            Text(aid.actionStatus.map(M) ?? " ").font(AppType.caption).foregroundStyle(aid.actionFailed ? Color.orange : .secondary)
                .lineLimit(2).frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
        }.frame(maxWidth: .infinity)
    }
    private func allows(_ delta: Int) -> Bool { selection.map { $0.range.contains($0.level + delta) } ?? false }
    private func setLevel(_ value: Int) {
        if let selection { store.setMainVolume(selection, level: value) }
    }
}
