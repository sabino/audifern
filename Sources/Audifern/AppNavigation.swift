import Combine
import Foundation

enum AppPage: String, CaseIterable, Identifiable {
    case hearingAids, sound, presets, programs, fitting, backups, devices, audiogram, settings, developer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hearingAids: L("Sound")
        case .sound: L("Equalizers")
        case .presets: L("Presets")
        case .programs: L("Library")
        case .fitting: L("Hearing profile")
        case .backups: L("Backups")
        case .devices: L("Devices")
        case .audiogram: L("Audiogram")
        case .settings: L("Settings")
        case .developer: L("Diagnostics")
        }
    }
    var symbol: String {
        switch self {
        case .hearingAids: "waveform"
        case .sound: "slider.horizontal.3"
        case .presets: "star"
        case .programs: "books.vertical"
        case .fitting: "person.crop.circle"
        case .backups: "externaldrive.badge.checkmark"
        case .devices: "ear.badge.waveform"
        case .audiogram: "chart.xyaxis.line"
        case .settings: "gearshape"
        case .developer: "waveform.path.ecg"
        }
    }
    var accessibilityID: String { self == .hearingAids ? "navigation-hearing-aids" : "navigation-\(rawValue)" }
    static let everydayPages: [AppPage] = [.hearingAids, .programs, .devices]
    static let workspacePages: [AppPage] = [.fitting]
    static let mainPages = everydayPages + workspacePages
}

/// Navigation and the editors belong to the app lifetime, not a feature window.
@MainActor
final class AppNavigation: ObservableObject {
    @Published var page: AppPage = .hearingAids
    @Published var sheet: AppSheet?
    @Published var sheetPath: [AppSheet] = []
    @Published var libraryPresets = false
    @Published var fittingStep: FittingPlanStep = .aboutYou
    @Published var presetNameDraft = ""

    func show(_ page: AppPage) {
        switch page {
        case .sound: present(.equalizers)
        case .presets: closeSheet(); libraryPresets = true; self.page = .programs
        case .programs: closeSheet(); libraryPresets = false; self.page = .programs
        case .backups: present(.backups)
        case .audiogram: present(.audiograms)
        case .settings: present(.settings)
        case .developer: present(.diagnostics)
        default: closeSheet(); self.page = page
        }
    }
    func present(_ destination: AppSheet) {
        if sheet == nil { sheetPath = []; sheet = destination }
        else if sheet == destination { sheetPath = [] }
        else if let existing = sheetPath.firstIndex(of: destination) { sheetPath = Array(sheetPath.prefix(through: existing)) }
        else { sheetPath.append(destination) }
    }
    func closeSheet() { sheet = nil; sheetPath = [] }
}

enum AppSheet: Hashable, Identifiable {
    case equalizers, savePreset, settings, about, diagnostics, backups, audiograms, savedFitting, fittingPlan, fittingReference, programDetails
    case device(UUID)
    case savedSnapshot(UUID), fittingReport(UUID)
    case backupComparison, backupInformation
    var id: Self { self }
    var title: String {
        switch self {
        case .equalizers: L("Equalizers")
        case .savePreset: L("Save current sound")
        case .settings: L("Settings")
        case .about: L("About Audifern")
        case .diagnostics: L("Diagnostics")
        case .backups: L("Backups")
        case .audiograms: L("Audiograms")
        case .savedFitting: L("Saved fitting")
        case .fittingPlan: L("Prepare a fitting plan")
        case .fittingReference: L("Fitting reference")
        case .programDetails: L("Program data")
        case .device: L("Device details")
        case .savedSnapshot: L("Saved fitting")
        case .fittingReport: L("Saved fitting summary")
        case .backupComparison: L("Compare backups")
        case .backupInformation: L("About backups")
        }
    }
}
