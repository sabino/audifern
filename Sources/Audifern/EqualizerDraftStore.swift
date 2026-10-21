import Combine
import CompanionCore
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
        let frequencies: [Double]?
    }
    private var microphoneContexts: [UUID: Context] = [:]
    private var streamingContexts: [UUID: Context] = [:]
    subscript(_ id: UUID, microphone source: Bool) -> [Double]? {
        get { source ? microphone[id] : streaming[id] }
        set { if source { microphone[id] = newValue } else { streaming[id] = newValue } }
    }
    func hasChanges(for aids: [AidConnection], microphone source: Bool) -> Bool {
        aids.contains { self[$0.id, microphone: source] != nil }
    }
    func clear(microphone source: Bool) { if source { microphone.removeAll() } else { streaming.removeAll() } }
    func channelValues(for aid: AidConnection, microphone source: Bool) -> [Double]? {
        guard let equalizer = source ? aid.microphoneEqualizer : aid.streamingEqualizer else { return nil }
        guard let pending = self[aid.id, microphone: source] else { return equalizer.channelDB }
        guard pending.allSatisfy(\.isFinite) else { return nil }
        if pending.count == 8 { return pending }
        if pending.count == 3 {
            return OticonEqualizer.groups.enumerated().flatMap { index, group in Array(repeating: pending[index], count: group.count) }
        }
        return nil
    }
    /// Stage only the touched channels in each ear's own vector. Preflight all
    /// targets before changing any draft; linking never copies untouched bands.
    @discardableResult func editChannels(_ aids: [AidConnection], microphone source: Bool,
                                        channels: [Int], value: Double) -> Bool {
        guard (1...2).contains(aids.count), Set(aids.map(\.id)).count == aids.count,
              value.isFinite, !channels.isEmpty, Set(channels).count == channels.count,
              channels.allSatisfy({ (0..<8).contains($0) }) else { return false }
        var pending: [UUID: [Double]] = [:]
        for aid in aids {
            guard let eq = source ? aid.microphoneEqualizer : aid.streamingEqualizer,
                  var values = channelValues(for: aid, microphone: source) else { return false }
            for channel in channels { values[channel] = value }
            guard (try? eq.steps(forChannelDB: values)) != nil else { return false }
            pending[aid.id] = values
        }
        for (id, values) in pending { self[id, microphone: source] = values }
        return true
    }
    func reconcile(_ connections: [UUID: AidConnection]) {
        for id in Set(microphoneContexts.keys).union(streamingContexts.keys).subtracting(connections.keys) {
            microphone[id] = nil; streaming[id] = nil; microphoneContexts[id] = nil; streamingContexts[id] = nil
        }
        for (id, aid) in connections {
            for source in [true, false] {
                let eq = source ? aid.microphoneEqualizer : aid.streamingEqualizer
                let context = Context(program: aid.activeProgram, connected: aid.isConnected, step: eq?.stepDB,
                                      minimum: eq?.minimumSteps, maximum: eq?.maximumSteps, frequencies: eq?.frequenciesHz)
                let old = source ? microphoneContexts[id] : streamingContexts[id]
                if old != context || !aid.isConnected || eq == nil { self[id, microphone: source] = nil }
                if source { microphoneContexts[id] = context } else { streamingContexts[id] = context }
            }
        }
    }
}
