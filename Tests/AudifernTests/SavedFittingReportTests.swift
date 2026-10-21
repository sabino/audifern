import AppKit
import CompanionCore
import Foundation
import PDFKit
import SwiftUI
import Testing
@testable import Audifern

private func syntheticSummaryBackup() throws -> DeviceBackup {
    let program = try ConsumerProgramSnapshot.Program(programID: 77, name: "PRIVATE_CUSTOM_NAME",
        category: 0, boostable: false, tinnitus: false)
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let consumer = try ConsumerProgramSnapshot(capturedAt: date, aids: [
        .init(side: .left, program: program), .init(side: .right, program: program)
    ])
    let payload = Data("PRIVATE_OPAQUE_PAYLOAD".utf8)
    let crc = OticonFittingRead.checksum(payload)
    let header = Data([0, 0, 4, 0, 0, UInt8(payload.count), UInt8(crc >> 8), UInt8(crc & 255)])
        + Data(repeating: 0, count: 8)
    let record = try DeviceBackup.Record(key: 1009,
        bytes: OticonFittingRead.validateRecord(header: header, payload: payload))
    return try DeviceBackup(capturedAt: date, consumerControls: consumer, aids: [
        .init(side: .left, identity: .init(peripheralID: UUID(), serialNumber: "PRIVATE_SERIAL_LEFT",
            model: "Synthetic model", firmware: "1.2.3", software: "4.5.6"), notes: ["PRIVATE_PATIENT_NOTE"]),
        .init(side: .right, identity: .init(peripheralID: UUID(), serialNumber: "PRIVATE_SERIAL_RIGHT",
            model: "Synthetic model", firmware: "1.2.4", software: "4.5.7"), records: [record])
    ], acquisitionStage: .partialRead)
}

private func compactReportText(_ value: String) -> String {
    value.components(separatedBy: .whitespacesAndNewlines).joined()
}

private func syntheticFourProgramSummary() throws -> SavedFittingReport {
    // Four invented user slots and a TV record. Exercise report pagination and
    // filtering without any copied clinical values or original model data.
    let directory = [(0, 0), (1, 0), (2, 0), (3, 0), (6, 19)]
    let firstProgram = 36 + directory.count * 9 + 7447
    var parameters = Data(repeating: 0, count: (firstProgram + 4 * 4405 + 20 + 7) / 8)
    parameters.replaceSubrange(0..<4, with: [255, 255, 255, 255])
    func put(_ value: Int, width: Int, at offset: Int) {
        for bit in 0..<width where value & (1 << bit) != 0 {
            parameters[(offset + bit) / 8] |= UInt8(1 << ((offset + bit) % 8))
        }
    }
    put(directory.count, width: 4, at: 32)
    for (index, entry) in directory.enumerated() {
        put(entry.0, width: 4, at: 36 + index * 9)
        put(entry.1, width: 5, at: 40 + index * 9)
    }
    var payload = Data(repeating: 0xA5, count: 16) + Data([6, 0, 0, 1, 1, 7, 4, 1])
    payload += Data([UInt8(parameters.count & 255), UInt8(parameters.count >> 8)]) + parameters + Data([0, 0])
    let crc = OticonFittingRead.checksum(payload)
    let header = Data([0, 0, 4, 0, UInt8(payload.count >> 8), UInt8(payload.count & 255), UInt8(crc >> 8), UInt8(crc & 255)])
        + Data(repeating: 0, count: 8)
    let record = try DeviceBackup.Record(key: 1009, bytes: OticonFittingRead.validateRecord(header: header, payload: payload))
    let consumer = try syntheticSummaryBackup().consumerControls
    let aids: [DeviceBackup.Aid] = [ConsumerProgramSnapshot.Side.left, .right].map { side in
        .init(side: side, identity: .init(peripheralID: UUID(), model: "Intent 3", hiidVersion: "4.5",
            releasePackageVersion: "5.0.29", runtimeMemoryMapVersion: "10.0.0"), records: [record])
    }
    return try SavedFittingReport(backup: DeviceBackup(capturedAt: consumer.capturedAt,
        consumerControls: consumer, aids: aids, acquisitionStage: .readCompleted))
}

@Test func summaryPresentationPreservesPartialAndUnsupportedDistinctionsInEachLanguage() throws {
    let report = try SavedFittingReport(backup: syntheticSummaryBackup())
    for language in [AppLanguage.english, .portugueseBrazil, .spanish] {
        let text = Localization(language: language)
        let presentation = SavedFittingReportPresentation(report: report, localization: text)
        #expect(presentation.pages.map(\.title) == [text.string("Left"), text.string("Right")])
        #expect(presentation.capture == text.string("Partial capture · post-read state not verified"))
        let leftValues = presentation.pages[0].sections.flatMap(\.rows).map(\.value)
        let rightValues = presentation.pages[1].sections.flatMap(\.rows).map(\.value)
        #expect(leftValues.contains(text.string("Fitting record not captured")))
        #expect(rightValues.contains(text.string("Fitting format not supported")))
        #expect(!rightValues.contains(text.string("Fitting record not captured")))
    }
}

