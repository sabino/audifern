import AppKit
import CompanionCore
import Foundation
import SwiftUI
import Testing
@testable import Audifern

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["AUDIFERN_PREVIEW_OUTPUT"] != nil))
func renderAboutAndContributionsWithoutOpeningLinksOrBluetooth() throws {
    let output = try #require(ProcessInfo.processInfo.environment["AUDIFERN_PREVIEW_OUTPUT"])
    let folder = URL(fileURLWithPath: output, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    NSApplication.shared.setActivationPolicy(.prohibited)
    let services = AudifernServices(demo: true)
    let cases: [(String, AppLanguage, ColorScheme, AboutView.ContributionMethod, DonationAsset, Int, Int)] = [
        ("en-mp", .english, .light, .mercadoPago, .bitcoin, 900, 638),
        ("en-btc", .english, .light, .cryptocurrency, .bitcoin, 900, 638),
        ("pt-btc", .portugueseBrazil, .light, .cryptocurrency, .bitcoin, 609, 598),
        ("es-usdc", .spanish, .light, .cryptocurrency, .usdc, 609, 598),
        ("en-eth-dark", .english, .dark, .cryptocurrency, .ethereum, 714, 638),
        ("pt-sol-dark", .portugueseBrazil, .dark, .cryptocurrency, .solana, 609, 598)
    ]
    for (name, language, scheme, method, asset, width, height) in cases {
        services.preferences.language = language
        services.preferences.appearance = scheme == .light ? .light : .dark
        NSApplication.shared.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        let content = AboutView(initialMethod: method, initialAsset: asset)
            .environmentObject(services.preferences).environment(\.colorScheme, scheme)
            .frame(width: CGFloat(width), height: CGFloat(height)).background(Brand.background)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.window == nil && services.bluetooth.isDemo)
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try PrivateDocuments.writeNew(png, to: folder.appendingPathComponent("about-\(name).png"))
    }
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["AUDIFERN_PREVIEW_OUTPUT"] != nil))
func renderContextualTaskSheetsAndEveryGuidedPlanStepWithoutWindows() throws {
    let output = try #require(ProcessInfo.processInfo.environment["AUDIFERN_PREVIEW_OUTPUT"])
    let folder = URL(fileURLWithPath: output, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    NSApplication.shared.setActivationPolicy(.prohibited)
    let services = AudifernServices(demo: true)
    let windowCount = NSApplication.shared.windows.count
    let routes: [(String, AppSheet)] = [
        ("equalizers", .equalizers), ("save-preset", .savePreset), ("settings", .settings),
        ("settings-battery", .settings), ("settings-privacy", .settings), ("backups", .backups), ("audiograms", .audiograms), ("saved-fitting", .savedFitting),
        ("device-details", .device(DemoData.leftID)), ("backup-comparison", .backupComparison)
    ] + FittingPlanStep.allCases.map { ("plan-\($0.rawValue)", AppSheet.fittingPlan) }
    for (name, route) in routes {
      for scheme in [ColorScheme.light, .dark] {
        services.preferences.language = .english
        services.preferences.appearance = scheme == .light ? .light : .dark
        if name.hasPrefix("plan-"), let number = Int(name.dropFirst(5)), let step = FittingPlanStep(rawValue: number) {
            services.navigation.fittingStep = step
        }
        services.defaults.set(name == "settings-battery" ? "battery" : name == "settings-privacy" ? "privacy" : "general", forKey: "settingsSection")
        services.navigation.sheet = route; services.navigation.sheetPath = []
        NSApplication.shared.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        let content = AppTaskSheet(store: services.bluetooth, workspace: services.fittingWorkspace, backups: services.backups,
            audiograms: services.audiograms, notifications: services.batteryNotifications)
            .environmentObject(services.preferences).environmentObject(services.navigation)
            .environmentObject(services.presets).environmentObject(services.equalizerDrafts)
            .defaultAppStorage(services.defaults).environment(\.colorScheme, scheme)
            .frame(width: 1000, height: 920).background(Brand.background)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 1000, height: 920)
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.window == nil && NSApplication.shared.windows.count == windowCount)
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try PrivateDocuments.writeNew(png, to: folder.appendingPathComponent("sheet-\(name)-\(scheme == .light ? "light" : "dark").png"))
      }
    }
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["AUDIFERN_PREVIEW_OUTPUT"] != nil))
func renderEverydayNavigationWithoutOpeningAWindowOrBluetooth() throws {
    let output = try #require(ProcessInfo.processInfo.environment["AUDIFERN_PREVIEW_OUTPUT"])
    let folder = URL(fileURLWithPath: output, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    NSApplication.shared.setActivationPolicy(.prohibited)
    let services = AudifernServices(demo: true)
    let cases: [(AppPage, AppLanguage, ColorScheme, Int, Int)] = [
        (.hearingAids, .english, .light, 1240, 1100),
        (.hearingAids, .english, .dark, 1080, 1100),
        (.hearingAids, .portugueseBrazil, .light, 1080, 1100),
        (.hearingAids, .spanish, .light, 1080, 1100),
        (.sound, .english, .light, 1080, 1100),
        (.presets, .english, .dark, 1080, 1100),
        (.programs, .english, .light, 1080, 1100)
    ]
    for (page, language, scheme, width, height) in cases {
        services.preferences.language = language
        services.preferences.appearance = scheme == .light ? .light : .dark
        services.navigation.page = page
        NSApplication.shared.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        let content = ContentView(store: services.bluetooth, audiogramStore: services.audiograms,
            notifications: services.batteryNotifications, fittingWorkspace: services.fittingWorkspace, backups: services.backups)
            .environmentObject(services.preferences).environmentObject(services.navigation)
            .environmentObject(services.presets).environmentObject(services.equalizerDrafts)
            .defaultAppStorage(services.defaults)
            .environment(\.colorScheme, scheme).preferredColorScheme(scheme)
            .frame(width: CGFloat(width), height: CGFloat(height)).background(Brand.background)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.window == nil && services.bluetooth.isDemo)
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        #expect(bitmap.pixelsWide == width && bitmap.pixelsHigh == height)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try PrivateDocuments.writeNew(png, to: folder.appendingPathComponent("everyday-\(page.rawValue)-\(language.rawValue)-\(scheme == .light ? "light" : "dark")-\(width).png"))
    }
}

