import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import XCTest
@testable import CompanionCore

final class AudiogramTests: XCTestCase {
    private let rightAir = AudiogramThresholdKey(ear: .right, conduction: .air, frequencyHz: 1000)

    func testMissingValuesStayUnknownAndAreNeverZeroFilled() throws {
        let draft = AudiogramDraft()
        let exam = try draft.validated()
        XCTAssertTrue(exam.thresholds.isEmpty)
        XCTAssertNil(exam.examDate)
        XCTAssertNil(try Audiogram.parseLevel(" \n", for: rightAir))
        var partial = draft
        partial.cells[rightAir] = .init(text: "0")
        let validated = try partial.validated()
        XCTAssertEqual(validated.thresholds.count, 1)
        XCTAssertEqual(validated.thresholds.first?.levelDBHL, 0)
    }

    func testNumericEntryAcceptsNegativeAndDecimalCommaButRejectsMalformedInput() throws {
        XCTAssertEqual(try Audiogram.parseLevel(" −5", for: rightAir), -5)
        XCTAssertEqual(try Audiogram.parseLevel("-5", for: rightAir), -5)
        XCTAssertEqual(try Audiogram.parseLevel(" 12,5 ", for: rightAir), 12.5)
        XCTAssertEqual(try Audiogram.parseLevel("+20.5", for: rightAir), 20.5)
        for invalid in ["-", "+", ".", "20.", "NaN", "Infinity", "1e2", "10dB", "1,2,3", "0x10", "-20.1", "130.1"] {
            XCTAssertThrowsError(try Audiogram.parseLevel(invalid, for: rightAir), invalid)
        }
    }

    func testDateValidationPreservesUnknownAndRejectsNormalizedInvalidDates() throws {
        XCTAssertTrue(Audiogram.isValidExamDate("2024-02-29"))
        XCTAssertTrue(Audiogram.isValidExamDate("2026-10-20"))
        for invalid in ["2025-02-29", "2026-04-31", "2026-13-01", "2026-01-00", "26-01-01", "2026-1-1", "0000-01-01"] {
            XCTAssertFalse(Audiogram.isValidExamDate(invalid), invalid)
        }
        XCTAssertThrowsError(try Audiogram(examDate: "2025-02-29").validated())
    }

    func testAirBoneMaskedAndNoResponseAreDistinctAndRoundTripWithoutFittingData() throws {
        var draft = AudiogramDraft(Audiogram(name: "Synthetic fixture", examDate: "2024-02-29", notes: "Entered from an exam"))
        draft.cells[rightAir] = .init(text: "35")
        var masked = rightAir; masked.masked = true
        draft.cells[masked] = .init(text: "45", noResponse: true)
        let leftBone = AudiogramThresholdKey(ear: .left, conduction: .bone, frequencyHz: 4000)
        draft.cells[leftBone] = .init(text: "20,5")
        let exam = try draft.validated()
        let data = try AudiogramLibrary(exams: [exam]).encoded()
        XCTAssertEqual(try AudiogramLibrary.decode(data).exams, [exam])
        XCTAssertEqual(exam.thresholds.first { $0.key == masked }?.noResponse, true)
        XCTAssertEqual(exam.thresholds.first { $0.key == masked }?.levelDBHL, 45)
        XCTAssertEqual(AudiogramDraft(exam), AudiogramDraft(try AudiogramLibrary.decode(data).exams[0]))
        let json = String(decoding: data, as: UTF8.self)
        for absent in ["gain", "prescription", "device", "patientName", "token"] { XCTAssertFalse(json.contains(absent)) }
    }

    func testNoResponseRequiresEnteredPresentationLevel() {
        var draft = AudiogramDraft()
        draft.cells[rightAir] = .init(noResponse: true)
        XCTAssertThrowsError(try draft.validated()) { XCTAssertEqual($0 as? AudiogramError, .missingNoResponseLevel(self.rightAir)) }
    }

    func testDuplicateInvalidAndNonFiniteMeasurementsAreRejected() throws {
        let valid = AudiogramThreshold(key: rightAir, levelDBHL: 20)
        XCTAssertThrowsError(try Audiogram(thresholds: [valid, valid]).validated())
        for level in [Double.nan, Double.infinity, -Double.infinity, -21, 131] {
            XCTAssertThrowsError(try Audiogram(thresholds: [.init(key: rightAir, levelDBHL: level)]).validated())
        }
        let unsupported = AudiogramThresholdKey(ear: .left, conduction: .air, frequencyHz: 9000)
        XCTAssertThrowsError(try Audiogram(thresholds: [.init(key: unsupported, levelDBHL: 20)]).validated())
    }

