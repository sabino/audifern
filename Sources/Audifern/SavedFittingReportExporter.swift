import AppKit
import CompanionCore
import CoreText
import PDFKit
import UniformTypeIdentifiers
import SwiftUI

/// The preview and printable document consume this same localized projection.
/// No archive or BluetoothStore is retained by the presentation/export layer.
struct SavedFittingReportPresentation {
    struct Row { let title: String; let value: String }
    struct Section { let title: String; let rows: [Row]; var note: String? = nil }
    struct Page { let title: String; let sections: [Section] }
    let title: String
    let subtitle: String
    let date: String
    let capture: String
    let privacy: String
    let pages: [Page]

    init(report: SavedFittingReport, localization text: Localization) {
        func L(_ key: String, arguments: [CVarArg] = []) -> String {
            text.string(key, arguments: arguments)
        }
        title = L("Saved fitting summary")
        subtitle = L("Archived settings only. This is not a complete clinical report, a measured response or a restorable fitting.")
        let formatter = DateFormatter()
        formatter.locale = text.formattingLocale
        formatter.dateStyle = .long; formatter.timeStyle = .short
        date = L("Captured %@", arguments: [formatter.string(from: report.capturedAt)])
        switch report.capture {
        case .completed: capture = L("Read completed · captured scopes only")
        case .partial: capture = L("Partial capture · post-read state not verified")
        case .consumerCheckpoint: capture = L("Consumer checkpoint · saved before fitting reads")
        case .unspecified: capture = L("Capture completion not recorded")
        }
        privacy = L("Identifiers, custom names, audiograms, real-ear data, gain/MPO values and raw records are excluded. Saved settings may have changed since this capture.")
        func row(_ title: String, _ value: String?) -> Row {
            Row(title: title, value: value ?? L("Not reported"))
        }
        func toggle(_ value: Bool?) -> String {
            value.map { L($0 ? "Enabled" : "Disabled") } ?? L("Not reported")
        }
        pages = report.ears.map { ear in
            let side = L(ear.side == .left ? "Left" : "Right")
            guard ear.isCaptured else {
                return Page(title: side, sections: [Section(title: L("Not captured"), rows: [],
                    note: L("This backup contains no data for this ear. No values have been copied from the other ear or a connected aid."))])
            }
            var sections = [Section(title: L("Hearing aid"), rows: [
                row(L("Model"), ear.model), row(L("Firmware version"), ear.firmwareVersion),
                row(L("Software version"), ear.softwareVersion)
            ])]
            let fitting: String
            switch ear.fittingStatus {
            case .decoded: fitting = L("Saved fitting decoded")
            case .notCaptured: fitting = L("Fitting record not captured")
            case .unsupported: fitting = L("Fitting format not supported")
            case .unreadable: fitting = L("Fitting details could not be decoded")
            }
            var coverage = [row(L("Fitting-system record"), fitting)]
            if let eus = ear.endUserCoverage {
                let count = eus.advertisedCount.map {
                    L("%d of %d advertised scopes", arguments: [eus.capturedCount, $0])
                } ?? L("%d scopes captured", arguments: [eus.capturedCount])
                coverage.append(row(L("End-user settings"), count))
                coverage.append(row(L("Scope coverage"), L(eus.advertisedInventoryComplete
                    ? "Advertised inventory captured" : "Partial coverage")))
            } else { coverage.append(row(L("End-user settings"), L("Not captured"))) }
            sections.append(Section(title: L("Capture coverage"), rows: coverage))
            if let adaptation = ear.adaptation {
                let mode: String
                switch adaptation.mode {
                case .manual: mode = L("Manual")
                case .automatic: mode = L("Automatic")
                case .paused: mode = L("Paused")
                }
                let step = adaptation.currentStep.formatted(.number.locale(text.formattingLocale).precision(.fractionLength(0...2)))
                sections.append(Section(title: L("Saved adaptation"), rows: [
                    row(L("Adaptation mode"), mode), row(L("Saved step"), step),
                    row(L("Start and final steps"), L("Start %d · final %d", arguments: [adaptation.startStep, adaptation.endStep]))
                ]))
            }
            if let acoustics = ear.acoustics {
                sections.append(Section(title: L("Saved acoustics"), rows: [
                    row(L("Earpiece"), acoustics.earpiece.map { L($0) } ?? L("Unrecognized saved category")),
                    row(L("Vent"), acoustics.vent.map { L($0) } ?? L("Unrecognized saved category")),
                    row(L("Acoustic fitting level"), acoustics.fittingLevel.map { L($0) } ?? L("Unrecognized saved category"))
                ], note: L("Saved categories do not verify the parts currently fitted or their acoustic compatibility.")))
            }
            if ear.fittingStatus == .decoded {
                let programs = ear.programs.map { program in
                    var values = [
                        L("%@: %@", arguments: [L("Noise management"), toggle(program.noiseManagementEnabled)]),
                        L("%@: %@", arguments: [L("Feedback management"), toggle(program.feedbackManagementEnabled)]),
                        L("%@: %@", arguments: [L("Frequency lowering"), toggle(program.frequencyLoweringEnabled)])
                    ]
                    if let value = program.transientControl {
                        values.append(L("%@: %@", arguments: [L("Transient sounds"), L(value)]))
                    }
                    if let value = program.windControl {
                        values.append(L("%@: %@", arguments: [L("Wind handling"), L(value)]))
                    }
                    return Row(title: L("P%d", arguments: [program.slot + 1]), value: values.joined(separator: "\n"))
                }
                sections.append(Section(title: L("Saved listening programs"), rows: programs,
                    note: L("Only fitted user slots are listed. Custom labels and accessory programs are omitted; this does not identify the active listening program.")))
                if let metadata = ear.metadata {
                    let software = metadata.isPrerelease
                        ? L("%@ (prerelease)", arguments: [metadata.fittingSoftwareVersion]) : metadata.fittingSoftwareVersion
                    var labels: [String] = []
                    for rationale in metadata.rationales {
                        let label = rationale.map { L($0) } ?? L("Unrecognized saved rationale")
                        if !labels.contains(label) { labels.append(label) }
                    }
                    sections.append(Section(title: L("Fitting record details"), rows: [
                        row(L("Fitting software version"), software),
                        row(L("Stored rationales"), labels.isEmpty ? nil : labels.joined(separator: ", "))
                    ], note: L("Stored rationales describe setup positions, not a verified rationale for each listening program.")))
                } else {
                    sections.append(Section(title: L("Fitting record details"), rows: [],
                        note: L("Additional fitting metadata could not be decoded and is omitted from this summary.")))
                }
            }
            return Page(title: side, sections: sections)
        }
    }
}

