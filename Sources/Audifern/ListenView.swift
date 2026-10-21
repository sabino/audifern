import CompanionCore
import SwiftUI

/// A bounded workspace: expanding volume folds EQ, and opening EQ restores a
/// compact device strip. Neither action changes a device setting or a draft.
struct ListenView: View {
    @ObservedObject var store: BluetoothStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("soundDevicesExpanded") private var devicesExpanded = false
    @AppStorage("groupedHearingAidControls") private var together = true
    @AppStorage("groupedSpeechBoosterControls") private var speechTogether = true
    @AppStorage("groupedProgramControls") private var programsTogether = true
    @AppStorage("groupedEqualizerControls") private var microphoneTogether = true
    @AppStorage("groupedStreamingControls") private var streamingTogether = true
    @AppStorage("groupedTinnitusControls") private var tinnitusTogether = true
    private var masterMixed: Bool {
        [speechTogether, programsTogether, microphoneTogether, streamingTogether, tinnitusTogether].contains { $0 != together }
    }
    private var masterGrouping: Binding<Bool> {
        Binding(get: { together }, set: { preferences.groupAllSoundControls($0) })
    }
    private var aids: [AidConnection] {
        store.orderedConnections.sorted { $0.sideLabel == "Left" && $1.sideLabel != "Left" }
    }
    private var pair: [AidConnection]? {
        guard let left = aids.first(where: { $0.sideLabel == "Left" }),
              let right = aids.first(where: { $0.sideLabel == "Right" }) else { return nil }
        return [left, right]
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = SoundWorkspaceMetrics(height: geometry.size.height, preview: store.isDemo)
            VStack(alignment: .leading, spacing: 12) {
                heading
                if store.isDemo {
                    Label(L("Preview only. Sample devices; Bluetooth and sound changes are disabled."), systemImage: "eye")
                        .font(AppType.small).foregroundStyle(.secondary).lineLimit(1).frame(height: 18)
                }
                if !aids.isEmpty {
                    if let pair {
                        PairedSoundCard(store: store, left: pair[0], right: pair[1], together: masterGrouping,
                                        masterMixed: masterMixed, compact: !devicesExpanded,
                                        expanded: $devicesExpanded)
                    } else if let aid = aids.first {
                        singleDevice(aid)
                    }
                    if devicesExpanded { foldedEqualizers }
                    else { equalizerCard(faderHeight: metrics.faderHeight) }
                } else {
                    Surface {
                        ContentUnavailableView {
                            Label(L("Ready when you are"), systemImage: "ear.badge.waveform")
                        } description: { Text(L("Keep your hearing aids nearby, then connect over Bluetooth.")) }
                        actions: {
                            if store.pairCandidateIDs.count == 2 {
                                Button(L("Connect hearing aids")) { store.connectPair() }.buttonStyle(.borderedProminent)
                                    .disabled(!store.isPoweredOn)
                            }
                            Button(L("Find hearing aids")) { navigation.show(.devices) }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                if let error = store.lastError {
                    Label(M(error), systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                        .font(AppType.caption).lineLimit(1).help(M(error))
                }
            }
            .padding(20).frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: devicesExpanded)
        }
        .onChange(of: navigation.soundFocus) { _, request in if request != nil { devicesExpanded = false } }
        .onAppear { if navigation.soundFocus != nil { devicesExpanded = false } }
    }

    private var heading: some View {
        HStack(spacing: 12) {
            Text(L("Sound")).font(.system(size: 28, weight: .bold))
            Spacer(minLength: 0)
            if !aids.isEmpty {
                Button { navigation.present(.savePreset) } label: { Label(L("Save sound…"), systemImage: "bookmark") }
                    .font(AppType.caption).buttonStyle(.bordered)
                if store.connectedCount > 0 && !store.isDemo {
                    Button(L("Disconnect")) { store.disconnect() }.font(AppType.caption).disabled(store.isDemo)
                        .accessibilityIdentifier("disconnect-sound-devices")
                } else if store.pairCandidateIDs.count == 2 && !store.isDemo {
                    Button(L("Reconnect")) { store.connectPair() }.font(AppType.caption).disabled(!store.isPoweredOn || store.isDemo)
                        .accessibilityIdentifier("reconnect-sound-devices")
                }
            }
            ConnectionBadge(store: store)
            Button { navigation.show(.devices) } label: { Image(systemName: "magnifyingglass").frame(width: 20, height: 22) }
                .help(L("Find hearing aids")).accessibilityLabel(L("Find hearing aids"))
                .accessibilityIdentifier("find-hearing-aids")
        }.frame(height: 42)
    }

    private func singleDevice(_ aid: AidConnection) -> some View {
        Surface(insets: 14) {
            HStack(spacing: 18) {
                HearingAidArtwork(right: aid.sideLabel == "Right", size: 0.48)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L(aid.sideLabel)).font(AppType.headline)
                    Text(aid.model ?? L("Hearing aid")).font(AppType.caption).foregroundStyle(.secondary)
                    AidBatteryView(store: store, aid: aid, compact: true)
                }
                Spacer(minLength: 0)
                VolumeFader(store: store, aid: aid, targets: [aid], height: 88, width: 32)
                VStack(spacing: 4) {
                    VolumeLevelButtons(store: store, aid: aid, targets: [aid], compact: true)
                    StableMuteToggle(store: store, targets: [aid])
                }
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    DeviceSoundButtons(aid: aid)
                    SpeechBoosterQuickButton(store: store, aids: [aid])
                    Button(L("Connect the other ear")) { navigation.show(.devices) }.font(AppType.caption)
                }
            }.frame(height: 140)
        }
    }

    private func equalizerCard(faderHeight: CGFloat) -> some View {
        Surface(insets: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Label(L("Equalizers"), systemImage: "slider.vertical.3").font(AppType.headline)
                    Spacer(minLength: 0)
                    Button(L("More sound controls…")) { navigation.present(.equalizers) }
                        .font(AppType.caption).buttonStyle(.bordered).controlSize(.regular)
                        .accessibilityIdentifier("more-sound-controls")
                }.frame(height: 26)
                HearingAidControlsView(store: store, embedded: true, faderHeight: faderHeight)
            }
        }.frame(maxHeight: .infinity, alignment: .top)
            .accessibilityIdentifier("sound-equalizers")
    }

    private var foldedEqualizers: some View {
        Surface(insets: 14) {
            HStack(spacing: 14) {
                Image(systemName: "slider.vertical.3").font(AppType.headline).foregroundStyle(Brand.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Equalizers")).font(AppType.headline)
                    Text(L("Microphone, streaming and tinnitus controls")).font(AppType.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(L("Edit equalizers")) { devicesExpanded = false }
                    .buttonStyle(.borderedProminent).font(AppType.caption)
                    .accessibilityIdentifier("expand-equalizers")
            }
        }.frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Budget for the smallest supported content area. The line sliders get the
/// remaining height; device controls and action rows never shrink their text.
struct SoundWorkspaceMetrics {
    let height: CGFloat
    var preview = false
    var faderHeight: CGFloat { max(56, min(340, height - (preview ? 684 : 654))) }
}
