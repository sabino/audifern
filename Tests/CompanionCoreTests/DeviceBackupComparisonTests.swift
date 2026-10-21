import Foundation
import Testing
@testable import CompanionCore

private let comparisonID = UUID()
private func comparisonBackup(id: UUID = comparisonID, serial: String? = nil, side: ConsumerProgramSnapshot.Side = .left,
                              volume: Int? = nil, record: Data? = nil,
                              settings: DeviceBackup.EndUserSettings? = nil, release: String = "5.0.29") throws -> DeviceBackup {
    let program = try ConsumerProgramSnapshot.Program(programID: 0, name: "Synthetic program", category: 0, boostable: false, tinnitus: false)
    let consumer = try ConsumerProgramSnapshot(aids: [.init(side: side, program: program,
        volume: try volume.map { try .init(level: $0, muted: false) })])
    let identity = DeviceBackup.Identity(peripheralID: id, serialNumber: serial, model: "Intent 3",
        hiidVersion: "4.5", releasePackageVersion: release, runtimeMemoryMapVersion: "10.0.0")
    let records = try record.map { [try DeviceBackup.Record(key: 1009, bytes: $0)] } ?? []
    return try .init(consumerControls: consumer, aids: [.init(side: side, identity: identity, records: records, endUserSettings: settings)])
}

@Test func comparisonDoesNotDecodeSectionsAcrossUnverifiedProfiles() throws {
    let record = try comparisonRecord(guid: 1)
    let a = try comparisonBackup(record: record)
    let b = try comparisonBackup(record: record, release: "5.0.30")
    let aid = try #require(DeviceBackupComparison(first: a, second: b).aids.first)
    #expect(aid.isComparable && aid.fittingRecord == .identical && aid.sections.isEmpty)
    #expect(aid.consumer[.program] == .identical)
}

@Test func comparisonStillReportsCapturedControlsWhenKnownBlobStructureCannotBeDecoded() throws {
    let payload = Data([1, 2, 3])
    let crc = OticonFittingRead.checksum(payload)
    let header = Data([0, 0, 4, 0, 0, 3, UInt8(crc >> 8), UInt8(crc & 255)]) + Data(repeating: 0, count: 8)
    let record = try OticonFittingRead.validateRecord(header: header, payload: payload)
    let a = try comparisonBackup(volume: 0, record: record), b = try comparisonBackup(volume: -1, record: record)
    let aid = try #require(DeviceBackupComparison(first: a, second: b).aids.first)
    #expect(aid.fittingRecord == .identical && aid.sections.isEmpty)
    #expect(aid.consumer[.mainVolume] == .changed)
}

@Test func comparisonKeepsOnlyCapturedScopesAndMarksNewlyReadValuesAsCoverageChanges() throws {
    func text(_ value: String) -> Data { Data([0x60 | UInt8(value.utf8.count)]) + Data(value.utf8) }
    let scope = Data([0xA3]) + text("name") + text("global") + text("count") + Data([2]) + text("access") + text("NVRAM")
    let inventory = Data([0xA1]) + text("scopes") + Data([0x81, 0x81]) + scope
    let firstSettings = try DeviceBackup.EndUserSettings(inventory: inventory, records: [
        .init(scope: 0, id: 0, bytes: Data([0x01]))
    ])
    let secondSettings = try DeviceBackup.EndUserSettings(inventory: inventory, records: [
        .init(scope: 0, id: 0, bytes: Data([0x02])), .init(scope: 0, id: 1, bytes: Data([0x03]))
    ])
    let a = try comparisonBackup(settings: firstSettings), b = try comparisonBackup(settings: secondSettings)
    let aid = try #require(DeviceBackupComparison(first: a, second: b).aids.first)
    #expect(aid.scopeInventory == .identical && aid.scopeMetadata == .notCaptured)
    #expect(aid.scopes.count == 2)
    #expect(aid.scopes[0].scope == 0 && aid.scopes[0].id == 0 && aid.scopes[0].difference == .changed)
    #expect(aid.scopes[1].id == 1 && aid.scopes[1].difference == .secondOnly)
    #expect(!firstSettings.isComplete && secondSettings.isComplete)
}