@MainActor enum SavedFittingReportExporter {
    enum ExportError: Error { case renderingFailed }

    /// Uses Core Text on an in-memory PDF context. No NSWindow, web view,
    /// temporary archive, screen capture or device connection is involved.
    static func pdfData(report: SavedFittingReport, localization: Localization) throws -> Data {
        let content = SavedFittingReportPresentation(report: report, localization: localization)
        let data = CFDataCreateMutable(nil, 0)!
        guard let consumer = CGDataConsumer(data: data) else { throw ExportError.renderingFailed }
        var media = CGRect(x: 0, y: 0, width: 595, height: 842)
        let info = [kCGPDFContextTitle as String: content.title, kCGPDFContextCreator as String: "Audifern"] as CFDictionary
        guard let context = CGContext(consumer: consumer, mediaBox: &media, info) else { throw ExportError.renderingFailed }
        let writer = PDFWriter(context: context, content: content, localization: localization)
        for page in content.pages { writer.append(page) }
        writer.finish()
        context.closePDF()
        let result = data as Data
        guard !result.isEmpty else { throw ExportError.renderingFailed }
        return result
    }

    /// Called only by the explicit Print button. Native print UI lets the user
    /// choose the printer/destination; no report is sent automatically.
    static func printReport(report: SavedFittingReport, localization: Localization) throws -> Bool {
        let data = try pdfData(report: report, localization: localization)
        guard let document = PDFDocument(data: data),
              let operation = document.printOperation(for: NSPrintInfo(dictionary: [:]),
                scalingMode: .pageScaleToFit, autoRotate: true) else { throw ExportError.renderingFailed }
        operation.jobTitle = localization.string("Saved fitting summary")
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        return operation.run()
    }

