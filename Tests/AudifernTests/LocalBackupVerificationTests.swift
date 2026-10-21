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
        let controls = try OticonSavedControls.decode(fitting)
        let acoustics = try OticonSavedAcoustics.decode(fitting)
        let settings = try #require(aid.endUserSettings)
        let preferences = try OticonSavedPreferences.decode(settings,
            identity: fitting.identity, services: aid.services)
        #expect(preferences.taps.count == 12)
        #expect(preferences.audibleIndicators.count == 23)
        #expect(preferences.indicatorSettings.count == 3)
        #expect(preferences.taps.allSatisfy { $0.action.isRecognized })
        if let identification = aid.identification {
            let hardware = try OticonHardwareProfile.decodeHiid(identification)
            #expect(hardware.hiidMajor == 4 && hardware.hiidMinor == 5)
            #expect(hardware.hardware.removableSpeaker.isRecognized)
            #expect(hardware.hardware.audiologicalStyle.isRecognized)
            #expect(hardware.hardware.hearingInstrumentInterface.isRecognized)
            #expect(hardware.acoustics.earPieceCode == acoustics.earpiece.rawCode)
            #expect(hardware.acoustics.ventCode == acoustics.vent.rawCode)
            #expect(hardware.acoustics.hookCode == acoustics.hook.rawCode)
            #expect(hardware.acoustics.tubingCode == acoustics.tubing.rawCode)
            #expect(hardware.acoustics.fittingLevelCode == acoustics.fittingLevel.rawCode)
        }
        #expect(controls.programs.map(\.slot) == fitting.programs.map(\.slot))
        #expect([acoustics.earpiece, acoustics.hook, acoustics.vent, acoustics.tubing,
                 acoustics.fittingLevel, acoustics.fittedSide].allSatisfy { $0.isRecognized })
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
    if let comparisonPath = ProcessInfo.processInfo.environment["AUDIFERN_COMPARE_BACKUP"] {
        let comparisonBytes = try PrivateDocuments.read(URL(fileURLWithPath: comparisonPath),
                                                        maximumBytes: DeviceBackupArchive.maximumBytes)
        let other = try DeviceBackupArchive.decode(comparisonBytes).verifiedBackup()
        try library.save(other)
        let comparison = try DeviceBackupComparison(first: other, second: backup)
        #expect(!comparison.aids.isEmpty)
    }
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

        let aid = try #require(backup.aids.first)
        let fitting = try SavedFitting.decode(aid)
        let controls = try OticonSavedControls.decode(fitting)
        let preferences = try OticonSavedPreferences.decode(#require(aid.endUserSettings),
            identity: fitting.identity, services: aid.services)
        let acoustics = try OticonSavedAcoustics.decode(fitting)
        let slot = try #require(fitting.userPrograms.first).slot
        let savedControls = VStack(spacing: 20) {
            SavedAcousticsView(labels: acoustics)
            SavedSoundControlsView(controls: controls, slot: slot)
        }
        try renderPrivate(savedControls, name: "saved-controls", width: 820, height: 1250,
                          scheme: scheme, services: services, folder: folder)
        try renderPrivate(SavedPreferencesView(preferences: preferences, showDetails: true),
                          name: "saved-preferences", width: 820, height: 1700,
                          scheme: scheme, services: services, folder: folder)
        if library.entries.count > 1 {
            try renderPrivate(BackupComparisonView(backups: library),
                              name: "backup-comparison", width: 820, height: 1000,
                              scheme: scheme, services: services, folder: folder)
        }
    }
}

@MainActor private func renderPrivate<Content: View>(_ content: Content, name: String,
    width: Int, height: Int, scheme: ColorScheme, services: AudifernServices, folder: URL) throws {
    let hosting = NSHostingView(rootView: content
        .environmentObject(services.preferences).environmentObject(services.navigation)
        .environment(\.colorScheme, scheme).preferredColorScheme(scheme)
        .frame(width: CGFloat(width - 60)).padding(30)
        .frame(width: CGFloat(width), height: CGFloat(height), alignment: .topLeading)
        .background(Brand.background).tint(Brand.accent))
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
    hosting.layoutSubtreeIfNeeded()
    let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try PrivateDocuments.writeNew(png, to: folder.appendingPathComponent(
        "private-\(name)-\(scheme == .light ? "light" : "dark").png"))
}
