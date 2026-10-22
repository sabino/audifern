import Combine
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: L("System"); case .light: L("Light"); case .dark: L("Dark") }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

/// Appearance and language never alter hearing-aid settings. Identifiers stay
/// hidden by default, including in local diagnostics and public screenshots.
@MainActor final class AppPreferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: "language"); Localization.shared.language = language }
    }
    @Published var showIdentifiers: Bool { didSet { defaults.set(showIdentifiers, forKey: "showDeviceIdentifiers") } }
    @Published var showMenuBar: Bool { didSet { defaults.set(showMenuBar, forKey: "showMenuBar") } }
    @Published var menuBarExpanded: Bool { didSet { defaults.set(menuBarExpanded, forKey: "menuBarExpanded") } }
    @Published var menuBarArtwork: Bool { didSet { defaults.set(menuBarArtwork, forKey: "menuBarArtwork") } }
    @Published var menuBarTime: Bool { didSet { defaults.set(menuBarTime, forKey: "menuBarTime") } }
    @Published var menuBarSound: Bool { didSet { defaults.set(menuBarSound, forKey: "menuBarSound") } }
    @Published var menuBarPrograms: Bool { didSet { defaults.set(menuBarPrograms, forKey: "menuBarPrograms") } }
    @Published var menuBarAudio: Bool { didSet { defaults.set(menuBarAudio, forKey: "menuBarAudio") } }
    @Published var menuBarLabel: String { didSet { defaults.set(menuBarLabel, forKey: "menuBarLabel") } }
    @Published var widgetsEnabled: Bool { didSet { defaults.set(widgetsEnabled, forKey: "widgetsEnabled") } }
    @Published private(set) var quickProgramSelections: [String: [Int]] {
        didSet { defaults.set(quickProgramSelections, forKey: "quickProgramSelections") }
    }

    func setQuickProgram(_ id: Int, included: Bool, catalog: ProgramShortcutCatalog) {
        guard let selection = catalog.selection(changing: id, included: included, saved: quickProgramSelections[catalog.scope]) else { return }
        quickProgramSelections[catalog.scope] = selection
    }

    func groupAllSoundControls(_ together: Bool) {
        SoundGroupingPreferences.setAll(together, defaults: defaults)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        showIdentifiers = defaults.bool(forKey: "showDeviceIdentifiers")
        showMenuBar = defaults.object(forKey: "showMenuBar") as? Bool ?? true
        menuBarExpanded = defaults.bool(forKey: "menuBarExpanded")
        menuBarArtwork = defaults.object(forKey: "menuBarArtwork") as? Bool ?? true
        menuBarTime = defaults.object(forKey: "menuBarTime") as? Bool ?? true
        menuBarSound = defaults.object(forKey: "menuBarSound") as? Bool ?? true
        menuBarPrograms = defaults.object(forKey: "menuBarPrograms") as? Bool ?? true
        menuBarAudio = defaults.object(forKey: "menuBarAudio") as? Bool ?? true
        menuBarLabel = ["icon", "minimum", "both"].contains(defaults.string(forKey: "menuBarLabel") ?? "") ? defaults.string(forKey: "menuBarLabel")! : "icon"
        widgetsEnabled = defaults.object(forKey: "widgetsEnabled") as? Bool ?? true
        quickProgramSelections = defaults.dictionary(forKey: "quickProgramSelections") as? [String: [Int]] ?? [:]
        Localization.shared.language = language
    }
}
