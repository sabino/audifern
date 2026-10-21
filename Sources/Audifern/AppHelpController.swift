import AppKit
import Combine
import SwiftUI

/// AppKit can search on a background thread. The handler only searches immutable
/// topic data; navigation is explicitly dispatched to the main actor.
final class NativeHelpSearch: NSObject, NSUserInterfaceItemSearching {
    private let selected: @MainActor @Sendable (String) -> Void
    private let all: @MainActor @Sendable (String) -> Void
    init(selected: @escaping @MainActor @Sendable (String) -> Void, all: @escaping @MainActor @Sendable (String) -> Void) {
        self.selected = selected; self.all = all
    }
    func searchForItems(withSearch searchString: String, resultLimit: Int, matchedItemHandler: @escaping ([Any]) -> Void) {
        matchedItemHandler(HelpCatalog.search(searchString, limit: resultLimit).map(\.id))
    }
    func localizedTitles(forItem item: Any) -> [String] {
        guard let id = item as? String, let topic = HelpCatalog.topic(id) else { return [] }
        return topic.localizedPath
    }
    func performAction(forItem item: Any) {
        guard let id = item as? String, HelpCatalog.topic(id) != nil else { return }
        Task { @MainActor [selected] in selected(id) }
    }
    func showAllHelpTopics(forSearch searchString: String) { Task { @MainActor [all] in all(searchString) } }
}

@MainActor final class AppHelpController: ObservableObject {
    @Published var query = ""
    @Published var selection: String? = "getting-started"
    var showMain: (() -> Void)?
    private let navigation: AppNavigation
    private let defaults: UserDefaults
    private var searchHandler: NativeHelpSearch?
    init(navigation: AppNavigation, defaults: UserDefaults) { self.navigation = navigation; self.defaults = defaults }
    func installNativeSearch() {
        guard searchHandler == nil else { return }
        let handler = NativeHelpSearch(selected: { [weak self] in self?.openFeature($0) }, all: { [weak self] in self?.openHelp(query: $0) })
        searchHandler = handler
        NSApplication.shared.registerUserInterfaceItemSearchHandler(handler)
    }
    func openHelp(query: String = "") {
        self.query = query
        selection = HelpCatalog.search(query).first?.id ?? "getting-started"
        navigation.present(.help); showMain?()
    }
    func openFeature(_ id: String) {
        guard let topic = HelpCatalog.topic(id) else { return }
        if ["microphone-eq", "stream-eq", "tinnitus"].contains(id) {
            defaults.set(id == "stream-eq" ? "streaming" : id == "tinnitus" ? "tinnitus" : "microphone", forKey: "equalizerSoundSection")
        }
        if id == "menu-bar" || id == "widgets" {
            defaults.set(id == "widgets" ? 1 : 0, forKey: "quickAccessSettingsSection")
        }
        switch topic.destination {
        case .sound: navigation.show(.hearingAids)
        case .equalizers: navigation.show(.sound)
        case .library: navigation.show(.programs)
        case .presets: navigation.show(.presets)
        case .programs: navigation.present(.programDetails)
        case .devices: navigation.show(.devices)
        case .audiograms: navigation.present(.audiograms)
        case .fitting: navigation.present(.fittingPlan)
        case .savedFitting: navigation.present(.savedFitting)
        case .backups: navigation.present(.backups)
        case .diagnostics: navigation.present(.diagnostics)
        case .about: navigation.present(.about)
        case .settings(let section, let tab):
            defaults.set(section, forKey: "settingsSection")
            if let tab { defaults.set(tab, forKey: "connectionSettingsSection") }
            navigation.present(.settings)
        }
        showMain?()
    }
    @discardableResult func openURL(_ url: URL) -> Bool {
        guard url.scheme == "audifern", url.host == "feature", url.query == nil, url.fragment == nil else { return false }
        let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard HelpCatalog.topic(id) != nil else { return false }
        openFeature(id); return true
    }
}

struct HelpPresentationAccess: ViewModifier {
    @ObservedObject var help: AppHelpController
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onAppear {
            help.showMain = { openWindow(id: "main"); NSApplication.shared.activate(ignoringOtherApps: true) }
            help.installNativeSearch()
        }.onOpenURL { _ = help.openURL($0) }
    }
}
