import AppKit
import SwiftUI
import Testing
@testable import Audifern

/// Current native views, synthetic releases and devices, no windows or radio.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["AUDIFERN_CONNECTION_UPDATE_REVIEW"] != nil))
func renderConnectionAndUpdateReviewWithoutWindows() async throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["AUDIFERN_CONNECTION_UPDATE_REVIEW"]))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let preferences = UserDefaults(suiteName: "org.audifern.preview")!
    let saved = preferences.persistentDomain(forName: "org.audifern.preview")
    defer {
        if let saved { preferences.setPersistentDomain(saved, forName: "org.audifern.preview") }
        else { preferences.removePersistentDomain(forName: "org.audifern.preview") }
    }
    let services = AudifernServices(demo: true)
    let initialWindows = NSApplication.shared.windows.count
    func render<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat, scheme: ColorScheme, updates: AppUpdateController? = nil) throws {
        let root = view.environmentObject(services.preferences).environmentObject(services.navigation)
            .environmentObject(services.help).environmentObject(services.presets).environmentObject(services.equalizerDrafts)
            .environment(\.appUpdates, updates).defaultAppStorage(services.defaults)
            .environment(\.colorScheme, scheme).environment(\.displayScale, 2)
            .frame(width: width, height: height).background(Brand.background).tint(Brand.accent)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height); host.layoutSubtreeIfNeeded()
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = .init(width: width, height: height)
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try PrivateDocuments.writeNew(png, to: directory.appendingPathComponent(name + ".png"))
        #expect(host.window == nil && NSApplication.shared.windows.count == initialWindows)
        #expect(png.count > 2_000)
    }
    for (language, scheme) in [(AppLanguage.english, ColorScheme.light), (.portugueseBrazil, .dark), (.spanish, .light)] {
        services.preferences.language = language
        services.preferences.appearance = scheme == .light ? .light : .dark
        NSApplication.shared.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        for installation in [AppInstallation.malt, .direct, .uncertain] {
            let updater = TestUpdateClient()
            let model = AppUpdateController(version: "0.9.0", detect: { installation }, fetch: {
                [AppRelease(tagName: "v0.9.1", name: "Synthetic review release", body: "Synthetic release notes for interface review only.",
                            htmlURL: URL(string: "https://github.com/sabino/audifern/releases/tag/v0.9.1")!, draft: false, prerelease: false)]
            }, startAutomatically: false, makeUpdater: { _ in updater })
            await model.checkForUpdates()
            services.defaults.set("updates", forKey: "settingsSection")
            services.navigation.closeSheet(); services.navigation.present(.settings)
            let sheet = AppTaskSheet(store: services.bluetooth, workspace: services.fittingWorkspace, backups: services.backups,
                                     audiograms: services.audiograms, notifications: services.batteryNotifications,
                                     availableSize: .init(width: 1040, height: 760), connectionAutomation: services.connectionAutomation)
            try render(sheet, name: "updates-\(language.rawValue)-\(String(describing: installation))", width: 1040, height: 760, scheme: scheme, updates: model)
        }
        let menu = MenuBarPanel(store: services.bluetooth, automation: services.connectionAutomation, help: services.help)
        let menuWidth: CGFloat = services.preferences.menuBarExpanded ? 422 : 382
        let measure = NSHostingView(rootView: menu.environmentObject(services.preferences).defaultAppStorage(services.defaults).fixedSize(horizontal: false, vertical: true))
        measure.frame.size.width = menuWidth
        try render(menu, name: "menu-\(language.rawValue)", width: menuWidth, height: ceil(measure.fittingSize.height), scheme: scheme)
        try render(MenuConnectionControls(connectedCount: 0, targetCount: 2, connecting: false, disconnecting: false,
                                          preview: false, poweredOn: true, status: L("Trying again in %d seconds", 23), connect: {}, disconnect: {}).padding(18),
                   name: "disconnected-controls-\(language.rawValue)", width: 382, height: 110, scheme: scheme)
        try render(EarControlModePicker(together: .constant(false), available: false, scope: L("Volume and mute"), identifier: "review-grouping").padding(18),
                   name: "disabled-grouping-\(language.rawValue)", width: 280, height: 80, scheme: scheme)
    }
}
