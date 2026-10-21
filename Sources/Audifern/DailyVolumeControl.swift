import CompanionCore
import SwiftUI

/// Horizontal daily volume: level above, step buttons at either end, mute below.
/// Tracking previews locally and commits once on release, preserving ear balance.
struct DailyVolumeControl: View {
    @ObservedObject var store: BluetoothStore
    let aid: AidConnection
    let targets: [AidConnection]
    var showsMute = true
    @State private var preview: Int?
    private var selection: MainVolumeSelection? { .init(aids: targets, anchorID: aid.id) }
    private var subject: String { targets.count == 2 ? L("Both ears") : L(aid.sideLabel) }
    var body: some View {
        let captured = selection
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(targets.count == 2 ? L("Level") : L(aid.sideLabel)).font(AppType.small).foregroundStyle(.secondary)
                Text(preview.map(String.init) ?? aid.volume.map { String($0.level) } ?? "—")
                    .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    .frame(width: 42, alignment: .leading)
                    .accessibilityIdentifier("volume-value-\(targets.count == 2 ? "together" : aid.sideLabel.lowercased())")
            }.frame(height: 24)
                .help(targets.map { L($0.sideLabel) + ": " + ($0.volume.map { String($0.level) } ?? "—") }.joined(separator: " · "))
            HStack(spacing: 8) {
                step(-1, symbol: "minus")
                NativeVolumeSlider(value: preview ?? aid.volume?.level ?? 0,
                    range: captured?.range ?? aid.volumeRanges?.main ?? 0...0,
                    enabled: !store.isDemo && captured != nil, label: L("%@ volume", subject),
                    vertical: false, preview: { preview = $0 }, commit: { target in
                        guard let captured, target != captured.level else { preview = nil; return }
                        preview = target; store.setMainVolume(captured, level: target)
                    })
                    .frame(minWidth: 76, maxWidth: .infinity).frame(height: 24)
                    .accessibilityIdentifier("volume-fader-\(targets.count == 2 ? "together" : aid.sideLabel.lowercased())")
                step(1, symbol: "plus")
            }.frame(height: 26).buttonStyle(.bordered).controlSize(.regular)
            if showsMute { StableMuteToggle(store: store, targets: targets).controlSize(.regular) }
        }.frame(minWidth: 160, maxWidth: .infinity).frame(height: showsMute ? 86 : 52)
            .accessibilityElement(children: .contain).accessibilityLabel(L("%@ volume", subject))
            .accessibilityIdentifier("daily-volume-\(targets.count == 2 ? "together" : aid.sideLabel.lowercased())")
            .onChange(of: aid.volume?.level) { _, _ in preview = nil }
            .onChange(of: aid.actionFailed) { _, failed in if failed { preview = nil } }
            .transaction { $0.animation = nil }
    }
    private func step(_ delta: Int, symbol: String) -> some View {
        Button {
            guard let selection else { return }
            store.setMainVolume(selection, level: selection.level + delta)
        } label: { Image(systemName: symbol).frame(width: 18, height: 20) }
            .disabled(store.isDemo || selection.map { !$0.range.contains($0.level + delta) } ?? true)
            .accessibilityLabel(delta < 0 ? L("Decrease %@ microphone level", subject) : L("Increase %@ microphone level", subject))
    }
}
