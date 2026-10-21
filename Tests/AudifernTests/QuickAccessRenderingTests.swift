import AppKit
import CompanionCore
import QuickAccessKit
import QuickAccessUI
import SwiftUI
import Testing
@testable import Audifern

/// Synthetic native views at real panel/widget dimensions. No window, radio,
/// private identifiers or sound commands are involved in these captures.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["AUDIFERN_QUICK_ACCESS_PREVIEWS"] != nil))
func renderQuickAccessSurfacesAndGroupedSoundAtTheirActualSizes() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["AUDIFERN_QUICK_ACCESS_PREVIEWS"]))
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let services = AudifernServices(demo: true)
    let initialWindows = NSApplication.shared.windows.count
    func render<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat, scheme: ColorScheme) throws {
        let content = view.environmentObject(services.preferences).environmentObject(services.navigation)
            .environmentObject(services.help).environmentObject(services.presets).environmentObject(services.equalizerDrafts)
            .defaultAppStorage(services.defaults).environment(\.colorScheme, scheme).environment(\.displayScale, 2)
            .frame(width: width, height: height).background(Brand.background).tint(Brand.accent)
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height); host.layoutSubtreeIfNeeded()
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = .init(width: width, height: height)
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try PrivateDocuments.writeNew(png, to: folder.appendingPathComponent(name + ".png"))
        #expect(host.window == nil && NSApplication.shared.windows.count == initialWindows)
    }
    let now = Date()
    let ears: [QuickEar] = [(.left, 76, 57_600), (.right, 68, 50_400)].map { side, battery, seconds in
        .init(side: side, connected: true, battery: battery,
            runtime: .init(percentage: battery, measuredAt: now, secondsAtMeasurement: Double(seconds), isCharging: false, isCharged: false),
            level: 0, muted: false, minimum: -8, maximum: 4, canChangeVolume: true, speechBooster: false, canChangeSpeechBooster: true)
    }
    let state = QuickAccessState(session: UUID(), updatedAt: now, sharingEnabled: true, ears: ears, paused: false, canReconnect: true, macAudio: false, canSwitchAudio: true)
    for (language, scheme) in [(AppLanguage.english, ColorScheme.light), (.portugueseBrazil, .dark), (.spanish, .light)] {
        services.preferences.language = language
        services.preferences.appearance = scheme == .light ? .light : .dark
        NSApplication.shared.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        for together in [true, false] {
            services.defaults.set(together, forKey: "groupedHearingAidControls")
            try render(ListenView(store: services.bluetooth), name: "sound-\(language.rawValue)-\(together ? "together" : "separate")", width: 960, height: 920, scheme: scheme)
            for expanded in [false, true] {
                services.preferences.menuBarExpanded = expanded
                let panel = MenuBarPanel(store: services.bluetooth, automation: services.connectionAutomation, help: services.help)
                try render(panel, name: "menu-\(language.rawValue)-\(together ? "together" : "separate")-\(expanded ? "expanded" : "compact")", width: expanded ? 422 : 382, height: expanded && !together ? 850 : expanded ? 760 : together ? 675 : 755, scheme: scheme)
            }
        }
        services.help.query = "battery"
        services.help.selection = "battery-alerts"
        try render(HelpView(), name: "help-\(language.rawValue)", width: 970, height: 650, scheme: scheme)
        try render(QuickAccessSettingsView(), name: "quick-settings-\(language.rawValue)", width: 675, height: 650, scheme: scheme)
    }
    for scheme in [ColorScheme.light, .dark] {
        NSApplication.shared.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        for (size, width, height, name) in [(QuickWidgetSize.small, 155, 155, "small"), (.medium, 329, 155, "medium"), (.large, 329, 345, "large")] {
            let widget = QuickWidgetView(state: state, date: now, size: size, artwork: AppResources.bundle.url(forResource: "HearingAid", withExtension: "png"), mark: nil) {
                if size != .small {
                    HStack {
                        Button {} label: { Image(systemName: "minus").frame(maxWidth: .infinity, minHeight: 23) }
                        Button {} label: { Label("Mute", systemImage: "speaker.wave.2").frame(maxWidth: .infinity, minHeight: 23) }
                        Button {} label: { Image(systemName: "plus").frame(maxWidth: .infinity, minHeight: 23) }
                    }.buttonStyle(.bordered).font(.system(size: 12))
                }
            }.padding(16)
            try render(widget, name: "widget-\(name)-\(scheme == .light ? "light" : "dark")", width: CGFloat(width), height: CGFloat(height), scheme: scheme)
        }
    }
}
