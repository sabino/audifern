import CompanionCore
import SwiftUI
import UniformTypeIdentifiers

struct DeveloperView: View {
    @ObservedObject var store: BluetoothStore
    @EnvironmentObject private var preferences: AppPreferences
    @State private var section = "activity"
    @State private var exporting = false
    @State private var document = DiagnosticsDocument(data: Data())
    @State private var exportStatus: String?
    private var identifiers: [String] {
        store.connections.values.flatMap { [$0.id.uuidString, $0.name, $0.serialNumber ?? ""] } + store.devices.map(\.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(title: L("Developer"), subtitle: L("Inspect this connection. Nothing is uploaded.")) {
                Button(L("Export diagnostics…")) { prepareExport() }.disabled(store.events.isEmpty)
            }.padding(.horizontal, 30).padding(.top, 30)
            Picker(L("Developer tools"), selection: $section) {
                Text(L("Activity log")).tag("activity")
                Text(L("Advanced Bluetooth")).tag("bluetooth")
            }.pickerStyle(.segmented).font(AppType.body).frame(maxWidth: 430).padding(.horizontal, 30)
                .accessibilityIdentifier("developer-section")
            if section == "bluetooth" {
                DeviceExplorerView(store: store, technicalOnly: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label(preferences.showIdentifiers ? L("Identifiers visible on this Mac") : L("Identifiers hidden"), systemImage: "eye.slash")
                                .font(AppType.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(L("Clear log")) { store.clearEvents() }.buttonStyle(.borderless)
                        }
                        Text(L("Exports always omit identifiers, raw packets and authentication material, even when identifiers are visible locally."))
                            .font(AppType.caption).foregroundStyle(.secondary)
                        if let exportStatus { Text(exportStatus).font(AppType.caption).foregroundStyle(.secondary) }
                        if store.events.isEmpty { ContentUnavailableView(L("No events yet"), systemImage: "text.alignleft") }
                        ForEach(store.events.reversed()) { event in
                            ExpandableSection {
                                let details = DiagnosticPrivacy.shareableDetails(event.details, identifiers: identifiers)
                                ForEach(details.keys.sorted(), id: \.self) { key in
                                    LabeledContent(key, value: details[key] ?? "").font(AppType.caption.monospaced()).textSelection(.enabled)
                                }
                                if details.isEmpty { Text(L("No shareable protocol details.")).font(AppType.caption).foregroundStyle(.secondary) }
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 14) {
                                    Text(event.timestamp, style: .time).monospacedDigit().foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
                                    Text(preferences.showIdentifiers ? M(event.message) : M(DiagnosticPrivacy.redact(event.message, identifiers: identifiers)))
                                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }.font(AppType.callout)
                            }.padding(14).background(Brand.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.padding(.horizontal, 30).padding(.bottom, 30)
                }
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "audifern-diagnostics") { result in
            switch result { case .success: exportStatus = L("Diagnostics exported."); case .failure: exportStatus = L("The export was not completed.") }
        }
    }

    private func prepareExport() {
        let rows = store.events.map { event in
            ["time": ISO8601DateFormatter().string(from: event.timestamp), "event": event.event,
             "message": DiagnosticPrivacy.redact(event.message, identifiers: identifiers),
             "details": DiagnosticPrivacy.shareableDetails(event.details, identifiers: identifiers)] as [String: Any]
        }
        let payload: [String: Any] = ["application": Brand.name, "schemaVersion": 1, "redacted": true,
                                      "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
                                      "events": rows]
        do {
            document = DiagnosticsDocument(data: try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]))
            exporting = true
        } catch { exportStatus = L("Could not prepare diagnostics.") }
    }
}

struct DiagnosticsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
