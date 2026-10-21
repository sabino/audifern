import AppKit
import CompanionCore
import Foundation
import SwiftUI
import Testing
@testable import Audifern

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