/// Optional artifact check used during UI work. An in-memory hosting view paints
/// synthetic content; it does not open, focus or capture a Mac window. Window
/// chrome, menu behavior and onscreen interaction remain separate checks.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["AUDIFERN_PREVIEW_OUTPUT"] != nil))
func renderSyntheticWorkspacePreviewsWithoutBluetoothOrPrivateData() throws {
    let output = try #require(ProcessInfo.processInfo.environment["AUDIFERN_PREVIEW_OUTPUT"])
    let folder = URL(fileURLWithPath: output, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    NSApplication.shared.setActivationPolicy(.prohibited)
    let services = AudifernServices(demo: true)
    services.preferences.language = .english
    services.fittingWorkspace.draft.name = L("Everyday clarity")
    services.fittingWorkspace.draft.programs = [.init(name: L("Everyday"), purpose: .everyday), .init(name: L("Music"), purpose: .music)]
    #expect(services.bluetooth.isDemo && services.backups.entries.isEmpty)
    for scheme in [ColorScheme.light, .dark] {
      for width in [1120, 820] {
        NSApplication.shared.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        let workspace = FittingWorkspaceView(store: services.bluetooth, audiograms: services.audiograms,
            draft: Binding(get: { services.fittingWorkspace.draft }, set: { services.fittingWorkspace.draft = $0 }),
            saveDraft: {}, loadDraft: {}, canLoadDraft: false)
            .environmentObject(services.preferences).environmentObject(services.navigation)
            .environment(\.colorScheme, scheme).preferredColorScheme(scheme)
            .frame(width: CGFloat(width), height: 1120).background(Brand.background).tint(Brand.accent)
        // AppKit-backed controls and ScrollView are not supported by
        // ImageRenderer. Paint the in-memory hosting view instead; no window
        // is created or ordered and no screen coordinates are sampled.
        let hosting = NSHostingView(rootView: workspace)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 1120)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        #expect(bitmap.pixelsWide == width && bitmap.pixelsHigh == 1120)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        // Compare sampled pixels: file size alone accepts blank images with a
        // large color profile. Refuse to call an empty render a visual check.
        var colors = Set<String>()
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 13) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 13) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    colors.insert("\(Int(color.redComponent * 255))/\(Int(color.greenComponent * 255))/\(Int(color.blueComponent * 255))")
                }
            }
        }
        #expect(colors.count > 30, "The render is blank or incomplete; onscreen UI verification is still required.")
        try png.write(to: folder.appendingPathComponent("fitting-\(scheme == .light ? "light" : "dark")-\(width).png"))
      }
    }
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["AUDIFERN_PREVIEW_OUTPUT"] != nil))
func renderDetailedConsumerEQWithReportedAndMissingFrequencyLabels() throws {
    let output = try #require(ProcessInfo.processInfo.environment["AUDIFERN_PREVIEW_OUTPUT"])
    let folder = URL(fileURLWithPath: output, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let services = AudifernServices(demo: true)
    services.preferences.language = .english
    NSApplication.shared.setActivationPolicy(.prohibited)
    var aids = services.bluetooth.orderedConnections
    #expect(aids.count == 2)
    for index in aids.indices {
        aids[index].microphoneEqualizer = try .init(rawSteps: [1, 2, 3, 0, -1, -2, 0, 2],
            minimumSteps: .init(repeating: -24, count: 8), maximumSteps: .init(repeating: 24, count: 8),
            stepDB: 0.25, frequenciesHz: index == 0 ? [250, 500, 1000, 2000, 3000, 4000, 6000, 8000] : nil)
    }
    for scheme in [ColorScheme.light, .dark] {
        for width in [1120, 820] {
            NSApplication.shared.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            let content = Surface {
                PairedEqualizerView(store: services.bluetooth, aids: aids, microphone: true,
                    linked: .constant(false), canLink: false, detailed: true)
            }.padding(30)
                .environmentObject(services.preferences).environmentObject(services.equalizerDrafts)
                .environment(\.colorScheme, scheme).preferredColorScheme(scheme)
                .frame(width: CGFloat(width), height: 620, alignment: .topLeading).background(Brand.background).tint(Brand.accent)
            let hosting = NSHostingView(rootView: content)
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: 620)
            hosting.layoutSubtreeIfNeeded()
            let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try PrivateDocuments.writeNew(png, to: folder.appendingPathComponent("consumer-eight-band-\(scheme == .light ? "light" : "dark")-\(width).png"))
        }
    }
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["AUDIFERN_PREVIEW_OUTPUT"] != nil))
func renderSyntheticFittingHistoryWithoutOpeningAWindow() throws {
    let output = try #require(ProcessInfo.processInfo.environment["AUDIFERN_PREVIEW_OUTPUT"])
    let folder = URL(fileURLWithPath: output, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let workspace = FittingWorkspaceStore(file: temporary.appendingPathComponent("plan.json"))
    workspace.draft.name = "Everyday clarity"; workspace.draft.model = .intent3
    workspace.draft.programs = [.init(name: "Everyday", purpose: .everyday)]
    workspace.save()
    workspace.draft.programs.append(.init(name: "Music", purpose: .music))
    workspace.draft.rationale = .vacPlus; workspace.save()
    workspace.draft.leftAcoustics.receiver = "Recorded speaker"
    workspace.draft.rightAcoustics.coupling = .ventedDome
    workspace.draft.listeningGoals = "Discuss conversations and music"
    workspace.draft.adaptation = .step2
    #expect(workspace.revisions.count == 2)
    NSApplication.shared.setActivationPolicy(.prohibited)
    for scheme in [ColorScheme.light, .dark] {
        for width in [1120, 820] {
            NSApplication.shared.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            let content = FittingPlanHistoryView(workspace: workspace, expanded: true)
                .padding(30).environment(\.colorScheme, scheme).preferredColorScheme(scheme)
                .frame(width: CGFloat(width), height: 460, alignment: .topLeading).background(Brand.background).tint(Brand.accent)
            let hosting = NSHostingView(rootView: content)
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: 460)
            hosting.layoutSubtreeIfNeeded()
            let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            #expect(bitmap.pixelsWide == width && bitmap.pixelsHigh == 460)
            try PrivateDocuments.writeNew(png, to: folder.appendingPathComponent("plan-history-\(scheme == .light ? "light" : "dark")-\(width).png"))
        }
    }
}
