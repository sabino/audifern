import Combine

enum AppPage: String, CaseIterable, Identifiable {
    case hearingAids, sound, programs, fitting, backups, devices, audiogram, settings, developer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hearingAids: L("Listen")
        case .sound: L("Sound")
        case .programs: L("Programs")
        case .fitting: L("Fitting")
        case .backups: L("Backups")
        case .devices: L("Devices")
        case .audiogram: L("Audiogram")
        case .settings: L("Settings")
        case .developer: L("Developer")
        }
    }
    var symbol: String {
        switch self {
        case .hearingAids: "ear.badge.waveform"
        case .sound: "slider.horizontal.3"
        case .programs: "square.grid.2x2"
        case .fitting: "slider.horizontal.2.square"
        case .backups: "externaldrive.badge.checkmark"
        case .devices: "info.circle"
        case .audiogram: "chart.xyaxis.line"
        case .settings: "gearshape"
        case .developer: "chevron.left.forwardslash.chevron.right"
        }
    }
    var accessibilityID: String { self == .hearingAids ? "navigation-hearing-aids" : "navigation-\(rawValue)" }
    static let everydayPages: [AppPage] = [.hearingAids, .sound, .programs]
    static let workspacePages: [AppPage] = [.fitting, .audiogram, .backups, .devices]
    static let mainPages = everydayPages + workspacePages
}

/// Navigation and the editors belong to the app lifetime, not a feature window.
@MainActor
final class AppNavigation: ObservableObject {
    @Published var page: AppPage = .hearingAids
}
