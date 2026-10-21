import SwiftUI

/// The same explicit choice in every sound section. Changing the selection
/// changes the target of future actions; it never copies or sends a setting.
struct EarControlModePicker: View {
    @Binding var together: Bool
    var available = true
    var accent = Brand.accent
    var isMixed = false
    var affectsAllSections = false
    let scope: String
    let identifier: String

    var body: some View {
        HStack(spacing: 3) {
            choice(true, title: L("Together"), symbol: "link")
            choice(false, title: L("Separate"), symbol: "ear")
        }
        .padding(4).frame(width: 236, height: 38)
        .background(accent.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(accent.opacity(0.12)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(scope)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(isMixed ? L("Custom grouping") : together ? L("Together") : L("Separate"))
        .help(affectsAllSections
              ? L("Sets Together or Separate for every sound section. Section selectors can override it. Changing mode sends no device command.")
              : L("Applies only to this section. Changing mode does not change current settings."))
    }

    private func choice(_ value: Bool, title: String, symbol: String) -> some View {
        Button { together = value } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title).font(AppType.caption.weight(.semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .foregroundStyle(!isMixed && together == value ? accent : Color.secondary)
            .background(!isMixed && together == value ? Brand.surface : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).disabled(value && !available)
        .accessibilityLabel(L("%@ · %@", scope, title))
        .accessibilityAddTraits(!isMixed && together == value ? [.isSelected] : [])
        .accessibilityIdentifier("\(identifier)-\(value ? "together" : "separate")")
    }
}

/// All daily sections share these columns. The narrow middle lane lets the
/// faders sit inward of the artwork without pushing the hearing aids apart.
struct SoundEarColumns<Left: View, Center: View, Right: View>: View {
    @ViewBuilder var left: () -> Left
    @ViewBuilder var center: () -> Center
    @ViewBuilder var right: () -> Right
    var body: some View {
        SoundEarColumnLayout {
            ZStack { Color.clear.frame(width: 0, height: 0); left() }
            ZStack { Color.clear.frame(width: 0, height: 0); center() }
            ZStack { Color.clear.frame(width: 0, height: 0); right() }
        }.frame(maxWidth: .infinity)
    }
}

private struct SoundEarColumnLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = min(640, proposal.width ?? 640)
        let sideWidth = max(0, (width - 96) / 2)
        let heights = subviews.enumerated().map { index, view in
            view.sizeThatFits(.init(width: index == 1 ? 96 : sideWidth, height: nil)).height
        }
        return CGSize(width: width, height: heights.max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sideWidth = max(0, (bounds.width - 96) / 2)
        for (index, view) in subviews.enumerated() {
            let x = index == 0 ? bounds.minX + sideWidth / 2 : index == 1 ? bounds.midX : bounds.maxX - sideWidth / 2
            view.place(at: .init(x: x, y: bounds.midY), anchor: .center,
                       proposal: .init(width: index == 1 ? 96 : sideWidth, height: bounds.height))
        }
    }
}

enum SoundGroupingPreferences {
    static let volumeKey = "groupedHearingAidControls"
    static let sectionKeys = ["groupedSpeechBoosterControls", "groupedProgramControls", "groupedEqualizerControls", "groupedStreamingControls", "groupedTinnitusControls"]
    static func setAll(_ together: Bool, defaults: UserDefaults) {
        // Intentionally run even if volume already has this value: a second
        // press on Together must clear any later per-section overrides.
        for key in [volumeKey] + sectionKeys { defaults.set(together, forKey: key) }
    }
    static func migrate(defaults: UserDefaults) {
        let previous = defaults.object(forKey: "groupedHearingAidControls") as? Bool ?? true
        for key in sectionKeys where defaults.object(forKey: key) == nil { defaults.set(previous, forKey: key) }
    }
}
