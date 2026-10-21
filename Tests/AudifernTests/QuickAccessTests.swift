import Foundation
import QuickAccessKit
import Testing

private func quickState(date: Date, left: Int = 0, right: Int = 2) -> QuickAccessState {
    .init(session: UUID(), updatedAt: date, sharingEnabled: true, ears: [
        .init(side: .left, connected: true, battery: 76, runtime: nil, level: left, muted: false, minimum: -8, maximum: 4, canChangeVolume: true, speechBooster: false, canChangeSpeechBooster: true),
        .init(side: .right, connected: true, battery: 68, runtime: nil, level: right, muted: false, minimum: -8, maximum: 4, canChangeVolume: true, speechBooster: false, canChangeSpeechBooster: true)
    ], paused: false, canReconnect: true, macAudio: true, canSwitchAudio: true)
}
@Test func quickControlsRejectExpiredSnapshotsCommandsAndChangedSessions() {
    let now = Date(timeIntervalSince1970: 100_000), state = quickState(date: Date(timeIntervalSince1970: 100_000))
    let valid = QuickCommand(session: state.session, createdAt: now, kind: .mute, flag: true)
    #expect(state.permits(valid, at: now))
    #expect(!state.permits(valid, at: now - 1))
    #expect(!state.permits(valid, at: now + 9))
    #expect(!state.isFresh(at: now + 91))
    #expect(!state.permits(.init(session: UUID(), createdAt: now, kind: .mute, flag: true), at: now))
    #expect(!state.permits(.init(session: state.session, createdAt: now, kind: .volume, delta: 25), at: now))
    #expect(!state.permits(.init(session: state.session, createdAt: now, kind: .mute, delta: 1, flag: true), at: now))
}
@Test func groupedQuickVolumeRespectsBothEarsLimitsAndCanTargetOneEar() {
    let now = Date(timeIntervalSince1970: 100_000), state = quickState(date: Date(timeIntervalSince1970: 100_000), right: 4)
    #expect(!state.permits(.init(session: state.session, createdAt: now, kind: .volume, delta: 1), at: now))
    #expect(state.permits(.init(session: state.session, createdAt: now, kind: .volume, target: .left, delta: 1), at: now))
    #expect(state.permits(.init(session: state.session, createdAt: now, kind: .volume, delta: -1), at: now))
}
@Test func quickMailboxClaimsOnceAndNeverReplaysAcrossRestart() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = QuickAccessStorage(container: directory), now = Date(), state = quickState(date: Date())
    try storage.save(state)
    let command = QuickCommand(session: state.session, createdAt: now, kind: .mute, flag: true)
    try storage.enqueue(command, now: now)
    #expect(storage.claimNext(now: now)?.id == command.id)
    #expect(storage.claimNext(now: now) == nil)
    let restarted = QuickAccessStorage(container: directory)
    #expect(restarted.claimNext(now: now) == nil)
    try restarted.acknowledge(.init(id: command.id, accepted: true, message: "Synthetic confirmation"))
    #expect(restarted.receipt(command.id)?.accepted == true)
    restarted.removeReceipt(command.id)
    #expect(restarted.receipt(command.id) == nil)
}
@Test func staleMailboxActionsAreRemovedAndSymlinksCannotSupplyCommands() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = QuickAccessStorage(container: directory), now = Date(), state = quickState(date: Date())
    try storage.save(state)
    let command = QuickCommand(session: state.session, createdAt: now, kind: .mute, flag: false)
    try storage.enqueue(command, now: now)
    #expect(storage.claimNext(now: now + 9) == nil)
    let outside = directory.appendingPathComponent("outside.json")
    try JSONEncoder().encode(command).write(to: outside)
    try FileManager.default.createSymbolicLink(at: storage.inbox.appendingPathComponent(command.id.uuidString + ".json"), withDestinationURL: outside)
    #expect(storage.claimNext(now: now) == nil)
    #expect(FileManager.default.fileExists(atPath: outside.path))
}
@Test func disablingWidgetSharingDisablesEveryQuickAction() {
    let now = Date(), before = quickState(date: Date())
    let state = QuickAccessState(session: before.session, updatedAt: now, sharingEnabled: false, ears: before.ears,
        paused: false, canReconnect: true, macAudio: true, canSwitchAudio: true)
    for kind in [QuickCommand.Kind.mute, .speechBooster, .connection, .audio] {
        #expect(!state.permits(.init(session: state.session, createdAt: now, kind: kind, flag: true), at: now))
    }
}
