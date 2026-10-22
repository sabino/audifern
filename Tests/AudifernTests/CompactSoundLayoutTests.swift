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
        services.defaults.set("microphone", forKey: "equalizerSoundSection")
        services.defaults.set(false, forKey: "microphoneEqualizerDetailed")
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
        for control in views.filter({ ($0 is NSButton || $0 is NSSegmentedControl || $0 is NSPopUpButton)
            && !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 && $0.bounds.height > 0 }) {
            let frame = control.convert(control.bounds, to: host)
            #expect(host.bounds.contains(frame), "A native action escaped the short workspace: \(frame)")
        }
    }
}

@MainActor @Test func soundGroupingStaysCenteredWhenAHeaderHasNoLeadingTitle() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let host = NSHostingView(rootView: VStack(spacing: 12) {
        SoundSectionHeader {
            Text("Hearing aids")
        } center: {
            HeaderCenterProbe(name: "master").frame(width: 236, height: 38)
        } trailing: {
            Text("SpeechBooster")
        }
        SoundSectionHeader {
            EmptyView()
        } center: {
            HeaderCenterProbe(name: "equalizer").frame(width: 236, height: 38)
        } trailing: {
            Text("Tone controls")
        }
    }.frame(width: 672, height: 88))
    host.frame = NSRect(x: 0, y: 0, width: 672, height: 88)
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let centers = descendants(host).filter { ["master", "equalizer"].contains($0.identifier?.rawValue ?? "") }
    #expect(centers.count == 2)
    for center in centers {
        #expect(abs(center.convert(center.bounds, to: host).midX - host.bounds.midX) < 0.5)
    }
    #expect(host.window == nil)
}

private struct HeaderCenterProbe: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier(name)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
