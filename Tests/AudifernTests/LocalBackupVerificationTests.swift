import AppKit
import CompanionCore
import Foundation
import SwiftUI
import Testing
@testable import Audifern

/// Explicit local fixture only. CI has no fixture, aid connection, credentials
/// or personal data. Nothing from this verification is embedded in the source.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["AUDIFERN_LOCAL_BACKUP"] != nil))
func verifyExplicitLocalFittingArchiveAndRenderItsInspectorWithoutBluetooth() throws {
    let path = try #require(ProcessInfo.processInfo.environment["AUDIFERN_LOCAL_BACKUP"])
    let bytes = try PrivateDocuments.read(URL(fileURLWithPath: path), maximumBytes: DeviceBackupArchive.maximumBytes)
    let backup = try DeviceBackupArchive.decode(bytes).verifiedBackup()
    #expect(!backup.aids.isEmpty)
    for aid in backup.aids {
        let fitting = try SavedFitting.decode(aid)
        let metadata = try SavedFitting.businessData(aid)
        #expect(!fitting.userPrograms.isEmpty)
        #expect(metadata.airConduction.points.count == 11)
        #expect(metadata.boneConduction.points.count == 11)
        for program in fitting.userPrograms {
            let gain = try #require(program.gain)
            #expect(gain.map.count == 4 && gain.map.allSatisfy { $0.count == 24 } && gain.mpo.count == 24)
        }
    }
    guard let output = ProcessInfo.processInfo.environment["AUDIFERN_PREVIEW_OUTPUT"] else { return }
    let folder = URL(fileURLWithPath: output, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let libraryFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: libraryFolder) }
    let library = DeviceBackupStore(folder: libraryFolder)
    try library.save(backup)
    let services = AudifernServices(demo: true)
    services.preferences.language = .english
    NSApplication.shared.setActivationPolicy(.prohibited)
    for scheme in [ColorScheme.light, .dark] {
        NSApplication.shared.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        let content = FittedConfigurationView(store: services.bluetooth, backups: library, showParameters: true)
            .environmentObject(services.preferences).environmentObject(services.navigation)
            .environment(\.colorScheme, scheme).preferredColorScheme(scheme)
            .frame(width: 1120, height: 1300).background(Brand.background).tint(Brand.accent)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 1120, height: 1300)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try PrivateDocuments.writeNew(png, to: folder.appendingPathComponent("private-fitting-\(scheme == .light ? "light" : "dark").png"))
        let metadata = try SavedFitting.businessData(#require(backup.aids.first))
        let metadataView = StoredFittingMetadataView(snapshot: metadata, backup: backup,
            audiograms: services.audiograms, showAudiogram: true)
            .environmentObject(services.preferences).environmentObject(services.navigation)
            .environment(\.colorScheme, scheme).preferredColorScheme(scheme)
            .frame(width: 760, height: 1170).padding(30).background(Brand.background).tint(Brand.accent)
        let metadataHosting = NSHostingView(rootView: metadataView)
        metadataHosting.frame = NSRect(x: 0, y: 0, width: 820, height: 1230)
        metadataHosting.layoutSubtreeIfNeeded()
        let metadataBitmap = try #require(metadataHosting.bitmapImageRepForCachingDisplay(in: metadataHosting.bounds))
        metadataHosting.cacheDisplay(in: metadataHosting.bounds, to: metadataBitmap)
        let metadataPNG = try #require(metadataBitmap.representation(using: .png, properties: [:]))
        try PrivateDocuments.writeNew(metadataPNG, to: folder.appendingPathComponent("private-metadata-\(scheme == .light ? "light" : "dark").png"))
    }
}
