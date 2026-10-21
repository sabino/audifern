import CompanionCore
import SwiftUI

struct PairedSoundCard: View {
    @ObservedObject var store: BluetoothStore
    let left: AidConnection
    let right: AidConnection
    @Binding var together: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var faders
    private var pair: [AidConnection] { [left, right] }

    var body: some View {
        Surface {
            VStack(spacing: 14) {
                HStack {
                    Label(together ? L("Together") : L("Separate"), systemImage: together ? "link" : "ear")
                        .font(AppType.callout.weight(.semibold)).foregroundStyle(together ? Brand.accent : .secondary)
                        .frame(width: 120, alignment: .leading)
                    Spacer()
                    Picker(L("Control mode"), selection: $together) {
                        Text(L("Together")).tag(true)
                        Text(L("Separate")).tag(false)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 258)
                        .accessibilityIdentifier("ear-control-mode")
                }
                Text(together ? L("Changes apply to both ears. Your current balance is preserved.") : L("Adjust each hearing aid independently."))
                    .font(AppType.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                HStack(alignment: .top, spacing: 8) {
                    ear(left, trailingFader: true)
                    VStack(spacing: 8) {
                        Spacer().frame(height: 48)
                        if together {
                            VolumeFader(store: store, aid: left, targets: pair)
                                .matchedGeometryEffect(id: "left-fader", in: faders)
                        } else { Color.clear.frame(width: 36, height: 180) }
                        VolumeLevelButtons(store: store, aid: left, targets: pair)
                            .opacity(together ? 1 : 0).allowsHitTesting(together).accessibilityHidden(!together)
                        StableMuteToggle(store: store, targets: pair)
                            .opacity(together ? 1 : 0).allowsHitTesting(together).accessibilityHidden(!together)
                    }.frame(width: 160)
                    ear(right, trailingFader: false)
                }
                Text(store.linkedActionStatus.map(M) ?? (together ? L("Together also applies to programs, SpeechBooster and equalizers.") : L("Choose Together to group all supported sound controls.")))
                    .font(AppType.caption).foregroundStyle(store.linkedActionFailed ? Color.orange : .secondary)
                    .lineLimit(2).frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                    .accessibilityIdentifier("sound-change-status")
            }
        }.animation(reduceMotion ? nil : .smooth(duration: 0.28), value: together)
    }
    private func ear(_ aid: AidConnection, trailingFader: Bool) -> some View {
        VStack(spacing: 8) {
            VStack(spacing: 5) {
                HStack(spacing: 7) {
                    Circle().fill(aid.isConnected ? Brand.accent : Color.secondary).frame(width: 6, height: 6)
                    Text(L(aid.sideLabel)).font(AppType.subheading.weight(.semibold))
                }
                Text(aid.model ?? L("Hearing aid")).font(AppType.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(height: 48)
            ZStack {
                HearingAidArtwork(right: aid.sideLabel == "Right")
                if !together {
                    VolumeFader(store: store, aid: aid, targets: [aid])
                        .matchedGeometryEffect(id: trailingFader ? "left-fader" : "right-fader", in: faders)
                        .offset(x: trailingFader ? 80 : -80)
                        .transition(.opacity)
                }
            }.frame(height: 180)
            VolumeLevelButtons(store: store, aid: aid, targets: [aid])
                .opacity(together ? 0 : 1).allowsHitTesting(!together).accessibilityHidden(together)
                .overlay { if together { Text(aid.volume.map { L("Level %d", $0.level) } ?? L("Level —")).font(AppType.callout.monospacedDigit()).foregroundStyle(.secondary) } }
            StableMuteToggle(store: store, targets: [aid])
                .opacity(together ? 0 : 1).allowsHitTesting(!together).accessibilityHidden(together)
                .overlay { if together { Image(systemName: aid.volume?.muted == true ? "speaker.slash.fill" : "speaker.wave.2").foregroundStyle(.secondary) } }
            AidBatteryView(store: store, aid: aid, compact: true)
        }.frame(maxWidth: .infinity)
    }
}

struct VolumeFader: View {
    @ObservedObject var store: BluetoothStore
    let aid: AidConnection
    let targets: [AidConnection]
    @State private var preview: Int?
    private var selection: MainVolumeSelection? { .init(aids: targets, anchorID: aid.id) }
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "speaker.wave.3").font(.system(size: 13)).foregroundStyle(.secondary)
            NativeVolumeSlider(value: preview ?? aid.volume?.level ?? 0,
                range: selection?.range ?? aid.volumeRanges?.main ?? 0...0,
                enabled: !store.isDemo && selection != nil,
                label: targets.count == 2 ? L("Both ears volume") : L("%@ volume", L(aid.sideLabel)),
                preview: { if let value = $0 { preview = value } }, commit: { target in
                    guard let selection, target != selection.level else { preview = nil; return }
                    preview = target; store.setMainVolume(selection, level: target)
                }).frame(width: 36, height: 144)
                .accessibilityIdentifier(targets.count == 2 ? "volume-fader-together" : "volume-fader-\(aid.sideLabel.lowercased())")
            Image(systemName: "speaker.wave.1").font(.system(size: 13)).foregroundStyle(.secondary)
        }.frame(width: 36, height: 180)
            .onChange(of: aid.volume?.level) { _, _ in preview = nil }
            .onChange(of: aid.actionFailed) { _, failed in if failed { preview = nil } }
            .transaction { $0.animation = nil }
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
    var body: some View {
        Toggle(L("Mute"), isOn: Binding(get: { !targets.isEmpty && targets.allSatisfy { $0.volume?.muted == true } }, set: { value in
            if targets.count == 2 { store.setLinkedMuted(value) }
            else if let aid = targets.first { store.setMuted(aid.id, muted: value) }
        })).toggleStyle(.switch).font(AppType.callout)
            .disabled(store.isDemo || targets.isEmpty || !targets.allSatisfy(\.canChangeVolume))
            .frame(width: 126, height: 32).transaction { $0.animation = nil }
            .accessibilityLabel(targets.count == 2 ? L("Mute both ears") : L("Mute %@ ear", targets.first.map { L($0.sideLabel) } ?? ""))
    }
}
