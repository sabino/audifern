import Combine
import Foundation

/// Keep unapplied sound drafts when navigating between pages or changing the
/// interface language. Device/program invalidation still clears stale drafts.
@MainActor final class EqualizerDraftStore: ObservableObject {
    @Published private var microphone: [UUID: [Double]] = [:]
    @Published private var streaming: [UUID: [Double]] = [:]
    private struct Context: Equatable {
        let program: Int?
        let connected: Bool
        let step: Double?
        let minimum: [Int]?
        let maximum: [Int]?
    }
    private var microphoneContexts: [UUID: Context] = [:]
    private var streamingContexts: [UUID: Context] = [:]
    subscript(_ id: UUID, microphone source: Bool) -> [Double]? {
        get { source ? microphone[id] : streaming[id] }
        set { if source { microphone[id] = newValue } else { streaming[id] = newValue } }
    }
    func clear(microphone source: Bool) { if source { microphone.removeAll() } else { streaming.removeAll() } }
    func reconcile(_ connections: [UUID: AidConnection]) {
        for id in Set(microphoneContexts.keys).union(streamingContexts.keys).subtracting(connections.keys) {
            microphone[id] = nil; streaming[id] = nil; microphoneContexts[id] = nil; streamingContexts[id] = nil
        }
        for (id, aid) in connections {
            for source in [true, false] {
                let eq = source ? aid.microphoneEqualizer : aid.streamingEqualizer
                let context = Context(program: aid.activeProgram, connected: aid.isConnected, step: eq?.stepDB,
                                      minimum: eq?.minimumSteps, maximum: eq?.maximumSteps)
                let old = source ? microphoneContexts[id] : streamingContexts[id]
                if old != context || !aid.isConnected || eq == nil { self[id, microphone: source] = nil }
                if source { microphoneContexts[id] = context } else { streamingContexts[id] = context }
            }
        }
    }
}
