import CompanionCore
import Foundation
import Testing

private func backupFixture(sides: [ConsumerProgramSnapshot.Side] = [.left, .right]) throws -> DeviceBackup {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let program = try ConsumerProgramSnapshot.Program(programID: 0, name: "Everyday", category: 0, boostable: true, tinnitus: false)
    let consumer = try ConsumerProgramSnapshot(capturedAt: date, aids: sides.map { try .init(side: $0, program: program) })
    return try .init(capturedAt: date, consumerControls: consumer, aids: sides.map {
        .init(side: $0, identity: .init(peripheralID: UUID(), model: "Synthetic aid"), programs: [program])
    })
}

@Test func backupArchiveRoundTripsAndChecksItsStoredPayload() throws {
    let fixture = try backupFixture()
    let archive = try DeviceBackupArchive(fixture)
    let decoded = try DeviceBackupArchive.decode(archive.encoded())
    #expect(try decoded.verifiedBackup() == fixture)
    #expect(!fixture.clinicalRestoreSupported)
    #expect(fixture.aids.allSatisfy { $0.records.isEmpty })
}

@Test func backupArchiveRejectsCorruptedPayloadBeforeDecoding() throws {
    let archive = try DeviceBackupArchive(backupFixture())
    var object = try #require(JSONSerialization.jsonObject(with: archive.encoded()) as? [String: Any])
    object["payload"] = Data("changed".utf8).base64EncodedString()
    #expect(throws: DeviceBackup.BackupError.digestMismatch) {
        try DeviceBackupArchive.decode(JSONSerialization.data(withJSONObject: object))
    }
}

@Test func backupRecordHasIndependentIntegrityAndBounds() throws {
    let record = try DeviceBackup.Record(key: 1009, bytes: Data([0, 1, 2]))
    #expect(record.sha256 == DeviceBackup.digest(Data([0, 1, 2])))
    #expect(throws: DeviceBackup.BackupError.invalid) { try DeviceBackup.Record(key: 1009, bytes: Data()) }
    #expect(throws: DeviceBackup.BackupError.invalid) { try DeviceBackup.Record(key: 1009, bytes: Data(repeating: 0, count: 65_536)) }
}

@Test func backupRejectsMismatchedOrDuplicatedEars() throws {
    let fixture = try backupFixture()
    #expect(throws: DeviceBackup.BackupError.invalid) {
        try DeviceBackup(consumerControls: fixture.consumerControls, aids: [fixture.aids[0]])
    }
    #expect(throws: DeviceBackup.BackupError.invalid) {
        try DeviceBackup(consumerControls: fixture.consumerControls, aids: [fixture.aids[0], fixture.aids[0]])
    }
}

@Test func backupFormatCannotClaimClinicalRestoreByEditingTheFlag() throws {
    var object = try #require(JSONSerialization.jsonObject(with: backupFixture().encoded()) as? [String: Any])
    object["clinicalRestoreSupported"] = true
    #expect(throws: DeviceBackup.BackupError.invalid) {
        try DeviceBackup.decode(JSONSerialization.data(withJSONObject: object))
    }
}

@Test func backupReadOnlySessionPreservesHonestApplicationIdentityAndRefusesUnknownContract() throws {
    let service = UTLProtocol.Service(id: UTLConsumerSession.serviceID, handle: 1, major: 1, minor: 1, status: 0xFF)
    let payload = try UTLReadOnlySession.openPayload(service: service, privateToken: 1, timeSince2020: 2, version: (0, 6, 2))
    #expect(payload == Data([4, 0, 0, 0, 1, 0, 0, 0, 2, 3, 0, 0, 0, 6, 0, 2, 1]))
    #expect(UTLReadOnlySession.readNVRAMTransaction == 2)
    let unknown = UTLProtocol.Service(id: UTLConsumerSession.serviceID, handle: 1, major: 1, minor: 0, status: 0xFF)
    #expect(throws: UTLProtocol.CodecError.self) {
        try UTLReadOnlySession.openPayload(service: unknown, privateToken: 1, timeSince2020: 2, version: (0, 6, 2))
    }
}

@Test func backupPreservesValidatedIdentificationIncludingUnknownHardwareEntries() throws {
    // Synthetic map: version4.5 plus an uninterpreted key1002 byte string.
    let payload = Data([0xA2, 0x19, 0x03, 0xE9, 0x42, 4, 5, 0x19, 0x03, 0xEA, 0x43, 1, 2, 3])
    let original = try backupFixture(sides: [.left])
    let identity = DeviceBackup.Identity(peripheralID: UUID(), hiidVersion: "4.5")
    let backup = try DeviceBackup(consumerControls: original.consumerControls,
        aids: [.init(side: .left, identity: identity, identification: payload)])
    let decoded = try DeviceBackupArchive.decode(DeviceBackupArchive(backup).encoded()).verifiedBackup()
    #expect(decoded.aids.first?.identification == payload)
    #expect(throws: DeviceBackup.BackupError.invalid) {
        try DeviceBackup(consumerControls: original.consumerControls, aids: [.init(side: .left,
            identity: .init(peripheralID: UUID(), hiidVersion: "4.6"), identification: payload)])
    }
}
