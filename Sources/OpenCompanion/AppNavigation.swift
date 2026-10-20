import Combine

enum AppPage: String, CaseIterable, Identifiable {
    case hearingAids, devices, audiogram, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hearingAids: "Hearing aids"
        case .devices: "Devices"
        case .audiogram: "Audiogram"
        case .settings: "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .hearingAids: "ear.badge.waveform"
        case .devices: "info.circle"
        case .audiogram: "chart.xyaxis.line"
        case .settings: "slider.horizontal.3"
        }
    }
}

/// Navigation and the editors belong to the app lifetime, not a feature window.
@MainActor
final class AppNavigation: ObservableObject {
    @Published var page: AppPage = .hearingAids
}