    func testChartUsesRealLogFrequencyAndIncreasingHearingLevelDownward() throws {
        let low = try XCTUnwrap(Audiogram.chartPosition(frequencyHz: 125, levelDBHL: -20))
        let high = try XCTUnwrap(Audiogram.chartPosition(frequencyHz: 8000, levelDBHL: 130))
        XCTAssertEqual(low.x, 0); XCTAssertEqual(low.y, 0)
        XCTAssertEqual(high.x, 1); XCTAssertEqual(high.y, 1)
        let first = try XCTUnwrap(Audiogram.chartPosition(frequencyHz: 500, levelDBHL: 0))
        let second = try XCTUnwrap(Audiogram.chartPosition(frequencyHz: 1000, levelDBHL: 20))
        XCTAssertEqual(second.x - first.x, 1 / 6.0, accuracy: 0.000001)
        XCTAssertGreaterThan(second.y, first.y)
        let interoctave = try XCTUnwrap(Audiogram.chartPosition(frequencyHz: 3000, levelDBHL: 20))
        XCTAssertEqual(interoctave.x, log2(24.0) / 6, accuracy: 0.000001)
        XCTAssertNotEqual(interoctave.x, 4.5 / 6)
        XCTAssertNil(Audiogram.chartPosition(frequencyHz: 0, levelDBHL: 0))
    }

    func testIntermediateFrequenciesPreserveStoredExamValuesAndTheirLogPosition() throws {
        let exam = Audiogram(name: "Synthetic fitting record", thresholds: [750, 1500].map {
            AudiogramThreshold(key: .init(ear: .left, conduction: .air, frequencyHz: $0), levelDBHL: 25)
        })
        XCTAssertEqual(try AudiogramLibrary.decode(AudiogramLibrary(exams: [exam]).encoded()).exams, [exam])
        let low = try XCTUnwrap(Audiogram.chartPosition(frequencyHz: 750, levelDBHL: 25))
        let high = try XCTUnwrap(Audiogram.chartPosition(frequencyHz: 1500, levelDBHL: 25))
        XCTAssertEqual(high.x - low.x, 1.0 / 6, accuracy: 0.00001)
        XCTAssertEqual(high.y, low.y)
    }

