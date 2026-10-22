import SwiftUI

struct HelpView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var help: AppHelpController
    private var matches: [HelpTopic] { HelpCatalog.search(help.query) }
    private var selected: HelpTopic? { matches.first { $0.id == help.selection } ?? matches.first }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Search features and help"), text: $help.query).textFieldStyle(.plain)
                    .accessibilityIdentifier("help-search")
                if !help.query.isEmpty { Button { help.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel(L("Clear search")) }
            }.font(AppType.body).padding(18).background(Brand.surface)
            Divider()
            HStack(spacing: 0) {
                List(matches, selection: $help.selection) { topic in
                    Label { VStack(alignment: .leading, spacing: 4) {
                        Text(L(topic.title)).font(AppType.callout.weight(.medium))
                        Text(topic.path.map { L($0) }.joined(separator: " › ")).font(AppType.caption).foregroundStyle(.secondary)
                    }} icon: { Image(systemName: topic.symbol).frame(width: 23) }
                        .padding(.vertical, 6).tag(topic.id)
                }.listStyle(.sidebar).frame(width: 280).accessibilityIdentifier("help-topics")
                Divider()
                if let selected {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Image(systemName: selected.symbol).font(.system(size: 30)).foregroundStyle(Brand.accent)
                                .frame(width: 60, height: 60).background(Brand.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                            Text(L(selected.title)).font(.system(size: 30, weight: .bold))
                            Text(L(selected.summary)).font(AppType.headline).foregroundStyle(.secondary)
                            Text(L(selected.guidance)).font(AppType.body).lineSpacing(6).textSelection(.enabled)
                            Button { help.openFeature(selected.id) } label: {
                                Label(L("Open %@", L(selected.title)), systemImage: "arrow.up.forward")
                            }.buttonStyle(.borderedProminent).tint(Brand.controlTint).font(AppType.body).accessibilityIdentifier("help-open-feature")
                            Text(selected.localizedPath.joined(separator: " › ")).font(AppType.caption).foregroundStyle(.secondary)
                        }.padding(30).frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                } else { ContentUnavailableView(L("No matching features"), systemImage: "magnifyingglass", description: Text(L("Try a feature name such as battery, volume or Bluetooth."))).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }.background(Brand.background)
    }
}
