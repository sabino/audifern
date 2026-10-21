import SwiftUI

struct SidebarNavigationButton: View {
    let title: String
    let symbol: String
    let selected: Bool
    let identifier: String
    var action: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(AlignedLabelStyle())
                .font(AppType.body.weight(selected ? .semibold : .medium))
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 12)
                .foregroundStyle(selected ? Brand.accent : Color.primary)
                .background(selected ? Brand.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(focused ? Brand.accent.opacity(0.7) : .clear, lineWidth: 2))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).focused($focused).focusEffectDisabled()
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityIdentifier(identifier)
    }
}
