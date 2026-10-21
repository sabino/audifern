import Foundation
import Testing
@testable import CompanionCore

private func reportRecord(slots: [Int] = [0, 1], earpiece: UInt8 = 1,
                          feedback: Bool = true, truncated: Bool = false) throws -> Data {
    // Invented data at already researched wire positions. No real backup,
    // manufacturer resource, clinical calculation or factory preset is used.
    let general = 36 + slots.count * 9
    let first = general + 7447
    var parameters = Data(repeating: 0, count: (first + slots.count * 4405 + 7) / 8)
    func put(_ value: Int, width: Int, at offset: Int) {
        for bit in 0..<width {
            let index = (offset + bit) / 8, mask = UInt8(1 << ((offset + bit) % 8))
            parameters[index] &= ~mask
            if value & (1 << bit) != 0 { parameters[index] |= mask }
        }
    }
    parameters.replaceSubrange(0..<4, with: [255, 255, 255, 255])
    put(slots.count, width: 4, at: 32)
    for (index, slot) in slots.enumerated() { put(slot, width: 4, at: 36 + index * 9) }
    put(1, width: 2, at: general) // Automatic adaptation.
    put(75, width: 8, at: general + 4)
    put(2, width: 2, at: general + 12) // Final step3.
    let customName = Array("PRIVATE_PROGRAM_NAME".utf8)
    put(customName.count, width: 5, at: general + 3002)
    for (index, byte) in customName.enumerated() { put(Int(byte), width: 8, at: general + 3007 + index * 8) }
    if feedback { put(1, width: 1, at: first + 1536) }
    if truncated { parameters = Data(parameters.prefix(5)) }

    var business = Data([0x42, 0x4C, 0, 1, 2, 3, 4, 27, 0, 4, 0, 2, 0, 0])
    business += Data(repeating: 0x80, count: 66) // Three absent clinical curves.
    business += Data([1, 1, 0, 0]) + Data(repeating: 0, count: 16)
    business += Data(repeating: 0x80, count: 22)
    business += Data("PRIVATE_OPAQUE_PATIENT_DATA".utf8)
    business += Data(repeating: 0, count: 500 - business.count)
    var payload = Data("PRIVATE_GUID_123".utf8)
    func appendSection(_ data: Data) {
        payload += Data([UInt8(data.count & 255), UInt8(data.count >> 8)]) + data
    }
    appendSection(Data([earpiece, 1, 1, 7, 4, 1]))
    appendSection(parameters); appendSection(business)
    let crc = OticonFittingRead.checksum(payload)
    let header = Data([0, 0, 4, 0, UInt8(payload.count >> 8), UInt8(payload.count & 255),
        UInt8(crc >> 8), UInt8(crc & 255)]) + Data(repeating: 0, count: 8)
    return try OticonFittingRead.validateRecord(header: header, payload: payload)
}

private func reportSettings(complete: Bool) throws -> DeviceBackup.EndUserSettings {
    func text(_ value: String) -> Data { Data([0x60 | UInt8(value.utf8.count)]) + Data(value.utf8) }
    let scope = Data([0xA3]) + text("name") + text("global") + text("count") + Data([2]) + text("access") + text("NVRAM")
    let inventory = Data([0xA1]) + text("scopes") + Data([0x81, 0x81]) + scope
    var records = [try DeviceBackup.EndUserSettings.ScopeRecord(scope: 0, id: 0, bytes: Data([0xA0]))]
    if complete { records.append(try .init(scope: 0, id: 1, bytes: Data([0xA0]))) }
    return try .init(inventory: inventory, records: records)
}

private func reportBackup(sides: [ConsumerProgramSnapshot.Side] = [.left, .right],
                          records: [Data?], release: String = "5.0.29",
                          stage: DeviceBackup.AcquisitionStage? = .readCompleted,
                          settings: DeviceBackup.EndUserSettings? = nil) throws -> DeviceBackup {
    let consumerProgram = try ConsumerProgramSnapshot.Program(programID: 91, name: "PRIVATE_CONSUMER_NAME",
        category: 0, boostable: false, tinnitus: false)
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let consumer = try ConsumerProgramSnapshot(capturedAt: date, aids: sides.map { try .init(side: $0, program: consumerProgram) })
    let aids = try sides.enumerated().map { index, side in
        DeviceBackup.Aid(side: side, identity: .init(peripheralID: UUID(), serialNumber: "PRIVATE_SERIAL",
            model: "Intent 3", firmware: "rel_7.4_27.0", software: "1.2.3", hiidVersion: "4.5",
            releasePackageVersion: release, runtimeMemoryMapVersion: "10.0.0"), programs: [consumerProgram],
            records: try records[index].map { [try DeviceBackup.Record(key: 1009, bytes: $0)] } ?? [],
            endUserSettings: settings, notes: ["PRIVATE_ACQUISITION_NOTE", "AA:BB:CC:DD:EE:FF"])
    }
    return try DeviceBackup(capturedAt: date, consumerControls: consumer, aids: aids, acquisitionStage: stage)
}