    func testImportRejectsUnknownSchemaDuplicateRecordsAndOversizedFiles() throws {
        let exam = Audiogram()
        XCTAssertThrowsError(try AudiogramLibrary(exams: [exam, exam]).encoded())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: AudiogramLibrary(exams: [exam]).encoded()) as? [String: Any])
        json["schemaVersion"] = 2
        XCTAssertThrowsError(try AudiogramLibrary.decode(JSONSerialization.data(withJSONObject: json))) {
            XCTAssertEqual($0 as? AudiogramError, .unsupportedSchema)
        }
        XCTAssertThrowsError(try AudiogramLibrary.decode(Data("{broken".utf8)))
        XCTAssertThrowsError(try AudiogramLibrary.decode(Data(repeating: 32, count: AudiogramRepository.maximumFileBytes + 1))) {
            XCTAssertEqual($0 as? AudiogramError, .fileTooLarge)
        }
    }

    func testPrivateAtomicPersistencePreservesPreviousFileOnInvalidSave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("audiogram-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AudiogramRepository(fileURL: directory.appendingPathComponent("exams.json"))
        XCTAssertEqual(try repository.load(), AudiogramLibrary())
        let first = AudiogramLibrary(exams: [Audiogram(name: "Synthetic fixture", thresholds: [.init(key: rightAir, levelDBHL: 30)])])
        try repository.save(first)
        XCTAssertEqual(try repository.load(), first)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: repository.fileURL.path)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let previous = try Data(contentsOf: repository.fileURL)
        XCTAssertThrowsError(try repository.save(AudiogramLibrary(exams: [Audiogram(name: "")])))
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), previous)
        var replacement = first; replacement.exams[0].notes = "Updated record"
        try repository.save(replacement)
        XCTAssertEqual(try repository.load(), replacement)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["exams.json"])
    }

    func testCorruptSavedFileAndSymlinkAreNeverSilentlyLoadedOrOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("audiogram-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("original.json")
        let corrupt = Data("malformed saved data".utf8)
        try corrupt.write(to: target)
        XCTAssertThrowsError(try AudiogramRepository(fileURL: target).load())
        XCTAssertEqual(try Data(contentsOf: target), corrupt)
        let link = directory.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let repository = AudiogramRepository(fileURL: link)
        XCTAssertThrowsError(try repository.load())
        XCTAssertThrowsError(try repository.save(AudiogramLibrary()))
        XCTAssertEqual(try Data(contentsOf: target), corrupt)
    }

    func testHIMSAExportCarriesMeasuredValuesAndNoResponseWithoutInventedMetadata() throws {
        let exam = Audiogram(name: "Excluded from XML", examDate: "2026-10-20", notes: "Excluded notes", thresholds: [
            .init(key: rightAir, levelDBHL: 35),
            .init(key: .init(ear: .left, conduction: .air, frequencyHz: 8000), levelDBHL: 95, noResponse: true),
            .init(key: .init(ear: .right, conduction: .bone, frequencyHz: 500), levelDBHL: -5),
            .init(key: .init(ear: .left, conduction: .bone, frequencyHz: 2000), levelDBHL: 12.5)
        ])
        let data = try HIMSAAudiogramExport.xml(for: exam, airTransducer: .insertPhones)
        let document = try XMLDocument(data: data)
        XCTAssertEqual(document.rootElement()?.name, "HIMSAAudiometricStandard")
        XCTAssertEqual(document.rootElement()?.attribute(forName: "Version")?.stringValue, "502")
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='ToneThresholdAudiogram']").count, 4)
        let xml = String(decoding: data, as: UTF8.self)
        for expected in ["InsertPhoneRight", "InsertPhoneLeft", "BoneConductorRight", "BoneConductorLeft", "<TonePointStatus>NoResponse</TonePointStatus>", "<StimulusLevel>95.0</StimulusLevel>", "<StimulusLevel>12.5</StimulusLevel>", "<StimulusSignalType>Unknown</StimulusSignalType>"] {
            XCTAssertTrue(xml.contains(expected), expected)
        }
        for absent in ["ValidatedByNOAH", "2026-10-20", "Excluded", "MaskingLevel", "Instrument", "Calibration"] { XCTAssertFalse(xml.contains(absent)) }
    }

    func testHIMSAExportDoesNotFabricateMaskingTransducerOrRoundedThresholds() {
        XCTAssertThrowsError(try HIMSAAudiogramExport.xml(for: Audiogram()))
        let air = Audiogram(thresholds: [.init(key: rightAir, levelDBHL: 20)])
        XCTAssertThrowsError(try HIMSAAudiogramExport.xml(for: air)) {
            XCTAssertEqual($0 as? HIMSAAudiogramExport.ExportError, .missingAirTransducer)
        }
        var masked = rightAir; masked.masked = true
        let maskedExam = Audiogram(thresholds: [.init(key: masked, levelDBHL: 20)])
        XCTAssertThrowsError(try HIMSAAudiogramExport.xml(for: maskedExam, airTransducer: .headphones)) {
            XCTAssertEqual($0 as? HIMSAAudiogramExport.ExportError, .missingMaskingLevels)
        }
        let precise = Audiogram(thresholds: [.init(key: rightAir, levelDBHL: 20.05)])
        XCTAssertThrowsError(try HIMSAAudiogramExport.xml(for: precise, airTransducer: .headphones)) {
            XCTAssertEqual($0 as? HIMSAAudiogramExport.ExportError, .precisionNotSupported)
        }
    }

    func testHIMSAExportValidatesAgainstOfficialSchemaWhenProvided() throws {
        guard let schema = ProcessInfo.processInfo.environment["HIMSA_AUDIOGRAM_SCHEMA"], FileManager.default.fileExists(atPath: schema) else {
            throw XCTSkip("Set HIMSA_AUDIOGRAM_SCHEMA to the locally acquired official Audiogram502 XSD to run schema validation.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("himsa-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("synthetic-exam.xml")
        var points: [AudiogramThreshold] = []
        for ear in AudiogramEar.allCases {
            for conduction in AudiogramConduction.allCases {
                for frequency in Audiogram.frequenciesHz {
                    points.append(.init(key: .init(ear: ear, conduction: conduction, frequencyHz: frequency),
                                        levelDBHL: frequency == 8000 ? 95 : 12.5, noResponse: frequency == 8000))
                }
            }
        }
        try HIMSAAudiogramExport.xml(for: Audiogram(thresholds: points), signal: .pureTone, airTransducer: .headphones).write(to: output)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xmllint")
        process.arguments = ["--nonet", "--noout", "--schema", schema, output.path]
        let errors = Pipe(); process.standardError = errors
        try process.run(); process.waitUntilExit()
        let diagnostics = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, diagnostics)
    }
}
