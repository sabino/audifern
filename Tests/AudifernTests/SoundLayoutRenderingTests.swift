import AppKit
import CompanionCore
import SwiftUI
import Testing
@testable import Audifern

/// Opt-in visual review at the actual smallest sheet size. Synthetic devices,
/// no windows, no radio and no changes to the user's regular preferences.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["AUDIFERN_SOUND_LAYOUT_PREVIEWS"] != nil))
func renderAlignedSoundAndEverySettingsPageWithoutOpeningWindows() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["AUDIFERN_SOUND_LAYOUT_PREVIEWS"]))
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let services = AudifernServices(demo: true)
    let initialWindows = NSApplication.shared.windows.count
    func render<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat) throws {
        let host = NSHostingView(rootView: view
            .environmentObject(services.preferences).environmentObject(services.navigation)
            .environmentObject(services.help).environmentObject(services.presets).environmentObject(services.equalizerDrafts)
            .defaultAppStorage(services.defaults).environment(\.colorScheme, services.preferences.appearance.colorScheme ?? .light)
            .environment(\.displayScale, 2).font(AppType.body).controlSize(.large).tint(Brand.accent)
            .frame(width: width, height: height).background(Brand.background))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = .init(width: width, height: height)
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try PrivateDocuments.writeNew(try #require(bitmap.representation(using: .png, properties: [:])),
                                     to: folder.appendingPathComponent(name + ".png"))
        #expect(host.window == nil && NSApplication.shared.windows.count == initialWindows)
    }
    for language in [AppLanguage.english, .portugueseBrazil, .spanish] {
        services.preferences.language = language
        services.preferences.appearance = language == .portugueseBrazil ? .dark : .light
        NSApplication.shared.appearance = NSAppearance(named: language == .portugueseBrazil ? .darkAqua : .aqua)
        for grouped in [true, false] {
            services.defaults.set(grouped, forKey: "groupedHearingAidControls")
            for key in SoundGroupingPreferences.sectionKeys { services.defaults.set(grouped, forKey: key) }
            try render(ListenView(store: services.bluetooth), name: "sound-\(language.rawValue)-\(grouped ? "together" : "separate")", width: 800, height: 1240)
        }
        for (section, tabs) in [("general", [0]), ("connections", [0, 1, 2]), ("quickAccess", [0, 1]),
                                ("battery", [0]), ("privacy", [0]), ("diagnostics", [0]), ("about", [0])] {
            services.defaults.set(section, forKey: "settingsSection")
            for tab in tabs {
                services.defaults.set(tab, forKey: section == "connections" ? "connectionSettingsSection" : "quickAccessSettingsSection")
                try render(AppSettingsView(notifications: services.batteryNotifications, isDemo: true,
                                           connectionAutomation: services.connectionAutomation),
                           name: "settings-\(language.rawValue)-\(section)-\(tab)", width: 1020, height: 637)
            }
        }
    }
}