    @MainActor private final class PDFWriter {
        let context: CGContext
        let content: SavedFittingReportPresentation
        let localization: Localization
        var top: CGFloat = 0
        var pageNumber = 0
        var pageOpen = false
        var earTitle = ""
        let green = NSColor(srgbRed: 0.06, green: 0.36, blue: 0.28, alpha: 1)

        init(context: CGContext, content: SavedFittingReportPresentation, localization: Localization) {
            self.context = context; self.content = content; self.localization = localization
        }

        func append(_ page: SavedFittingReportPresentation.Page) {
            earTitle = page.title
            beginPage()
            for section in page.sections {
                let headingHeight = height(section.title, size: 12, weight: .semibold)
                ensureSpace(headingHeight + 48)
                top += 14
                draw(section.title, size: 12, weight: .semibold, color: green)
                top += 7
                for row in section.rows {
                    let labelHeight = height(row.title, size: 9, weight: .medium, width: 150)
                    let valueHeight = height(row.value, size: 9, width: 350)
                    let rowHeight = max(labelHeight, valueHeight) + 8
                    ensureSpace(rowHeight)
                    draw(row.title, size: 9, weight: .medium, x: 40, width: 150, advance: false)
                    draw(row.value, size: 9, x: 205, width: 350, advance: false)
                    top += rowHeight
                }
                if let note = section.note {
                    let noteHeight = height(note, size: 8)
                    ensureSpace(noteHeight + 8)
                    top += 3
                    draw(note, size: 8, color: .darkGray)
                }
            }
        }

        func beginPage() {
            finishPage()
            context.beginPDFPage(nil)
            pageOpen = true; pageNumber += 1; top = 36
            draw("Audifern", size: 11, weight: .semibold, color: green)
            top += 8
            draw(content.title, size: 22, weight: .bold)
            top += 4
            draw(content.subtitle, size: 9, color: .darkGray)
            top += 9
            draw(content.date, size: 9, weight: .medium)
            draw(content.capture, size: 9, color: .darkGray)
            top += 10
            context.setStrokeColor(green.cgColor)
            context.move(to: CGPoint(x: 40, y: 842 - top))
            context.addLine(to: CGPoint(x: 555, y: 842 - top)); context.strokePath()
            top += 15
            draw(earTitle, size: 17, weight: .bold, color: green)
        }

        func ensureSpace(_ amount: CGFloat) { if top + amount > 739 { beginPage() } }
        func finish() { finishPage() }
        func finishPage() {
            guard pageOpen else { return }
            top = 765
            draw(content.privacy, size: 8, color: .darkGray)
            top = 811
            draw(localization.string("Page %d", arguments: [pageNumber]), size: 8, color: .darkGray)
            context.endPDFPage(); pageOpen = false
        }

        func attributed(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular,
                        color: NSColor = .black) -> NSAttributedString {
            let style = NSMutableParagraphStyle(); style.lineSpacing = 2
            return NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color, .paragraphStyle: style])
        }
        func height(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular, width: CGFloat = 515) -> CGFloat {
            let setter = CTFramesetterCreateWithAttributedString(attributed(value, size: size, weight: weight) as CFAttributedString)
            let measured = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
                CGSize(width: width, height: .greatestFiniteMagnitude), nil)
            return ceil(measured.height) + 3
        }
        func draw(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular,
                  color: NSColor = .black, x: CGFloat = 40, width: CGFloat = 515, advance: Bool = true) {
            let string = attributed(value, size: size, weight: weight, color: color)
            let measured = height(value, size: size, weight: weight, width: width)
            let setter = CTFramesetterCreateWithAttributedString(string as CFAttributedString)
            let path = CGPath(rect: CGRect(x: x, y: 842 - top - measured, width: width, height: measured), transform: nil)
            context.textMatrix = .identity
            CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil), context)
            if advance { top += measured }
        }
    }
}

struct SavedFittingPDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { exportFileWrapper() }
    func exportFileWrapper() -> FileWrapper {
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.fileAttributes[FileAttributeKey.posixPermissions.rawValue] = 0o600
        return wrapper
    }
}
