import AppKit
import CompanionCore
import SwiftUI
import Testing
@testable import Audifern

/// Opt-in: exercises real AppKit sheet presentation, including transitions that
/// an isolated NSHostingView render cannot cover. Uses synthetic data only.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["AUDIFERN_NATIVE_SHEET_TEST"] == "1"))
func nativeSheetsKeepTheirFrameWhenChangingSettingsAndOpeningAnAudiogram() async throws {
    for size in [CGSize(width: 1060, height: 740), CGSize(width: 1240, height: 960)] {
        try await exerciseNativeSheet(size: size)
    }
}

@MainActor private func exerciseNativeSheet(size: CGSize) async throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let services = AudifernServices(demo: true)
    services.preferences.language = .english
    services.preferences.appearance = .light
    let content = ContentView(store: services.bluetooth, audiogramStore: services.audiograms,
        notifications: services.batteryNotifications, fittingWorkspace: services.fittingWorkspace, backups: services.backups,
        connectionAutomation: services.connectionAutomation)
        .environmentObject(services.preferences).environmentObject(services.navigation)
        .environmentObject(services.presets).environmentObject(services.equalizerDrafts)
        .environmentObject(services.help)
        .defaultAppStorage(services.defaults)
    let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: 80, y: 80), size: size),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.title = "Audifern synthetic navigation test"
    window.contentView = NSHostingView(rootView: content)
    window.orderBack(nil)
    defer { window.orderOut(nil); window.close() }
    func stage(_ label: String) { fputs("NATIVE-SHEET \(Int(size.width))×\(Int(size.height)): \(label)\n", stderr) }
    func settle() async throws { try await Task.sleep(for: .milliseconds(700)) }
    func capture(_ target: NSWindow, name: String) throws {
        guard let output = ProcessInfo.processInfo.environment["AUDIFERN_NATIVE_SHEET_OUTPUT"] else { return }
        let folder = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let view = try #require(target.contentView)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try PrivateDocuments.writeNew(png, to: folder.appendingPathComponent("\(name)-\(Int(size.width)).png"))
    }
    stage("window shown")
    try await settle()
    let parentFrame = window.frame
    try capture(window, name: "main")
    services.navigation.page = .fitting
    services.navigation.present(.fittingPlan)
    try await settle()
    stage("plan shown")
    let sheet = try #require(window.attachedSheet)
    let sheetFrame = sheet.frame
    services.navigation.fittingStep = .audiogram
    try await settle()
    services.navigation.show(.audiogram)
    try await settle()
    stage("audiogram shown")
    #expect(window.attachedSheet === sheet)
    #expect(services.navigation.sheetPath == [.audiograms])
    #expect(sheet.frame == sheetFrame)
    #expect(window.frame == parentFrame)
    try capture(sheet, name: "audiogram")
    services.navigation.sheetPath.removeLast()
    try await settle()
    stage("returned to plan")
    #expect(services.navigation.fittingStep == .audiogram)
    services.navigation.closeSheet()
    try await settle()
    services.navigation.present(.settings)
    try await settle()
    let settings = try #require(window.attachedSheet)
    let settingsFrame = settings.frame
    for section in ["connections", "battery", "privacy", "diagnostics", "about", "general"] {
        services.defaults.set(section, forKey: "settingsSection")
        try await settle()
        stage("settings \(section)")
        #expect(window.attachedSheet === settings)
        #expect(settings.frame == settingsFrame)
        #expect(window.frame == parentFrame)
        try capture(settings, name: "settings-\(section)")
    }
    services.navigation.closeSheet()
    try await settle()
    #expect(window.attachedSheet == nil)
    #expect(services.bluetooth.isDemo)
    stage("complete")
}