@Test func savedFittingReportUsesEachArchivedEarAndFittedSlotsWithoutConsumerFallback() throws {
    let backup = try reportBackup(sides: [.right, .left],
        records: [reportRecord(slots: [2], feedback: false), reportRecord(slots: [0, 1])])
    let report = try SavedFittingReport(backup: backup)
    #expect(report.capturedAt == backup.capturedAt && report.capture == .completed)
    #expect(report.capturedEarCount == 2 && report.ears.map(\.side) == [.left, .right])
    #expect(report.ears.allSatisfy { $0.fittingStatus == .decoded })
    #expect(report.ears[0].programs.map(\.slot) == [0, 1])
    #expect(report.ears[1].programs.map(\.slot) == [2])
    #expect(report.ears[0].programs[0].feedbackManagementEnabled == true)
    #expect(report.ears[1].programs[0].feedbackManagementEnabled == false)
    #expect(report.ears[0].adaptation?.currentStep == 1.75)
    #expect(report.ears[0].adaptation?.endStep == 3)
    #expect(report.ears[0].adaptation?.mode == .automatic)
    #expect(report.ears[0].acoustics?.earpiece == "Bass dome, double vent")
    #expect(report.ears[0].metadata?.rationales == ["NAL-NL2", "VAC+"])
    #expect(report.ears[0].metadata?.fittingSoftwareVersion == "27.4.2")
    #expect(try report == JSONDecoder().decode(SavedFittingReport.self, from: JSONEncoder().encode(report)))
}

@Test func savedFittingReportDistinguishesMissingEarMissingRecordAndUnsupportedProfile() throws {
    let missing = try SavedFittingReport(backup: reportBackup(sides: [.left], records: [nil]))
    #expect(missing.ears[0].isCaptured && missing.ears[0].fittingStatus == .notCaptured)
    #expect(!missing.ears[1].isCaptured && missing.ears[1].model == nil)
    #expect(missing.ears.allSatisfy { $0.programs.isEmpty && $0.adaptation == nil })
    let future = try SavedFittingReport(backup: reportBackup(sides: [.right], records: [reportRecord()], release: "5.0.30"))
    #expect(future.ears[1].fittingStatus == .unsupported)
    #expect(future.ears[1].programs.isEmpty && future.ears[1].acoustics == nil)
    #expect(future.ears[1].firmwareVersion == "rel_7.4_27.0")
}

@Test func savedFittingReportSeparatesUndecodableDetailsFromAbsentData() throws {
    let report = try SavedFittingReport(backup: reportBackup(sides: [.left], records: [reportRecord(truncated: true)]))
    #expect(report.ears[0].fittingStatus == .unreadable)
    #expect(report.ears[0].programs.isEmpty && report.ears[0].metadata == nil)
    let unknown = try SavedFittingReport(backup: reportBackup(sides: [.left], records: [reportRecord(earpiece: 255)]))
    #expect(unknown.ears[0].fittingStatus == .decoded)
    #expect(unknown.ears[0].acoustics != nil && unknown.ears[0].acoustics?.earpiece == nil)
}

@Test func savedFittingReportKeepsPartialAcquisitionAndAdvertisedScopeCoverageDistinct() throws {
    let partial = try SavedFittingReport(backup: reportBackup(sides: [.left], records: [reportRecord()],
        stage: .partialRead, settings: reportSettings(complete: false)))
    #expect(partial.capture == .partial && partial.ears[0].fittingStatus == .decoded)
    #expect(partial.ears[0].endUserCoverage?.capturedCount == 1)
    #expect(partial.ears[0].endUserCoverage?.advertisedCount == 2)
    #expect(partial.ears[0].endUserCoverage?.advertisedInventoryComplete == false)
    let complete = try SavedFittingReport(backup: reportBackup(sides: [.left], records: [nil],
        settings: reportSettings(complete: true)))
    #expect(complete.ears[0].endUserCoverage?.advertisedInventoryComplete == true)
    #expect(complete.ears[0].fittingStatus == .notCaptured)
    #expect(try SavedFittingReport(backup: reportBackup(sides: [.left], records: [nil], stage: nil)).capture == .unspecified)
    #expect(try SavedFittingReport(backup: reportBackup(sides: [.left], records: [nil], stage: .consumerCheckpoint)).capture == .consumerCheckpoint)
}

@Test func savedFittingReportProjectionContainsNoArchiveIdentifiersClinicalPayloadOrCustomNames() throws {
    let backup = try reportBackup(records: [reportRecord(), reportRecord()])
    let original = try backup.encoded()
    let report = try SavedFittingReport(backup: backup)
    let encoded = try JSONEncoder().encode(report)
    let text = try #require(String(data: encoded, encoding: .utf8))
    for privateValue in ["PRIVATE_SERIAL", "PRIVATE_PROGRAM_NAME", "PRIVATE_CONSUMER_NAME", "PRIVATE_GUID_123",
                         "PRIVATE_OPAQUE_PATIENT_DATA", "PRIVATE_ACQUISITION_NOTE", "AA:BB:CC:DD:EE:FF", backup.id.uuidString] + backup.aids.map({ $0.identity.peripheralID.uuidString }) {
        #expect(!text.localizedCaseInsensitiveContains(privateValue))
    }
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    func keys(_ value: Any) -> Set<String> {
        if let dictionary = value as? [String: Any] {
            return Set(dictionary.keys).union(dictionary.values.reduce(into: Set<String>()) { $0.formUnion(keys($1)) })
        }
        if let array = value as? [Any] { return array.reduce(into: Set<String>()) { $0.formUnion(keys($1)) } }
        return []
    }
    #expect(keys(object).isDisjoint(with: ["serialNumber", "peripheralID", "fittingIDBytes", "identification", "notes",
        "records", "bytes", "businessData", "prodRegs", "airConduction", "boneConduction", "realEar", "gain", "mpo", "label", "name"]))
    #expect(try backup.encoded() == original)
}

@Test func savedFittingReportRevalidatesArchiveIntegrityBeforeProjecting() throws {
    let backup = try reportBackup(sides: [.left], records: [reportRecord()])
    var object = try #require(JSONSerialization.jsonObject(with: backup.encoded()) as? [String: Any])
    object["clinicalRestoreSupported"] = true
    // Bypass the archive's explicit decode helper to exercise the report guard.
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let unchecked = try decoder.decode(DeviceBackup.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(throws: DeviceBackup.BackupError.invalid) { try SavedFittingReport(backup: unchecked) }
}
