import SwiftUI

/// SF Symbols have different intrinsic widths. Reserve the same optical slot
/// so labels and controls do not move when a symbol or selection changes.
struct AlignedLabelStyle: LabelStyle {
    var iconSize: CGFloat = 18
    var iconWidth: CGFloat = 24
    var spacing: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: spacing) {
            configuration.icon.font(.system(size: iconSize, weight: .medium))
                .frame(width: iconWidth, height: 26)
            configuration.title
        }
    }
}
