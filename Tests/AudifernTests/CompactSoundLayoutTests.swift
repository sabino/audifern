import AppKit
import SwiftUI
import Testing
@testable import Audifern

/// Exercises native slider sizing, rather than asserting SwiftUI frame literals.
/// No windows, Bluetooth, or system audio changes are involved.
@MainActor @Test func compactSoundKeepsBothEarsFadersInsideAShortViewport() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let services = AudifernServices(demo: true)
    services.preferences.language = .portugueseBrazil
    for grouped in [true, false] {
        services.preferences.groupAllSoundControls(grouped)
        services.defaults.set(false, forKey: "soundDevicesExpanded")
        let host = NSHostingView(rootView: ListenView(store: services.bluetooth)
            .environmentObject(services.preferences).environmentObject(services.navigation)
            .environmentObject(services.equalizerDrafts)
            .defaultAppStorage(services.defaults)
            .font(AppType.body).controlSize(.large).tint(Brand.accent)
            .frame(width: 740, height: 700))
        host.frame = NSRect(x: 0, y: 0, width: 740, height: 700)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let views = descendants(host)
        #expect(host.window == nil)
        #expect(!views.contains { $0 is NSScrollView })
        let volumes = views.compactMap { $0 as? ReleaseVolumeSlider }
        let equalizers = views.compactMap { $0 as? NSSlider }.filter { !($0 is ReleaseVolumeSlider) }
        #expect(volumes.count == (grouped ? 1 : 2))
        #expect(equalizers.count == (grouped ? 3 : 6))
        for slider in volumes {
            #expect(slider.isVertical == false && slider.bounds.width > slider.bounds.height)
        }
        for slider in volumes + equalizers {
            let frame = slider.convert(slider.bounds, to: host)
            #expect(host.bounds.contains(frame), "A native fader escaped the short workspace: \(frame)")
        }
    }
}
