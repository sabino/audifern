import CompanionCore
import SwiftUI
import UniformTypeIdentifiers

struct ProgramsView: View {
    @ObservedObject var store: BluetoothStore
    var detailsOnly = false
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var navigation: AppNavigation
    @State private var exporting = false
    @State private var document = DiagnosticsDocument(data: Data())
    @State private var exportStatus: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: L("Programs"), subtitle: L("Choose and inspect the programs fitted to your hearing aids.")) { ConnectionBadge(store: store) }
                if !detailsOnly && !store.orderedConnections.isEmpty { HearingAidControlsView(store: store, mode: .programs) }
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label(L("Program data"), systemImage: "doc.text.magnifyingglass").font(AppType.headline)
                            Spacer()
                            Text(L("Read-only")).font(AppType.caption.weight(.medium)).foregroundStyle(Brand.accent)
                        }
                        Text(L("Read a fresh snapshot of the active program’s metadata and available consumer controls. This is not a full clinical fitting backup."))
                            .font(AppType.callout).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button(L("Read program snapshot")) { store.readProgramSnapshot() }
                                .buttonStyle(.borderedProminent).tint(Brand.controlTint).font(AppType.body)
                                .disabled(store.connectedCount == 0 || store.programSnapshotBusy || store.isDemo)
                                .accessibilityIdentifier("read-program-snapshot")
                            if store.programSnapshotBusy { ProgressView().controlSize(.small) }
                            Button(L("Export snapshot…")) {
                                do {
                                    if let snapshot = store.programSnapshot { document = DiagnosticsDocument(data: try snapshot.encoded()); exporting = true }
                                } catch { exportStatus = L("Could not prepare the snapshot.") }
                            }.disabled(store.programSnapshot == nil || store.programSnapshotBusy)
                        }
                        if let snapshot = store.programSnapshot {
                            Text(snapshot.capturedAt, format: .dateTime.year().month().day().hour().minute())
                                .font(AppType.caption).foregroundStyle(.secondary)
                            ForEach(snapshot.aids, id: \.side) { aid in
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack { Text(L(aid.side.rawValue.capitalized)).font(AppType.callout.weight(.semibold)); Spacer(); Text(aid.program.name).font(AppType.callout) }
                                    LabeledContent(L("Speech boost support"), value: aid.program.boostable ? L("Available") : L("Not available"))
                                    LabeledContent(L("Tinnitus support"), value: aid.program.tinnitus ? L("Available") : L("Not available"))
                                    if let volume = aid.volume {
                                        LabeledContent(L("Volume"), value: L("%d · %@", volume.level, volume.muted ? L("Muted") : L("Unmuted")))
                                    }
                                    LabeledContent(L("Microphone EQ"), value: aid.microphoneEqualizer == nil ? L("Not reported") : L("Eight bands read"))
                                    LabeledContent(L("Streaming EQ"), value: aid.streamingEqualizer == nil ? L("Not reported") : L("Eight bands read"))
                                }.font(AppType.caption).padding(14).background(Brand.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                            }
                            Text(L("The export excludes serial numbers, Bluetooth identifiers, authentication data and audiograms. It cannot create or restore a clinical fitting."))
                                .font(AppType.caption).foregroundStyle(.secondary)
                        }
                        if let status = store.programSnapshotStatus { Text(M(status)).font(AppType.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        if let exportStatus { Text(exportStatus).font(AppType.caption).foregroundStyle(.secondary) }
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L("Programs and presets"), systemImage: "info.circle").font(AppType.headline)
                    Text(L("A sound preset saves your own volume and EQ adjustments for an existing fitted program. Creating or cloning a fitted hearing-aid program has not been established through the consumer Bluetooth service. Audiograms are records, not prescriptions; fitted programs belong to the separate fitting workflow."))
                        .font(AppType.callout).foregroundStyle(.secondary).padding(.top, 10)
                        Button(L("Open presets")) { navigation.show(.presets) }
                    }
                }
            }.padding(30).frame(maxWidth: 1100)
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "audifern-consumer-program") { result in
            switch result { case .success: exportStatus = L("Snapshot exported."); case .failure: exportStatus = L("The export was not completed.") }
        }
    }
}
