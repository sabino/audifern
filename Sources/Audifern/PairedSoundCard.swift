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
    @EnvironmentObject private var navigation: AppNavigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var faders
    private var pair: [AidConnection] { [left, right] }

    var body: some View {
        Surface(insets: compact ? 12 : 16) {
            VStack(spacing: compact ? 6 : 8) {
                ZStack {
                    HStack {
                        Text(masterMixed ? L("Custom grouping") : L("Hearing aids")).font(AppType.callout.weight(.semibold))
                        Spacer(minLength: 0)
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
                if compact { compactControls }
                else { expandedControls }
                HStack(spacing: 8) {
                    DeviceSoundButtons(aid: left).frame(maxWidth: .infinity)
                    SpeechBoosterQuickButton(store: store, aids: pair)
                    DeviceSoundButtons(aid: right).frame(maxWidth: .infinity)
                }.frame(height: 28)
                if !compact {
                    Text(store.linkedActionStatus.map(M) ?? (masterMixed ? L("Custom grouping") : L("All sound controls")))
                        .font(AppType.caption).foregroundStyle(store.linkedActionFailed ? Color.orange : .secondary)
                        .lineLimit(1).frame(height: 20)
                        .accessibilityIdentifier("sound-change-status")
                }
            }
        }.animation(reduceMotion ? nil : .smooth(duration: 0.22), value: together)
    }

    private var compactControls: some View {
        HStack(spacing: 12) {
            compactEar(left)
            if together {
                HStack(spacing: 10) {
                    VolumeFader(store: store, aid: left, targets: pair, height: 86, width: 32)
                    VStack(spacing: 0) {
                        VolumeLevelButtons(store: store, aid: left, targets: pair, compact: true)
                        StableMuteToggle(store: store, targets: pair)
                    }
                }.frame(width: 190)
            }
            compactEar(right)
        }.frame(height: 90)
    }
    private func compactEar(_ aid: AidConnection) -> some View {
        HStack(spacing: 8) {
            HearingAidArtwork(right: aid.sideLabel == "Right", size: 0.36)
            VStack(alignment: .leading, spacing: 3) {
                Text(L(aid.sideLabel)).font(AppType.callout.weight(.semibold))
                Text(aid.model ?? L("Hearing aid")).font(AppType.small).foregroundStyle(.secondary).lineLimit(1)
                AidBatteryView(store: store, aid: aid, compact: true, compactWidth: together ? 142 : 110)
            }
            if !together {
                Spacer(minLength: 0)
                VolumeFader(store: store, aid: aid, targets: [aid], height: 86, width: 28)
                VStack(spacing: 0) {
                    VolumeLevelButtons(store: store, aid: aid, targets: [aid], compact: true)
                    StableMuteToggle(store: store, targets: [aid], compact: true)
                }
            }
        }.frame(maxWidth: .infinity)
    }
    private var expandedControls: some View {
        VStack(spacing: 6) {
            SoundEarColumns { earHeading(left) } center: { Color.clear } right: { earHeading(right) }
            ZStack {
                SoundEarColumns { HearingAidArtwork() } center: { Color.clear } right: { HearingAidArtwork(right: true) }
                HStack(spacing: 44) {
                    VolumeFader(store: store, aid: left, targets: together ? pair : [left])
                        .matchedGeometryEffect(id: "left-fader", in: faders)
                    if !together {
                        VolumeFader(store: store, aid: right, targets: [right])
                            .matchedGeometryEffect(id: "right-fader", in: faders).transition(.opacity)
                    }
                }
            }.frame(height: 180)
            ZStack {
                SoundEarColumns { level(left) } center: { Color.clear } right: { level(right) }
                if together { VolumeLevelButtons(store: store, aid: left, targets: pair) }
            }.frame(height: 55)
            ZStack {
                SoundEarColumns { mute(left) } center: { Color.clear } right: { mute(right) }
                if together { StableMuteToggle(store: store, targets: pair) }
            }.frame(height: 32)
            SoundEarColumns { AidBatteryView(store: store, aid: left, compact: true) }
                center: { EmptyView() } right: { AidBatteryView(store: store, aid: right, compact: true) }
        }
    }
    private func earHeading(_ aid: AidConnection) -> some View {
        VStack(spacing: 5) {
            Text(L(aid.sideLabel)).font(AppType.subheading.weight(.semibold))
            HStack(spacing: 6) {
                Circle().fill(aid.isConnected ? Brand.accent : Color.secondary).frame(width: 6, height: 6)
                Text(aid.model ?? L("Hearing aid")).font(AppType.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }.frame(height: 54)
    }
    @ViewBuilder private func level(_ aid: AidConnection) -> some View {
        if together {
            Text(aid.volume.map { L("Level %d", $0.level) } ?? L("Level —"))
                .font(AppType.callout.monospacedDigit()).foregroundStyle(.secondary)
        } else { VolumeLevelButtons(store: store, aid: aid, targets: [aid]) }
    }
    @ViewBuilder private func mute(_ aid: AidConnection) -> some View {
        if together { Image(systemName: aid.volume?.muted == true ? "speaker.slash.fill" : "speaker.wave.2").foregroundStyle(.secondary) }
        else { StableMuteToggle(store: store, targets: [aid]) }
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
