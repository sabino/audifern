import CompanionCore
import SwiftUI

struct PairedSoundCard: View {
    @ObservedObject var store: BluetoothStore
    let left: AidConnection
    let right: AidConnection
    @Binding var together: Bool
    var masterMixed = false
    var compact = false
    @Binding var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var pair: [AidConnection] { [left, right] }

    var body: some View {
        Surface(insets: compact ? 12 : 16) {
            VStack(spacing: compact ? 6 : 8) {
                ZStack {
                    HStack {
                        Text(masterMixed ? L("Custom grouping") : L("Hearing aids")).font(AppType.callout.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                        SpeechBoosterQuickButton(store: store, aids: pair)
                        Button { expanded.toggle() } label: {
                            Label(compact ? L("Expand volume controls") : L("Compact volume controls"),
                                  systemImage: compact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                                .labelStyle(.iconOnly).frame(width: 24, height: 24)
                        }.buttonStyle(.bordered).controlSize(.regular)
                            .help(compact ? L("Expand volume controls") : L("Compact volume controls"))
                            .accessibilityIdentifier("toggle-device-size")
                    }
                    EarControlModePicker(together: $together, available: store.connectedPair.count == 2,
                                         isMixed: masterMixed, affectsAllSections: true,
                                         scope: L("All sound controls"), identifier: "ear-control-mode")
                }.frame(height: 38)
                volumeControls
                SoundDeviceColumns {
                    DeviceSoundButtons(aid: left)
                } center: {
                    HStack(spacing: 12) {
                        if together {
                            StableMuteToggle(store: store, targets: pair).frame(maxWidth: .infinity)
                        } else {
                            ForEach(pair) { aid in
                                StableMuteToggle(store: store, targets: [aid]).frame(maxWidth: .infinity)
                            }
                        }
                    }.controlSize(.regular)
                } right: {
                    DeviceSoundButtons(aid: right)
                }.frame(height: 32)
                if !compact {
                    Text(store.linkedActionStatus.map(M) ?? (masterMixed ? L("Custom grouping") : L("All sound controls")))
                        .font(AppType.caption).foregroundStyle(store.linkedActionFailed ? Color.orange : .secondary)
                        .lineLimit(1).frame(height: 20)
                        .accessibilityIdentifier("sound-change-status")
                }
            }
        }.animation(reduceMotion ? nil : .smooth(duration: 0.22), value: together)
    }

    private var volumeControls: some View {
        SoundDeviceColumns {
            overview(left)
        } center: {
            HStack(spacing: 12) {
                if together {
                    DailyVolumeControl(store: store, aid: left, targets: pair, showsMute: false)
                } else {
                    ForEach(pair) { aid in
                        DailyVolumeControl(store: store, aid: aid, targets: [aid], showsMute: false)
                    }
                }
            }
        } right: {
            overview(right)
        }.frame(height: compact ? 86 : 220)
    }
    private func overview(_ aid: AidConnection) -> some View {
        Group {
            if compact {
                HStack(spacing: 8) {
                    if aid.sideLabel == "Left" { illustration(aid) }
                    deviceSummary(aid)
                    if aid.sideLabel == "Right" { illustration(aid) }
                }
            } else {
                VStack(spacing: 10) {
                    illustration(aid)
                    deviceSummary(aid)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("device-overview-\(aid.sideLabel.lowercased())")
    }
    private func deviceSummary(_ aid: AidConnection) -> some View {
        VStack(alignment: aid.sideLabel == "Left" ? .leading : .trailing, spacing: 3) {
            Text(L(aid.sideLabel)).font(AppType.callout.weight(.semibold))
            Text(aid.model ?? L("Hearing aid")).font(AppType.small).foregroundStyle(.secondary).lineLimit(1)
            AidBatteryView(store: store, aid: aid, compact: true, compactWidth: 110)
        }
    }
    private func illustration(_ aid: AidConnection) -> some View {
        HearingAidArtwork(right: aid.sideLabel == "Right", size: compact ? 0.32 : 0.65)
    }
}

/// The two outer lanes never participate in a grouping change. Volume expands
/// into the remaining width, and its mute controls reuse the same middle lane.
private struct SoundDeviceColumns<Left: View, Center: View, Right: View>: View {
    @ViewBuilder var left: () -> Left
    @ViewBuilder var center: () -> Center
    @ViewBuilder var right: () -> Right
    var body: some View {
        HStack(spacing: 12) {
            left().frame(width: 160)
            center().frame(maxWidth: .infinity)
            right().frame(width: 160)
        }.frame(maxWidth: .infinity)
    }
}

struct VolumeFader: View {
    @ObservedObject var store: BluetoothStore
    let aid: AidConnection
    let targets: [AidConnection]
    var height: CGFloat = 174
    var width: CGFloat = 52
    @State private var preview: Int?
    private var selection: MainVolumeSelection? { .init(aids: targets, anchorID: aid.id) }
    var body: some View {
        ZStack {
            VolumeGlassBackground()
            NativeVolumeSlider(value: preview ?? aid.volume?.level ?? 0,
                range: selection?.range ?? aid.volumeRanges?.main ?? 0...0,
                enabled: !store.isDemo && selection != nil,
                label: targets.count == 2 ? L("Both ears volume") : L("%@ volume", L(aid.sideLabel)),
                style: .capsule,
                preview: { if let value = $0 { preview = value } }, commit: { target in
                    guard let selection, target != selection.level else { preview = nil; return }
                    preview = target; store.setMainVolume(selection, level: target)
                }).frame(width: width, height: height)
                .accessibilityIdentifier(targets.count == 2 ? "volume-fader-together" : "volume-fader-\(aid.sideLabel.lowercased())")
        }.frame(width: width, height: height)
            .onChange(of: aid.volume?.level) { _, _ in preview = nil }
            .onChange(of: aid.actionFailed) { _, failed in if failed { preview = nil } }
            .transaction { $0.animation = nil }
    }
}

private struct VolumeGlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if #available(macOS 26, *), !reduceTransparency {
            Capsule().fill(.clear).glassEffect(.regular.tint(Brand.accent.opacity(0.06)), in: .capsule)
        } else {
            Capsule().fill(Brand.background).overlay(Capsule().strokeBorder(.quaternary))
        }
    }
}

struct VolumeLevelButtons: View {
    @ObservedObject var store: BluetoothStore
    let aid: AidConnection
    let targets: [AidConnection]
    var compact = false
    private var selection: MainVolumeSelection? { .init(aids: targets, anchorID: aid.id) }
    var body: some View {
        HStack(spacing: compact ? 5 : 8) {
            Button { change(-1) } label: { Image(systemName: "minus").frame(width: compact ? 17 : 21, height: compact ? 19 : 25) }
                .disabled(!canChange(-1)).accessibilityLabel(L("Decrease %@ microphone level", targets.count == 2 ? L("Both ears") : L(aid.sideLabel)))
            VStack(spacing: 0) {
                Text(aid.volume.map { String($0.level) } ?? "—").font(.system(size: compact ? 24 : 29, weight: .semibold, design: .rounded)).monospacedDigit()
                    .frame(width: compact ? 36 : 52, height: compact ? 29 : 35).accessibilityIdentifier("volume-value-\(targets.count == 2 ? "together" : aid.sideLabel.lowercased())")
                Text(L("Level")).font(AppType.small).foregroundStyle(.secondary)
            }
            Button { change(1) } label: { Image(systemName: "plus").frame(width: compact ? 17 : 21, height: compact ? 19 : 25) }
                .disabled(!canChange(1)).accessibilityLabel(L("Increase %@ microphone level", targets.count == 2 ? L("Both ears") : L(aid.sideLabel)))
        }.buttonStyle(.bordered).frame(height: compact ? 49 : 55).transaction { $0.animation = nil }
    }
    private func canChange(_ delta: Int) -> Bool {
        guard !store.isDemo, let selection else { return false }
        return selection.range.contains(selection.level + delta)
    }
    private func change(_ delta: Int) {
        guard let selection, canChange(delta) else { return }
        store.setMainVolume(selection, level: selection.level + delta)
    }
}

struct StableMuteToggle: View {
    @ObservedObject var store: BluetoothStore
    let targets: [AidConnection]
    var compact = false
    var body: some View {
        HStack(spacing: 6) {
        if compact { Image(systemName: "speaker.slash").foregroundStyle(.secondary).accessibilityHidden(true) }
        muteToggle
        }
        .frame(width: compact ? 92 : 126, height: 32)
    }
    private var muteToggle: some View {
        Group {
            if compact { toggle.labelsHidden() } else { toggle }
        }
    }
    private var toggle: some View {
        Toggle(L("Mute"), isOn: Binding(get: { !targets.isEmpty && targets.allSatisfy { $0.volume?.muted == true } }, set: { value in
            if targets.count == 2 { store.setLinkedMuted(value) }
            else if let aid = targets.first { store.setMuted(aid.id, muted: value) }
        })).toggleStyle(.switch).font(AppType.callout)
            .disabled(store.isDemo || targets.isEmpty || !targets.allSatisfy(\.canChangeVolume))
            .transaction { $0.animation = nil }
            .accessibilityLabel(targets.count == 2 ? L("Mute both ears") : L("Mute %@ ear", targets.first.map { L($0.sideLabel) } ?? ""))
    }
}