/// Runs without a window, printer, save dialog, BluetoothStore or private file.
@MainActor @Test func summaryPDFContainsBothLocalizedEarsAndAllProjectedTextWithoutPrivatePayload() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let backup = try syntheticSummaryBackup(), report = try SavedFittingReport(backup: backup)
    let windowCount = NSApplication.shared.windows.count
    for language in [AppLanguage.english, .portugueseBrazil, .spanish] {
        let text = Localization(language: language)
        let presentation = SavedFittingReportPresentation(report: report, localization: text)
        let bytes = try SavedFittingReportExporter.pdfData(report: report, localization: text)
        #expect(bytes.starts(with: Data("%PDF-".utf8)))
        let document = try #require(PDFDocument(data: bytes))
        #expect(document.pageCount >= 2 && !document.isEncrypted)
        let extracted = try #require(document.string)
        let compact = compactReportText(extracted)
        var expected = [presentation.title, presentation.subtitle, presentation.date, presentation.capture, presentation.privacy]
        for page in presentation.pages {
            expected.append(page.title)
            for section in page.sections {
                expected.append(section.title)
                expected += section.rows.flatMap { [$0.title, $0.value] }
                if let note = section.note { expected.append(note) }
            }
        }
        for value in expected { #expect(compact.contains(compactReportText(value)), "PDF omitted projected text: \(value)") }
        for privateValue in ["PRIVATE_CUSTOM_NAME", "PRIVATE_SERIAL_LEFT", "PRIVATE_SERIAL_RIGHT",
                             "PRIVATE_OPAQUE_PAYLOAD", "PRIVATE_PATIENT_NOTE", backup.id.uuidString]
            + backup.aids.map({ $0.identity.peripheralID.uuidString }) {
            #expect(!extracted.localizedCaseInsensitiveContains(privateValue))
        }
        #expect(document.documentAttributes?[PDFDocumentAttribute.authorAttribute] == nil)
        for index in 0..<document.pageCount {
            let page = try #require(document.page(at: index))
            #expect(page.bounds(for: .mediaBox).size == CGSize(width: 595, height: 842))
        }
    }
    #expect(NSApplication.shared.windows.count == windowCount)
}

@MainActor @Test func summaryPDFPaginatesFourFittedUserSlotsWithoutEmbeddingAccessoryOrGainData() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let report = try syntheticFourProgramSummary()
    #expect(report.ears.allSatisfy { $0.fittingStatus == .decoded && $0.programs.count == 4 })
    for language in [AppLanguage.portugueseBrazil, .spanish] {
        let text = Localization(language: language)
        let presentation = SavedFittingReportPresentation(report: report, localization: text)
        let document = try #require(PDFDocument(data: SavedFittingReportExporter.pdfData(report: report, localization: text)))
        #expect(document.pageCount >= 4)
        let extracted = try #require(document.string), compact = compactReportText(extracted)
        for page in presentation.pages {
            #expect(extracted.contains(page.title))
            for section in page.sections {
                #expect(compact.contains(compactReportText(section.title)))
                for row in section.rows {
                    #expect(compact.contains(compactReportText(row.title)))
                    #expect(compact.contains(compactReportText(row.value)))
                }
                if let note = section.note { #expect(compact.contains(compactReportText(note))) }
            }
        }
        for slot in 1...4 { #expect(extracted.contains(text.string("P%d", arguments: [slot]))) }
        #expect(extracted.contains(text.string("Frequency lowering")))
        #expect(!extracted.contains(text.string("Television")))
        #expect(!extracted.contains(text.string("Gain row %d", arguments: [1])))
    }
}

@MainActor @Test func summaryPDFFileWrapperWritesOwnerOnlyAndReadsBackTheSameDocument() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let report = try syntheticFourProgramSummary()
    let bytes = try SavedFittingReportExporter.pdfData(report: report, localization: Localization(language: .english))
    let wrapper = SavedFittingPDFDocument(data: bytes).exportFileWrapper()
    #expect((wrapper.fileAttributes[FileAttributeKey.posixPermissions.rawValue] as? NSNumber)?.intValue == 0o600)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Audifern-summary-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("summary.pdf")
    try wrapper.write(to: file, options: .atomic, originalContentsURL: nil)
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    let readback = try Data(contentsOf: file)
    #expect(readback == bytes)
    #expect(try #require(PDFDocument(data: readback)).pageCount >= 4)
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["AUDIFERN_PREVIEW_OUTPUT"] != nil))
func renderSyntheticSummaryPreviewWithoutOpeningAWindow() throws {
    let output = try #require(ProcessInfo.processInfo.environment["AUDIFERN_PREVIEW_OUTPUT"])
    let folder = URL(fileURLWithPath: output, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let defaultsName = "Audifern-summary-preview-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let previousLanguage = Localization.shared.language
    let previousAppearance = NSApplication.shared.appearance
    defer { Localization.shared.language = previousLanguage; NSApplication.shared.appearance = previousAppearance }
    let preferences = AppPreferences(defaults: defaults)
    preferences.language = .english
    NSApplication.shared.setActivationPolicy(.prohibited)
    let report = try syntheticFourProgramSummary()
    for scheme in [ColorScheme.light, .dark] {
      for width in [820, 1120] {
        NSApplication.shared.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        let view = SavedFittingReportView(report: report, close: {})
            .environmentObject(preferences).environment(\.colorScheme, scheme).preferredColorScheme(scheme)
            .padding(24).frame(width: CGFloat(width), height: 2400, alignment: .top).background(Brand.background)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 2400)
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.window == nil)
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try PrivateDocuments.writeNew(png, to: folder.appendingPathComponent("saved-fitting-summary-\(scheme == .light ? "light" : "dark")-\(width).png"))
      }
    }
}
