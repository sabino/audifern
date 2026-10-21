import CompanionCore
import Foundation
import Testing
@testable import Audifern

private func faderAid(_ level: Int, right: Bool = false, muted: Bool = false, range: ClosedRange<Int> = -8...4) -> AidConnection {
    var aid = AidConnection(id: UUID(), name: "Synthetic aid", phase: .connected)
    aid.sinkAudioLocations = right ? 2 : 1
    aid.volume = OticonRemoteProtocol.volumePayload(level: level, muted: muted, reportedRange: range).flatMap(OticonRemoteProtocol.Volume.init)
    aid.volumeRanges = .init(data: Data([UInt8(bitPattern: Int8(range.lowerBound)), UInt8(bitPattern: Int8(range.upperBound)), 0, 18, 0xFB, 0]))
    aid.writableVolume = true; aid.activeProgram = 0
    return aid
}

@Test func linkedFaderUsesCommonMovementAndPreservesAsymmetricBalanceAndMute() throws {
    let left = faderAid(-3), right = faderAid(1, right: true, muted: true, range: -5...3)
    let selection = try #require(MainVolumeSelection(aids: [left, right], anchorID: left.id))
    #expect(selection.range == -8 ... -1)
    let levels = try #require(selection.levels(setting: -1))
    #expect(levels[left.id] == -1 && levels[right.id] == 3)
    #expect(selection.levels(setting: 0) == nil)
    #expect(selection.levels(setting: Int.max) == nil)
    let plan = try ConsumerControlPlan(aids: [left, right], change: .volumeLevels(levels))
    #expect(plan.steps[0].setting == .volume(level: -1, muted: false))
    #expect(plan.steps[1].setting == .volume(level: 3, muted: true))
    let rightSelection = try #require(MainVolumeSelection(aids: [left, right], anchorID: right.id))
    #expect(rightSelection.range == -4...3)
    #expect(rightSelection.levels(setting: -4) == [left.id: -8, right.id: -4])
}

@Test func individualFaderRejectsStaleVolumeMuteProgramLimitsAndPendingWork() throws {
    let aid = faderAid(2)
    let selection = try #require(MainVolumeSelection(aids: [aid], anchorID: aid.id))
    #expect(selection.range == -8...4)
    #expect(selection.matches([aid.id: aid]))
    let plan = try ConsumerControlPlan(aids: [aid], change: .volumeLevels([aid.id: -2]))
    for change in 0..<5 {
        var stale = aid
        switch change {
        case 0: stale.volume = .init(data: Data([3, 1]))
        case 1: stale.volume = .init(data: Data([2, 0]))
        case 2: stale.activeProgram = 1
        case 3: stale.volumeRanges = .init(data: Data([0xF8, 3, 0, 18, 0xFB, 0]))
        default: stale.actionPending = true
        }
        #expect(!selection.matches([aid.id: stale]))
        if change != 3 { #expect(throws: (any Error).self) { try plan.steps[0].validate(stale) } }
    }
    #expect(!selection.matches([:]))
}

@Test func faderPreflightRequiresExactTargetsAndBothReportedRanges() throws {
    let left = faderAid(0), right = faderAid(0, right: true, range: 0...0)
    let selection = try #require(MainVolumeSelection(aids: [left, right], anchorID: left.id))
    #expect(selection.range == 0...0)
    #expect(selection.levels(setting: 1) == nil)
    #expect(MainVolumeSelection(aids: [left, left], anchorID: left.id) == nil)
    #expect(MainVolumeSelection(aids: [], anchorID: left.id) == nil)
    #expect(MainVolumeSelection(aids: [left], anchorID: right.id) == nil)
    var unknown = right; unknown.volumeRanges = nil
    #expect(MainVolumeSelection(aids: [left, unknown], anchorID: left.id) == nil)
    #expect(throws: (any Error).self) { try ConsumerControlPlan(aids: [left, right], change: .volumeLevels([left.id: 1])) }
    #expect(throws: (any Error).self) { try ConsumerControlPlan(aids: [left, right], change: .volumeLevels([left.id: 1, right.id: 1])) }
}

@MainActor @Test func faderDragPreviewsWithoutWritesAndCommitsOriginalSnapshotOnceOnRelease() {
    var previews: [Int?] = [], first: [Int] = [], replacement: [Int] = []
    let fader = NativeVolumeSlider(value: 0, range: -8...4, enabled: true, label: "Synthetic volume",
        preview: { previews.append($0) }, commit: { first.append($0) })
    let coordinator = NativeVolumeSlider.Coordinator(fader)
    coordinator.begin()
    coordinator.change(1, tracking: true); coordinator.change(3, tracking: true)
    #expect(first.isEmpty && previews == [1, 3])
    // A re-render during tracking must not silently replace the release action.
    coordinator.parent = .init(value: 2, range: -8...4, enabled: true, label: "Synthetic volume",
        preview: { previews.append($0) }, commit: { replacement.append($0) })
    coordinator.end(3)
    #expect(first == [3] && replacement.isEmpty && previews.last! == nil)
    coordinator.end(3)
    #expect(first == [3])
    coordinator.change(1, tracking: false)
    #expect(replacement == [1])
    coordinator.change(2, tracking: false)
    #expect(replacement == [1])
}

@MainActor @Test func releasingFaderAtItsInitialValueSendsNothing() {
    var commits: [Int] = []
    let coordinator = NativeVolumeSlider.Coordinator(.init(value: -2, range: -8...4, enabled: true,
        label: "Synthetic volume", preview: { _ in }, commit: { commits.append($0) }))
    coordinator.begin(); coordinator.change(2, tracking: true); coordinator.end(-2)
    #expect(commits.isEmpty)
}
