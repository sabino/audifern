import CompanionCore
import SwiftUI
import UniformTypeIdentifiers

/// Local records only. `onSaved` can associate an exam UUID with a manual sound preset;
/// it does not turn hearing thresholds into fitting gains or write to a hearing aid.
struct AudiogramEditorView: View {
    @StateObject private var store: AudiogramEditorStore
    private let onSaved: ((Audiogram) -> Void)?
    @State private var conduction = AudiogramConduction.air
    @State private var masked = false
    @State private var pendingAction: PendingAction?
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @State private var confirmClear = false
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument = AudiogramExportDocument()
    @State private var exportType = UTType.json
    @State private var showingHIMSAExport = false
    @State private var himsaSignal = HIMSAAudiogramExport.Signal.unknown
    @State private var himsaTransducer: HIMSAAudiogramExport.AirTransducer?

    private enum PendingAction { case new, select(UUID), importFile, revert }

    init(selectedExamID: UUID? = nil, onSaved: ((Audiogram) -> Void)? = nil) {
        _store = StateObject(wrappedValue: AudiogramEditorStore(selectedExamID: selectedExamID))
        self.onSaved = onSaved
    }

    init(store: AudiogramEditorStore, onSaved: ((Audiogram) -> Void)? = nil) {
        _store = StateObject(wrappedValue: store)
        self.onSaved = onSaved
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    GroupBox {
                        Text("Keep a plotted copy of your exam and export it as JSON or HIMSA XML. A sound preset can reference this exam; applying a preset restores the volume and EQ you saved manually. Exam values do not program the hearing aids.")
                            .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    } label: { Label("What this is used for", systemImage: "info.circle") }
                    metadata
                    HStack(alignment: .top, spacing: 24) {
                        graphPanel.frame(minWidth: 350, maxWidth: .infinity)
                        entryPanel.frame(width: 400)
                    }
                    notes
                    footer
                    if showingHIMSAExport { himsaExportOptions.id("himsa-export-options") }
                }.padding(28)
            }
            .onChange(of: showingHIMSAExport) { _, visible in
                if visible {
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("himsa-export-options", anchor: .bottom) }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.teal)
        .confirmationDialog("Discard unsaved changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { performPendingAction() }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: { Text("Your last saved exam will remain unchanged.") }
        .confirmationDialog("Delete this saved exam?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete exam", role: .destructive) { store.deleteExam() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes the exam from this Mac. Exported copies and sound presets are kept.") }
        .confirmationDialog("Clear all entered thresholds?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear thresholds", role: .destructive) { store.clearThresholds() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This clears both ears, air and bone conduction, including masked entries. Save to update the stored exam.") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): store.importExam(from: url)
            case .failure(let error): store.reportImportError(error)
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: exportType,
                      defaultFilename: "audiogram") { store.reportExport($0) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Audiogram", systemImage: "chart.xyaxis.line").font(.title.weight(.semibold))
                Text("Copy the values from your exam. Leave untested frequencies blank.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("New exam") { request(.new) }
                if !store.library.exams.isEmpty {
                    Divider()
                    ForEach(store.library.exams) { exam in
                        Button {
                            if exam.id != store.draft.id { request(.select(exam.id)) }
                        } label: {
                            Text("\(exam.name)\(exam.examDate.map { " · \($0)" } ?? "")")
                        }
                    }
                }
            } label: { Label("Exams", systemImage: "folder") }
            Button("Save exam") {
                if let exam = store.save() { onSaved?(exam) }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(store.loadFailed || store.validationError != nil)
            .accessibilityIdentifier("audiogram-save")
        }
    }

    private var metadata: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Exam name").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                TextField("Exam name", text: $store.draft.name).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("audiogram-name")
            }.frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                Text("Exam date · optional").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                TextField("YYYY-MM-DD", text: $store.draft.examDate).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("audiogram-date")
            }.frame(width: 170)
            VStack(alignment: .trailing, spacing: 6) {
                Text("Storage").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Label("This Mac only", systemImage: "lock").font(.callout).padding(.top, 3)
            }
        }
    }

    private var graphPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hearing level · dB HL").font(.callout.weight(.medium))
                Spacer()
                Text("\(store.plottedThresholds.count) entries").font(.caption).foregroundStyle(.secondary)
            }
            AudiogramPlot(thresholds: store.plottedThresholds).frame(height: 475)
            HStack(spacing: 16) {
                Label("Right", systemImage: "circle").foregroundStyle(.red)
                Label("Left", systemImage: "xmark").foregroundStyle(.blue)
                Text("↓ NR").foregroundStyle(.secondary)
            }.font(.caption)
            Text("Air: ○ / ×; masked: △ / □. Bone: < / >; masked: [ / ]. NR marks the presentation level when no response was recorded.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if store.plottedThresholds.isEmpty {
                Text("No exam values entered yet.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private var entryPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            Picker("Measurement", selection: $conduction) {
                ForEach(AudiogramConduction.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            Toggle("Masked measurements", isOn: $masked).toggleStyle(.checkbox)
                .font(.callout)
            Text("Each condition is stored separately. NR = no response at the entered level.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 15, verticalSpacing: 10) {
                GridRow {
                    Text("Hz").frame(width: 42, alignment: .trailing)
                    Text("Right · dB HL").foregroundStyle(.red)
                    Text("Left · dB HL").foregroundStyle(.blue)
                }.font(.caption.weight(.semibold))
                Divider().gridCellColumns(3)
                ForEach(Audiogram.frequenciesHz, id: \.self) { frequency in
                    GridRow {
                        Text("\(frequency)").font(.callout.monospacedDigit()).frame(width: 42, alignment: .trailing)
                        thresholdCell(.right, frequency: frequency)
                        thresholdCell(.left, frequency: frequency)
                    }
                }
            }
            Text("Accepted range: −20 to 130 dB HL. Enter the values printed on your exam.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Clear thresholds…", role: .destructive) { confirmClear = true }
                .font(.caption).disabled(store.draft.cells.isEmpty)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private func thresholdCell(_ ear: AudiogramEar, frequency: Int) -> some View {
        let key = AudiogramThresholdKey(ear: ear, conduction: conduction, frequencyHz: frequency, masked: masked)
        let text = store.text(for: key)
        let invalid = !text.isEmpty && (try? Audiogram.parseLevel(text, for: key)) == nil
        return HStack(spacing: 5) {
            TextField("—", text: Binding(get: { store.text(for: key) }, set: { store.setText($0, for: key) }))
                .textFieldStyle(.roundedBorder).frame(width: 60)
                .multilineTextAlignment(.trailing).font(.callout.monospacedDigit())
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(invalid ? Color.orange : Color.clear))
                .accessibilityLabel("\(key.label), dB HL")
                .accessibilityIdentifier("audiogram-\(ear.rawValue)-\(conduction.rawValue)-\(frequency)-\(masked ? "masked" : "unmasked")")
            Toggle("NR", isOn: Binding(get: { store.noResponse(for: key) }, set: { store.setNoResponse($0, for: key) }))
                .toggleStyle(.checkbox).font(.caption)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("\(key.label), no response")
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Exam notes").font(.callout.weight(.medium))
            TextEditor(text: $store.draft.notes)
                .font(.body).scrollContentBackground(.hidden).padding(6)
                .frame(height: 75)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                .accessibilityLabel("Exam notes")
            Text("Save keeps this exam on this Mac and makes it available as a reference for your sound presets.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = store.error ?? store.validationError {
                Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange)
            } else if !store.status.isEmpty {
                Label(store.status, systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary)
            } else if store.isDirty {
                Text("Unsaved changes").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Import JSON…") { request(.importFile) }
                Button("Export JSON…") {
                    if let data = store.prepareExport() {
                        exportDocument = AudiogramExportDocument(data: data)
                        exportType = .json
                        exporting = true
                    }
                }.disabled(store.validationError != nil)
                Button("Export HIMSA XML…") { showingHIMSAExport = true }
                    .disabled(store.validationError != nil || store.plottedThresholds.isEmpty)
                Spacer()
                Button("Revert changes") { request(.revert) }.disabled(!store.isDirty)
                Button("Delete saved exam…", role: .destructive) { confirmDelete = true }
                    .disabled(!store.isSaved || store.loadFailed)
            }
        }
    }

    private var himsaExportOptions: some View {
        let hasAir = store.plottedThresholds.contains { $0.key.conduction == .air }
        let hasMasked = store.plottedThresholds.contains { $0.key.masked }
        return VStack(alignment: .leading, spacing: 18) {
            Text("Export HIMSA audiogram").font(.title2.weight(.semibold))
            Text("Choose the measurement method recorded in your exam. Unknown details stay unknown.")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Test signal", selection: $himsaSignal) {
                ForEach(HIMSAAudiogramExport.Signal.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            if hasAir {
                Picker("Air-conduction transducer", selection: $himsaTransducer) {
                    Text("Choose from exam").tag(nil as HIMSAAudiogramExport.AirTransducer?)
                    ForEach(HIMSAAudiogramExport.AirTransducer.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                }
            }
            if hasMasked {
                Label("HIMSA export needs actual masking levels, which are not stored yet. JSON keeps all masked measurements.",
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("Exports entered measurements as Audiogram 502 XML. Exam name, date and notes stay in the JSON record. Import into Noah depends on a compatible audiometry module.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Close export options") { showingHIMSAExport = false }
                Spacer()
                Button("Export XML…") {
                    if let data = store.prepareHIMSAExport(signal: himsaSignal, airTransducer: himsaTransducer) {
                        exportDocument = AudiogramExportDocument(data: data)
                        exportType = .xml
                        showingHIMSAExport = false
                        exporting = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(hasMasked || (hasAir && himsaTransducer == nil))
            }
        }.padding(20).frame(maxWidth: 700, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("himsa-export-options")
    }

    private func request(_ action: PendingAction) {
        pendingAction = action
        if store.isDirty { confirmDiscard = true } else { performPendingAction() }
    }

    private func performPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .new: store.newExam()
        case .select(let id): store.select(id)
        case .importFile: importing = true
        case .revert: store.revert()
        }
    }
}

private struct AudiogramExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .xml] }
    var data = Data()
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct AudiogramPlot: View {
    let thresholds: [AudiogramThreshold]

    var body: some View {
        Canvas { context, size in
            // ASHA specifies one octave across equals 20 dB down. Six octaves / 150 dB gives 1.25 height/width.
            let width = min(max(0, size.width - 52), max(0, (size.height - 40) / 1.25))
            let plot = CGRect(x: (size.width - width) / 2 + 12, y: 12, width: width, height: width * 1.25)
            guard width > 0 else { return }
            let grid = Color.primary.opacity(0.12)
            for level in stride(from: -20, through: 130, by: 10) {
                let y = plot.minY + Double(level + 20) / 150 * plot.height
                var path = Path(); path.move(to: CGPoint(x: plot.minX, y: y)); path.addLine(to: CGPoint(x: plot.maxX, y: y))
                context.stroke(path, with: .color(level == 0 ? Color.primary.opacity(0.35) : grid), lineWidth: level == 0 ? 1.3 : 0.7)
                context.draw(Text("\(level)").font(.system(size: 9)).foregroundStyle(.secondary),
                             at: CGPoint(x: plot.minX - 7, y: y), anchor: .trailing)
            }
            for frequency in Audiogram.frequenciesHz {
                let x = plot.minX + (Audiogram.chartPosition(frequencyHz: frequency, levelDBHL: 0)?.x ?? 0) * plot.width
                let interoctave = frequency == 3000 || frequency == 6000
                var path = Path(); path.move(to: CGPoint(x: x, y: plot.minY)); path.addLine(to: CGPoint(x: x, y: plot.maxY))
                context.stroke(path, with: .color(grid), style: StrokeStyle(lineWidth: 0.7, dash: interoctave ? [2, 3] : []))
                let label = frequency >= 1000 ? "\(frequency / 1000)k" : "\(frequency)"
                context.draw(Text(label).font(.system(size: 9)).foregroundStyle(.secondary),
                             at: CGPoint(x: x, y: plot.maxY + (interoctave ? 20 : 10)))
            }
            context.draw(Text("Frequency · Hz").font(.system(size: 10)).foregroundStyle(.secondary),
                         at: CGPoint(x: plot.midX, y: plot.maxY + 34))
            for threshold in thresholds.sorted(by: { $0.key.masked && !$1.key.masked }) {
                guard let normalized = Audiogram.chartPosition(frequencyHz: threshold.key.frequencyHz, levelDBHL: threshold.levelDBHL) else { continue }
                let center = CGPoint(x: plot.minX + normalized.x * plot.width, y: plot.minY + normalized.y * plot.height)
                let color: Color = threshold.key.ear == .right ? .red : .blue
                let radius: CGFloat = 4.3
                let symbol = symbolPath(threshold.key, at: center, radius: radius)
                context.stroke(symbol, with: .color(color), lineWidth: 1.65)
                if threshold.noResponse {
                    var arrow = Path()
                    let start = CGPoint(x: center.x + radius + 2, y: center.y + 1)
                    let end = CGPoint(x: start.x, y: start.y + 12)
                    arrow.move(to: start); arrow.addLine(to: end)
                    arrow.move(to: CGPoint(x: end.x - 3, y: end.y - 4)); arrow.addLine(to: end)
                    arrow.addLine(to: CGPoint(x: end.x + 3, y: end.y - 4))
                    context.stroke(arrow, with: .color(color), lineWidth: 1.3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audiogram, frequency 125 to 8000 hertz, hearing level minus 20 to 130 decibels HL, with \(thresholds.count) entered measurements. Values are available in the entry table.")
    }

    private func symbolPath(_ key: AudiogramThresholdKey, at point: CGPoint, radius r: CGFloat) -> Path {
        var path = Path()
        if key.conduction == .bone {
            let direction: CGFloat = key.ear == .right ? -1 : 1
            if key.masked {
                let edge = point.x + direction * r
                path.move(to: CGPoint(x: point.x - direction * r, y: point.y - r))
                path.addLine(to: CGPoint(x: edge, y: point.y - r))
                path.addLine(to: CGPoint(x: edge, y: point.y + r))
                path.addLine(to: CGPoint(x: point.x - direction * r, y: point.y + r))
            } else {
                path.move(to: CGPoint(x: point.x - direction * r, y: point.y - r))
                path.addLine(to: CGPoint(x: point.x + direction * r, y: point.y))
                path.addLine(to: CGPoint(x: point.x - direction * r, y: point.y + r))
            }
        } else if key.masked {
            if key.ear == .right {
                path.move(to: CGPoint(x: point.x, y: point.y - r - 1))
                path.addLine(to: CGPoint(x: point.x + r + 1, y: point.y + r))
                path.addLine(to: CGPoint(x: point.x - r - 1, y: point.y + r)); path.closeSubpath()
            } else {
                path.addRect(CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
            }
        } else if key.ear == .right {
            path.addEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
        } else {
            path.move(to: CGPoint(x: point.x - r, y: point.y - r)); path.addLine(to: CGPoint(x: point.x + r, y: point.y + r))
            path.move(to: CGPoint(x: point.x + r, y: point.y - r)); path.addLine(to: CGPoint(x: point.x - r, y: point.y + r))
        }
        return path
    }
}
