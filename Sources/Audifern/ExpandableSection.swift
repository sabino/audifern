import SwiftUI

/// Explicit, keyboard-focusable controls replace small disclosure triangles.
/// Callers keep their existing expansion state and all content stays inline.
struct ExpandableSection<Label: View, Content: View>: View {
    private let externalExpansion: Binding<Bool>?
    private let content: () -> Content
    private let label: () -> Label
    @State private var localExpanded = false
    private var expansion: Binding<Bool> { externalExpansion ?? $localExpanded }

    init(isExpanded: Binding<Bool>? = nil, @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder label: @escaping () -> Label) {
        externalExpansion = isExpanded; self.content = content; self.label = label
    }
    init(_ title: String, isExpanded: Binding<Bool>? = nil,
         @ViewBuilder content: @escaping () -> Content) where Label == Text {
        externalExpansion = isExpanded; self.content = content; self.label = { Text(title) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: expansion.wrappedValue ? 14 : 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                label()
                Spacer(minLength: 0)
                Button(expansion.wrappedValue ? L("Hide") : L("Show")) { expansion.wrappedValue.toggle() }
                    .buttonStyle(.bordered).font(AppType.body).controlSize(.small)
                    .accessibilityValue(expansion.wrappedValue ? L("Expanded") : L("Collapsed"))
            }
            if expansion.wrappedValue { content() }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
    }
}
