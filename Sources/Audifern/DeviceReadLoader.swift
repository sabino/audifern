import Combine
import Foundation

/// Coalesces read-only work per connection/program and aid. A second ear can
/// load independently; new contexts wait for owned transport cleanup.
@MainActor final class DeviceReadLoader: ObservableObject {
    struct Context: Equatable {
        let id: UUID
        let connectedAt: Date?
        let program: Int?
    }
    enum Status: Equatable {
        case loading, loaded, failed(String)
        var isLoading: Bool { self == .loading }
    }
    struct State: Equatable {
        let context: Context
        var status: Status
    }
    @Published private(set) var states: [UUID: State] = [:]
    private var pending: [UUID: Context] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let read: @MainActor (Context) async throws -> Void

    init(read: @escaping @MainActor (Context) async throws -> Void) { self.read = read }

    func request(_ context: Context, retry: Bool = false) {
        // A failed read stays retryable instead of becoming an automatic loop.
        if states[context.id]?.context == context,
           (!retry || states[context.id]?.status.isLoading == true) { return }
        states[context.id] = State(context: context, status: .loading)
        pending[context.id] = context
        guard tasks[context.id] == nil else { return }
        tasks[context.id] = Task { [weak self] in
            guard let self else { return }
            defer { self.tasks[context.id] = nil }
            while let next = self.pending.removeValue(forKey: context.id) {
                do {
                    try await self.read(next)
                    if self.states[next.id]?.context == next { self.states[next.id]?.status = .loaded }
                } catch {
                    if self.states[next.id]?.context == next {
                        self.states[next.id]?.status = .failed(UTLSession.describe(error))
                    }
                }
            }
        }
    }
}

typealias EqualizerLoader = DeviceReadLoader
