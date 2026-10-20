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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        showIdentifiers = defaults.bool(forKey: "showDeviceIdentifiers")
        Localization.shared.language = language
    }
}
