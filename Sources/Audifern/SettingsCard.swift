import SwiftUI

/// Readable section headings and full-width native controls, without the
/// compact typography and intrinsic sizing of macOS GroupBox titles.
struct SettingsCard<Label: View, Content: View>: View {
    private let label: () -> Label
    private let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder label: @escaping () -> Label) {
        self.content = content; self.label = label
    }
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) where Label == Text {
        self.content = content; self.label = { Text(title) }
    }
    init(@ViewBuilder content: @escaping () -> Content) where Label == EmptyView {
        self.content = content; self.label = { EmptyView() }
    }
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 20) {
                label().font(AppType.headline)
                VStack(alignment: .leading, spacing: 16) { content() }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