@Test func comparisonNeverTreatsMissingObservationsAsUnchanged() throws {
    let a = try comparisonBackup(), b = try comparisonBackup(volume: 1)
    let aid = try #require(DeviceBackupComparison(first: a, second: b).aids.first)
    #expect(aid.isComparable && aid.identity == .localIdentifier)
    #expect(aid.fittingRecord == .notCaptured && aid.sections.isEmpty)
    #expect(aid.consumer[.mainVolume] == .secondOnly)
    #expect(aid.consumer[.program] == .identical)
    #expect(aid.consumer[.microphoneEQ] == .notCaptured)
    #expect(aid.scopeInventory == .notCaptured && aid.scopes.isEmpty)
    let reversed = try #require(DeviceBackupComparison(first: b, second: a).aids.first)
    #expect(reversed.consumer[.mainVolume] == .firstOnly)
}

@Test func comparisonRefusesDifferentAidAndMissingEarEvenWhenOtherDataLooksEqual() throws {
    let a = try comparisonBackup(serial: "synthetic-alpha")
    let b = try comparisonBackup(serial: "synthetic-beta")
    let unrelated = try #require(DeviceBackupComparison(first: a, second: b).aids.first)
    #expect(unrelated.identity == .differentAid && !unrelated.isComparable)
    #expect(unrelated.fittingRecord == nil && unrelated.consumer.isEmpty && unrelated.scopes.isEmpty)
    let opposite = try comparisonBackup(side: .right)
    let ears = try DeviceBackupComparison(first: a, second: opposite).aids
    #expect(ears.count == 2 && ears.allSatisfy { $0.identity == .missingEar && !$0.isComparable })
}

@Test func comparisonCanMatchAnAidBySerialAcrossLocalBluetoothIdentityChanges() throws {
    let a = try comparisonBackup(serial: "synthetic-same", volume: 0)
    let b = try comparisonBackup(id: UUID(), serial: "synthetic-same", volume: -1)
    let aid = try #require(DeviceBackupComparison(first: a, second: b).aids.first)
    #expect(aid.identity == .serialNumber && aid.isComparable)
    #expect(aid.consumer[.mainVolume] == .changed)
}

private func comparisonRecord(guid: UInt8, selection: UInt8 = 0, parameters: UInt8 = 0, metadata: UInt8 = 0) throws -> Data {
    // A synthetic structural 0.1.0 blob. No actual fitting values or resources.
    var payload = Data(repeating: guid, count: 16)
    payload += Data([6, 0, selection, 0, 0, 0, 0, 0])
    payload += Data([5, 0, 255, 255, 255, 255, parameters])
    payload += Data([1, 0, metadata])
    let crc = OticonFittingRead.checksum(payload)
    let header = Data([0, 0, 4, 0, 0, UInt8(payload.count), UInt8(crc >> 8), UInt8(crc & 255)]) + Data(repeating: 0, count: 8)
    return try OticonFittingRead.validateRecord(header: header, payload: payload)
}

@Test func comparisonSeparatesRecordEnvelopeChangesFromFittedSectionChanges() throws {
    let a = try comparisonBackup(record: comparisonRecord(guid: 1))
    let b = try comparisonBackup(record: comparisonRecord(guid: 2))
    let guidOnly = try #require(DeviceBackupComparison(first: a, second: b).aids.first)
    #expect(guidOnly.fittingRecord == .changed)
    #expect(guidOnly.sections.values.allSatisfy { $0 == .identical })
    let c = try comparisonBackup(record: comparisonRecord(guid: 1, parameters: 3, metadata: 5))
    let sections = try #require(DeviceBackupComparison(first: a, second: c).aids.first).sections
    #expect(sections[.acoustics] == .identical)
    #expect(sections[.fittedParameters] == .changed && sections[.fittingMetadata] == .changed)
}
