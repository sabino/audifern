import CompanionCore
import Foundation
import Testing
@testable import Audifern

private func localBackupFixture() throws -> DeviceBackup {
    let program = try ConsumerProgramSnapshot.Program(programID: 0, name: "Synthetic", category: 0, boostable: false, tinnitus: false)
    let consumer = try ConsumerProgramSnapshot(aids: [.init(side: .left, program: program)])
    return try .init(consumerControls: consumer, aids: [.init(side: .left, identity: .init(peripheralID: UUID()))])
}

@MainActor @Test func savedBackupIsPrivateVerifiedAndCannotOverwriteAnExistingCheckpoint() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = DeviceBackupStore(folder: folder)
    let fixture = try localBackupFixture()
    let file = try store.save(fixture)
    let bytes = try Data(contentsOf: file)
    #expect(store.entries.count == 1)
    #expect(try DeviceBackupArchive.decode(bytes).verifiedBackup().id == fixture.id)
    let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
    #expect(mode?.intValue == 0o600)
    let directoryMode = try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? NSNumber
    #expect(directoryMode?.intValue == 0o700)
    #expect(throws: (any Error).self) { try store.save(fixture) }
    #expect(try Data(contentsOf: file) == bytes)
}

@MainActor @Test func corruptBackupIsPreservedAndReportedWithoutBeingLoaded() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("broken.audifern-backup.json")
    let bytes = Data("corrupt".utf8); try bytes.write(to: file)
    let store = DeviceBackupStore(folder: folder)
    #expect(store.entries.isEmpty && store.failedFileCount == 1)
    #expect(try Data(contentsOf: file) == bytes)
    try store.save(localBackupFixture())
    #expect(store.entries.count == 1 && store.failedFileCount == 1)
    #expect(store.status == "Some backups could not be verified. Their files have been preserved.")
    #expect(try Data(contentsOf: file) == bytes)
}

@MainActor @Test func backupStoreRefusesDirectorySymlink() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let real = root.appendingPathComponent("real"), link = root.appendingPathComponent("link")
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    let store = DeviceBackupStore(folder: link)
    #expect(throws: (any Error).self) { try store.save(localBackupFixture()) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: real.path).isEmpty)
}

@MainActor @Test func unreadableFittingPlanCannotBeSilentlyOverwritten() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("plan.json"), bytes = Data("invalid".utf8)
    try bytes.write(to: file)
    let store = FittingWorkspaceStore(file: file)
    #expect(store.loadFailed)
    store.draft.name = "Changed plan"; store.save()
    #expect(try Data(contentsOf: file) == bytes)
}

@MainActor @Test func localFittingPlanPersistsIndependentlyOfAnyBluetoothConnection() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("plan.json")
    let store = FittingWorkspaceStore(file: file)
    store.draft.name = "Independent plan"; store.draft.model = .intent3
    store.save()
    #expect(store.canLoadDraft)
    let restored = FittingWorkspaceStore(file: file)
    #expect(restored.draft.name == "Independent plan" && restored.draft.model == .intent3)
    #expect(!restored.draft.clinicalFittingIncluded)
}

@Test func headlessBackupRequiresExplicitOutputAndCannotMixWithProbeOrPreview() {
    #expect(LaunchConfiguration(arguments: ["app", "--backup-seconds", "20"]).error != nil)
    #expect(LaunchConfiguration(arguments: ["app", "--backup-output", ""]).error != nil)
    #expect(LaunchConfiguration(arguments: ["app", "--backup-output", "backup.json", "--demo"]).error != nil)
    #expect(LaunchConfiguration(arguments: ["app", "--backup-output", "backup.json", "--probe-seconds", "20", "--probe-output", "probe.jsonl"]).error != nil)
    let valid = LaunchConfiguration(arguments: ["app", "--backup-output", "backup.json", "--backup-seconds", "60"])
    #expect(valid.error == nil && valid.isBackup && !valid.isProbe)
}

@Test func privateFileCreationPreservesExistingParentPermissions() throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: parent) }
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                                          attributes: [.posixPermissions: 0o750])
    try FileManager.default.setAttributes([.posixPermissions: 0o750], ofItemAtPath: parent.path)
    let file = parent.appendingPathComponent("private.json")
    try PrivateDocuments.writeNew(Data("private".utf8), to: file)
    #expect((try FileManager.default.attributesOfItem(atPath: parent.path)[.posixPermissions] as? NSNumber)?.intValue == 0o750)
    #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@MainActor @Test func interruptedReadArchivesRemainSeparateFromTheOriginalCheckpoint() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = DeviceBackupStore(folder: folder)
    let fixture = try localBackupFixture()
    let checkpoint = try DeviceBackup(consumerControls: fixture.consumerControls, aids: fixture.aids,
                                      acquisitionStage: .consumerCheckpoint)
    let first = try store.save(checkpoint)
    let bytes = try Data(contentsOf: first)
    let partial = try DeviceBackup(consumerControls: fixture.consumerControls, aids: fixture.aids,
                                   acquisitionStage: .partialRead)
    let second = try store.save(partial)
    #expect(first != second && store.entries.count == 2)
    #expect(try Data(contentsOf: first) == bytes)
    #expect(try DeviceBackupArchive.decode(Data(contentsOf: second)).verifiedBackup().acquisitionStage == .partialRead)
}
