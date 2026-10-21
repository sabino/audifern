import AppKit
import CompanionCore
import SwiftUI
import Testing
@testable import Audifern

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["AUDIFERN_INLINE_EQ_PREVIEWS"] != nil))
func renderInlineEqualizersInBothGroupingModesAndAllLanguages() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["AUDIFERN_INLINE_EQ_PREVIEWS"]))
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let services = AudifernServices(demo: true)
    let workspaceOnly = ProcessInfo.processInfo.environment["AUDIFERN_SOUND_WORKSPACE_ONLY"] == "1"
    let initialWindows = NSApplication.shared.windows.count
    func render<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat) throws {
        let host = NSHostingView(rootView: view
            .environmentObject(services.preferences).environmentObject(services.navigation).environmentObject(services.help)
            .environmentObject(services.presets).environmentObject(services.equalizerDrafts)
            .defaultAppStorage(services.defaults).environment(\.displayScale, 2)
            .environment(\.colorScheme, services.preferences.appearance.colorScheme ?? .light)
            .font(AppType.body).controlSize(.large).tint(Brand.accent)
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
    let aids = services.bluetooth.orderedConnections.sorted { $0.sideLabel == "Left" && $1.sideLabel != "Left" }
    for language in [AppLanguage.english, .portugueseBrazil, .spanish] {
        services.preferences.language = language
        services.preferences.appearance = language == .portugueseBrazil ? .dark : .light
        NSApplication.shared.appearance = NSAppearance(named: language == .portugueseBrazil ? .darkAqua : .aqua)
        for grouped in [true, false] {
            services.preferences.groupAllSoundControls(grouped)
            services.defaults.set("microphone", forKey: "equalizerSoundSection")
            try render(ListenView(store: services.bluetooth),
                       name: "sound-\(language.rawValue)-\(grouped ? "together" : "separate")", width: 800, height: 740)
            if !grouped {
                services.defaults.set("tinnitus", forKey: "equalizerSoundSection")
                try render(ListenView(store: services.bluetooth), name: "tinnitus-\(language.rawValue)", width: 800, height: 700)
                services.defaults.set("streaming", forKey: "equalizerSoundSection")
                try render(ListenView(store: services.bluetooth), name: "short-\(language.rawValue)", width: 740, height: 700)
                services.defaults.set("microphone", forKey: "equalizerSoundSection")
            }
            services.defaults.set(true, forKey: "soundDevicesExpanded")
            try render(ListenView(store: services.bluetooth), name: "expanded-\(language.rawValue)-\(grouped ? "together" : "separate")", width: 800, height: 740)
            services.defaults.set(false, forKey: "soundDevicesExpanded")
            if workspaceOnly { continue }
            for microphone in [true, false] {
                for detailed in [false, true] {
                    try render(PairedEqualizerView(store: services.bluetooth, aids: aids, microphone: microphone,
                                                  linked: .constant(grouped), canLink: true, detailed: detailed).padding(12),
                               name: "eq-\(language.rawValue)-\(microphone ? "microphone" : "streaming")-\(grouped ? "together" : "separate")-\(detailed ? "eight" : "three")",
                               width: 719, height: 690)
                }
            }
        }
        if workspaceOnly { continue }
        for section in DeviceInformationPanel.Section.allCases {
            try render(DeviceInformationPanel(store: services.bluetooth, id: DemoData.leftID, section: section),
                name: "device-\(language.rawValue)-\(section.rawValue)", width: 960, height: 597)
        }
        if language != .spanish {
            var mixedAids = aids
            mixedAids[0].microphoneEqualizer = try .init(rawSteps: [0, 2, -1, 1, 0, 3, -2, 0],
                minimumSteps: .init(repeating: -6, count: 8), maximumSteps: .init(repeating: 6, count: 8), stepDB: 1)
            mixedAids[1].microphoneEqualizer = try .init(rawSteps: [1, -2, -1, 2, -1, 0, -2, 1],
                minimumSteps: .init(repeating: -6, count: 8), maximumSteps: .init(repeating: 6, count: 8), stepDB: 1)
            for detailed in [false, true] {
                try render(PairedEqualizerView(store: services.bluetooth, aids: mixedAids, microphone: true,
                    linked: .constant(true), canLink: true, detailed: detailed).padding(12),
                    name: "eq-\(language.rawValue)-mixed-\(detailed ? "eight" : "three")", width: 719, height: 690)
            }
        }

    }
}
