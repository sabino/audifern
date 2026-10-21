import AppKit
import SwiftUI
#if !WIDGET_EXTENSION
import QuickAccessKit
#endif

public enum QuickWidgetSize: Sendable { case small, medium, large }

public struct QuickWidgetView<Controls: View>: View {
    public let state: QuickAccessState?
    public let date: Date
    public let size: QuickWidgetSize
    public let target: QuickTarget
    public let artwork: URL?
    public let mark: URL?
    private let controls: () -> Controls
    @Environment(\.displayScale) private var scale
    public init(state: QuickAccessState?, date: Date, size: QuickWidgetSize, target: QuickTarget = .both,
                artwork: URL?, mark: URL?, @ViewBuilder controls: @escaping () -> Controls) {
        self.state = state; self.date = date; self.size = size; self.target = target; self.artwork = artwork; self.mark = mark; self.controls = controls
    }
    private var ears: [QuickTarget] { target == .both ? [.left, .right] : [target] }
    public var body: some View {
        VStack(spacing: size == .small ? 5 : 8) {
            HStack(spacing: 6) {
                if let mark, let image = NSImage(contentsOf: mark) { Image(nsImage: image).resizable().scaledToFit().frame(width: 16, height: 18) }
                Text("Audifern").font(.system(size: size == .small ? 13 : 15, weight: .semibold))
                Spacer(minLength: 0)
                Circle().fill(state?.isFresh(at: date) == true ? Color(red: 0.12, green: 0.58, blue: 0.45) : .secondary).frame(width: 5, height: 5)
            }.frame(height: 20)
            HStack(alignment: .center, spacing: size == .small ? 6 : 12) {
                ForEach(ears, id: \.self) { side in
                    let aid = state?.ears.first { $0.side == side }
                    if size == .medium {
                        HStack(spacing: 7) {
                            device(side, width: 42, height: 52)
                            information(aid, side: side, compact: false)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 4) {
                            Text(label(side)).font(.system(size: size == .small ? 10 : 13, weight: .medium)).foregroundStyle(.secondary)
                            device(side, width: size == .small ? 40 : 86, height: size == .small ? 49 : 105)
                            information(aid, side: side, compact: size == .small)
                        }.frame(maxWidth: .infinity)
                    }
                }
            }.frame(maxHeight: .infinity)
            controls()
            if size == .large {
                HStack {
                    Text(L("Last reading")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if let state { Text(state.updatedAt, style: .time).font(.system(size: 11)).foregroundStyle(.secondary) }
                }.frame(height: 15)
            }
        }.tint(Color(red: 0.12, green: 0.58, blue: 0.45))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func information(_ aid: QuickEar?, side: QuickTarget, compact: Bool) -> some View {
        VStack(alignment: size == .medium ? .leading : .center, spacing: 3) {
            if size == .medium { Text(label(side)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary) }
            Text(aid?.battery.map { "\($0)%" } ?? "—").font(.system(size: compact ? 12 : 16, weight: .semibold)).monospacedDigit()
                .frame(minWidth: compact ? 30 : 42, minHeight: compact ? 15 : 20)
            if size != .medium {
                ProgressView(value: Double(aid?.battery ?? 0), total: 100).frame(maxWidth: compact ? 42 : 72)
            }
            Text(runtime(aid)).font(.system(size: compact ? 9 : 11)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1).frame(height: compact ? 12 : 15)
        }
    }
    @ViewBuilder private func device(_ side: QuickTarget, width: CGFloat, height: CGFloat) -> some View {
        if let artwork, let image = ArtworkRasterizer.image(url: artwork, size: .init(width: width, height: height), scale: scale, mirrored: side == .right) {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: width, height: height)
        } else { Image(systemName: "ear.badge.waveform").resizable().scaledToFit().foregroundStyle(.secondary).frame(width: width, height: height) }
    }
    private func label(_ side: QuickTarget) -> String { L(side == .left ? "Left" : "Right") }
    private func runtime(_ aid: QuickEar?) -> String {
        guard let sample = aid?.runtime else { return "—" }
        if sample.isCharged { return L("Charged") }
        if sample.isCharging { return L("Charging") }
        guard let seconds = sample.remainingSeconds(at: date) else { return "—" }
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "<1 min" }
        return minutes >= 60 ? "~\(minutes / 60) h \(minutes % 60) min" : "~\(minutes) min"
    }
    private func L(_ key: String) -> String { Bundle.main.localizedString(forKey: key, value: key, table: nil) }
}
