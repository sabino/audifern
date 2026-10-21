import Foundation

enum FittingPlanStep: Int, CaseIterable, Identifiable {
    case aboutYou, hearingAids, audiogram, preferences, review
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .aboutYou: L("About you")
        case .hearingAids: L("Hearing aids")
        case .audiogram: L("Audiogram")
        case .preferences: L("Preferences")
        case .review: L("Review")
        }
    }
    var previous: Self? { Self(rawValue: rawValue - 1) }
    var next: Self? { Self(rawValue: rawValue + 1) }
}
