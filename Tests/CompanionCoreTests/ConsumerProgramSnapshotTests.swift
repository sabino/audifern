import Foundation
import XCTest
@testable import CompanionCore

/// Synthetic protocol and export fixtures; no user identifiers or fitting data.
final class ConsumerProgramSnapshotTests: XCTestCase {
    private func service(major: UInt8 = 2, minor: UInt8 = 0, status: UInt8 = 255) -> UTLProtocol.Service {
        .init(id: OticonConsumerPrograms.serviceID, handle: 12, major: major, minor: minor, status: status)
    }
    private func uint(_ value: UInt32) -> Data {
        if value < 24 { return Data([UInt8(value)]) }
        if value <= 255 { return Data([0x18, UInt8(value)]) }
        return Data([0x1A, UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
                     UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
    }
    private func text(_ value: String) -> Data {
        let bytes = Data(value.utf8)
        return Data(bytes.count < 24 ? [0x60 | UInt8(bytes.count)] : [0x78, UInt8(bytes.count)]) + bytes
    }
    private func map(_ fields: [(String, Data)]) -> Data {
        fields.reduce(into: Data([0xA0 | UInt8(fields.count)])) { $0 += text($1.0) + $1.1 }
    }
    private func entry(id: UInt32 = 7, name: String = "Geral", mic: Bool? = true) -> Data {
        var fields: [(String, Data)] = [("program_id", uint(id)), ("name", text(name)), ("category", uint(0)),
                                       ("boostable", Data([0xF5])), ("tinnitus", Data([0xF4]))]
        if let mic { fields.append(("mic", Data([mic ? 0xF5 : 0xF4]))) }
        return map(fields)
    }
    private func info(_ records: [Data]) -> Data {
        map([("programs", records.reduce(into: Data([0x80 | UInt8(records.count)])) { $0 += $1 })])
    }

    func testVersionedProgramMetadataAndFixedWidthActiveID() throws {
        for minor in UInt8(0)...1 {
            let result = try OticonConsumerPrograms.programInformation(info([entry(), entry(id: 255, name: "Music", mic: nil)]), service: service(minor: minor))
            XCTAssertEqual(result.map(\.programID), [7, 255])
            XCTAssertEqual(result[0].name, "Geral")
            XCTAssertEqual(result[0].category, 0)
            XCTAssertTrue(result[0].boostable)
            XCTAssertFalse(result[0].tinnitus)
            XCTAssertEqual(result[0].mic, true)
            XCTAssertNil(result[1].mic)
            XCTAssertEqual(try OticonConsumerPrograms.activeProgram(Data([255]), service: service(minor: minor)), 255)
        }
        XCTAssertThrowsError(try OticonConsumerPrograms.activeProgram(Data([0x18, 7]), service: service()))
        XCTAssertThrowsError(try OticonConsumerPrograms.activeProgram(Data(), service: service()))
        for unsupported in [service(major: 1), service(minor: 2), service(status: 0)] {
            XCTAssertFalse(OticonConsumerPrograms.supports(unsupported))
            XCTAssertThrowsError(try OticonConsumerPrograms.programInformation(info([entry()]), service: unsupported))
        }
    }

    func testRootMapUsesWireOrderAndDoesNotRetainUnknownValues() throws {
        let record = map([("program_id", uint(1)), ("name", text("Geral")), ("category", uint(UInt32.max)),
                          ("boostable", Data([0xF4])), ("tinnitus", Data([0xF5])),
                          ("private_blob", Data([0x44, 1, 2, 3, 4]))])
        let wire = map([("zzz", Data([0x81]) + record), ("aaa", text("not a program array"))])
        let programs = try OticonConsumerPrograms.programInformation(wire, service: service())
        XCTAssertEqual(programs.count, 1)
        XCTAssertEqual(programs[0].category, UInt32.max)
        let encoded = try JSONEncoder().encode(programs)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("private_blob"))
    }

    func testRejectsDuplicateIDsKeysWrongTypesAndMalformedText() throws {
        let fields: [(String, Data)] = [("program_id", uint(1)), ("name", text("Geral")), ("category", uint(0)),
                                       ("boostable", Data([0xF4])), ("tinnitus", Data([0xF5]))]
        let invalidRecords = [entry(id: 256), entry(name: ""), entry(name: "Line\nBreak"),
            map(fields + [("program_id", uint(2))]), map(fields + [("mic", Data([0xF6]))]),
            map(Array(fields.dropLast()) + [("tinnitus", uint(1))])]
        for record in invalidRecords {
            XCTAssertThrowsError(try OticonConsumerPrograms.programInformation(info([record]), service: service()))
        }
        XCTAssertThrowsError(try OticonConsumerPrograms.programInformation(info([entry(), entry()]), service: service()))
        let duplicateRoot = map([("programs", Data([0x80])), ("programs", Data([0x80]))])
        XCTAssertThrowsError(try OticonConsumerPrograms.programInformation(duplicateRoot, service: service()))
    }

    func testRejectsEveryTruncationTrailingDataAndUnboundedContainers() throws {
        let valid = info([entry()])
        for length in 0..<valid.count {
            XCTAssertThrowsError(try OticonConsumerPrograms.programInformation(Data(valid.prefix(length)), service: service()), "prefix \(length)")
        }
        for malformed in [valid + Data([0]), Data([0xBF, 0xFF]), map([("p", Data([0x98, 0xFF]))]),
                          Data(repeating: 0, count: 65_536), map([("p", Data([0x80])), ("extra", Data(repeating: 0x81, count: 14) + Data([0]))])] {
            XCTAssertThrowsError(try OticonConsumerPrograms.programInformation(malformed, service: service()))
        }
    }

    func testConsumerJSONHasExplicitScopeAndNoPrivateIdentifiers() throws {
        let program = try ConsumerProgramSnapshot.Program(programID: 7, name: "Geral", category: 0, boostable: true, tinnitus: false)
        let volume = try ConsumerProgramSnapshot.Volume(level: -1, muted: false, range: -8...4)
        let eq = try OticonEqualizer.State(rawSteps: [1, 0, 0, 0, 0, 0, 0, -1],
            minimumSteps: .init(repeating: -4, count: 8), maximumSteps: .init(repeating: 4, count: 8), stepDB: 0.2)
        let aid = try ConsumerProgramSnapshot.Aid(side: .left, model: "Intent 3", program: program,
            volume: volume, streamingEqualizer: .init(state: eq), speechBoosterEnabled: true)
        let snapshot = try ConsumerProgramSnapshot(capturedAt: Date(timeIntervalSince1970: 1_800_000_000), aids: [aid])
        let data = try snapshot.encoded()
        XCTAssertEqual(try ConsumerProgramSnapshot.decode(data), snapshot)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["schemaVersion", "scope", "clinicalFittingIncluded", "capturedAt", "aids"])
        XCTAssertEqual(json["scope"] as? String, "consumer-controls")
        XCTAssertEqual(json["clinicalFittingIncluded"] as? Bool, false)
        for forbidden in ["serialNumber", "uuid", "HIID", "authentication", "audiogram"] {
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(forbidden))
        }
        XCTAssertNil(aid.tinnitusVolume)
        XCTAssertEqual(aid.speechBoosterEnabled, true)
    }

    func testSnapshotRejectsFalseClinicalClaimsDuplicateSidesAndBadRanges() throws {
        let program = try ConsumerProgramSnapshot.Program(programID: 0, name: "Geral", category: 0, boostable: false, tinnitus: false)
        let aid = try ConsumerProgramSnapshot.Aid(side: .right, program: program)
        XCTAssertThrowsError(try ConsumerProgramSnapshot(aids: [aid, aid]))
        XCTAssertThrowsError(try ConsumerProgramSnapshot(aids: []))
        XCTAssertThrowsError(try ConsumerProgramSnapshot.Volume(level: 5, muted: false, range: -8...4))
        let data = try ConsumerProgramSnapshot(aids: [aid]).encoded()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, value) in [("scope", "clinical-fitting" as Any), ("clinicalFittingIncluded", true as Any), ("schemaVersion", 2 as Any)] {
            var changed = original; changed[key] = value
            XCTAssertThrowsError(try ConsumerProgramSnapshot.decode(JSONSerialization.data(withJSONObject: changed)))
        }
    }
}
