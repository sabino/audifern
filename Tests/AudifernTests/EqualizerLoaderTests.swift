import Foundation
import Testing
@testable import Audifern

@MainActor private final class HeldEQReads {
    var started: [EqualizerLoader.Context] = []
    var continuations: [UUID: CheckedContinuation<Void, any Error>] = [:]
    func read(_ context: EqualizerLoader.Context) async throws {
        started.append(context)
        try await withCheckedThrowingContinuation { continuations[context.id] = $0 }
    }
    func finish(_ id: UUID, error: (any Error)? = nil) {
        let continuation = continuations.removeValue(forKey: id)
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }
}

@MainActor private func waitForEQ(_ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(2)
    while !condition() {
        try #require(Date() < deadline, "EQ reader did not reach its expected state")
        try await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor @Test func switchingFromLeftToBothLoadsTheMissingEarWithoutDuplicatingOrCancellingLeft() async throws {
    let reads = HeldEQReads()
    let loader = EqualizerLoader(read: reads.read)
    let left = EqualizerLoader.Context(id: UUID(), connectedAt: Date(), program: 1)
    let right = EqualizerLoader.Context(id: UUID(), connectedAt: Date(), program: 1)
    loader.request(left)
    try await waitForEQ { reads.started.count == 1 }
    loader.request(left); loader.request(right); loader.request(left, retry: true)
    try await waitForEQ { reads.started.count == 2 }
    #expect(reads.started.filter { $0.id == left.id }.count == 1)
    reads.finish(right.id)
    try await waitForEQ { loader.states[right.id]?.status == .loaded }
    #expect(loader.states[left.id]?.status == .loading)
    reads.finish(left.id)
    try await waitForEQ { loader.states[left.id]?.status == .loaded }
    loader.request(left); loader.request(right)
    #expect(reads.started.count == 2)
}

@MainActor @Test func aProgramChangeWaitsForOwnedCleanupAndDiscardsTheOlderReadsError() async throws {
    let reads = HeldEQReads()
    let loader = EqualizerLoader(read: reads.read)
    let initial = EqualizerLoader.Context(id: UUID(), connectedAt: Date(), program: 1)
    let changed = EqualizerLoader.Context(id: initial.id, connectedAt: initial.connectedAt, program: 2)
    loader.request(initial)
    try await waitForEQ { reads.started.count == 1 }
    loader.request(changed)
    #expect(reads.started.count == 1)
    #expect(loader.states[initial.id]?.context == changed)
    reads.finish(initial.id, error: UTLSession.SessionError.timeout)
    try await waitForEQ { reads.started.count == 2 }
    #expect(reads.started == [initial, changed])
    #expect(loader.states[initial.id]?.status == .loading)
    reads.finish(initial.id)
    try await waitForEQ { loader.states[initial.id]?.status == .loaded }
}

@MainActor @Test func aFailedEQReadStopsUntilAnExplicitRetryOrANewConnection() async throws {
    var calls = 0
    let loader = EqualizerLoader { _ in
        calls += 1
        if calls == 1 { throw UTLSession.SessionError.timeout }
    }
    let initial = EqualizerLoader.Context(id: UUID(), connectedAt: Date(), program: 1)
    loader.request(initial)
    try await waitForEQ { if case .failed = loader.states[initial.id]?.status { true } else { false } }
    loader.request(initial); loader.request(initial)
    #expect(calls == 1)
    loader.request(initial, retry: true)
    try await waitForEQ { loader.states[initial.id]?.status == .loaded }
    #expect(calls == 2)
    let reconnected = EqualizerLoader.Context(id: initial.id, connectedAt: initial.connectedAt?.addingTimeInterval(10), program: 1)
    loader.request(reconnected)
    try await waitForEQ { calls == 3 && loader.states[initial.id]?.status == .loaded }
}
