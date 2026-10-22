import SwiftUI

/// One result for any selection, with individual evidence in its disclosure.
/// A successful ear can never hide the other ear's failure or disconnection.
struct EqualizerReadSummary {
    enum State: Equatable { case disconnected, loading, loaded, missing, failed(String) }
    struct Ear: Identifiable {
        let id: UUID
        let side: String
        let state: State
        var message: String {
            switch state {
            case .disconnected: L("%@ is disconnected.", L(side))
            case .loading: L("Loading %@ EQ…", L(side))
            case .loaded: L("%@ EQ loaded", L(side))
            case .missing: L("%@ EQ is not loaded.", L(side))
            case .failed(let error): L("Could not load %@ EQ.", L(side)) + " " + M(error)
            }
        }
    }
    let ears: [Ear]
    init(aids: [AidConnection], microphone: Bool, states: [UUID: EqualizerLoader.State]) {
        ears = aids.map { aid in
            let state: State
            let context = EqualizerLoader.Context(id: aid.id, connectedAt: aid.connectedAt, program: aid.activeProgram)
            if !aid.isConnected { state = .disconnected }
            else if let read = states[aid.id], read.context == context, read.status == .loading { state = .loading }
            else if let read = states[aid.id], read.context == context, case .failed(let error) = read.status { state = .failed(error) }
            else if (microphone ? aid.microphoneEqualizer : aid.streamingEqualizer) != nil { state = .loaded }
            else { state = .missing }
            return .init(id: aid.id, side: aid.sideLabel, state: state)
        }
    }
    var isLoading: Bool { ears.contains { $0.state == .loading } }
    var isLoaded: Bool { !ears.isEmpty && ears.allSatisfy { $0.state == .loaded } }
    var hasProblem: Bool { ears.contains { if case .failed = $0.state { true } else { $0.state == .disconnected } } }
    var detail: String { ears.map(\.message).joined(separator: "\n") }
    var symbol: String { hasProblem ? "exclamationmark.circle" : isLoaded ? "checkmark.circle" : "circle.dotted" }
}

struct EqualizerReadStatusView: View {
    let summary: EqualizerReadSummary
    let identifier: String
    var allowsRefresh = true
    var canRefresh = true
    let refresh: () -> Void
    @State private var showingDetails = false
    var body: some View {
        HStack(spacing: 6) {
            Button { showingDetails.toggle() } label: {
                Group {
                    if summary.isLoading { ProgressView().controlSize(.mini) }
                    else { Image(systemName: summary.symbol).foregroundStyle(summary.hasProblem ? Color.orange : Brand.accent) }
                }.frame(width: 22, height: 22).contentShape(Rectangle())
            }.buttonStyle(.plain).help(summary.detail)
                .accessibilityLabel(L("EQ read status"))
                .accessibilityValue(summary.detail)
                .accessibilityIdentifier("\(identifier)-status")
                .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("EQ read status")).font(AppType.headline)
                        ForEach(summary.ears) { ear in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: ear.state == .loaded ? "checkmark.circle" : "info.circle").foregroundStyle(.secondary)
                                Text(ear.message).font(AppType.caption).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }.padding(18).frame(width: 300)
                }
            if allowsRefresh {
                Button(action: refresh) { Image(systemName: "arrow.clockwise").frame(width: 22, height: 22) }
                    .buttonStyle(.borderless).disabled(summary.isLoading || !canRefresh)
                    .help(summary.ears.count == 2 ? L("Refresh both EQs") : L("Refresh"))
                    .accessibilityLabel(summary.ears.count == 2 ? L("Refresh both EQs") : L("Refresh %@ EQ", summary.ears.first.map { L($0.side) } ?? L("Hearing aid")))
                    .accessibilityIdentifier(identifier)
            }
        }.font(AppType.small).frame(height: 24)
    }
}
