import CompanionCore
import SwiftUI

/// An inline, immutable preview. It owns no Bluetooth store or live controls.
struct SavedFittingReportView: View {
    let report: SavedFittingReport
    let close: () -> Void
    @EnvironmentObject private var preferences: AppPreferences
    @State private var exporting = false
    @State private var document = SavedFittingPDFDocument(data: Data())
    @State private var status: String?

    private var localization: Localization { Localization(language: preferences.language) }
    private var content: SavedFittingReportPresentation {
        SavedFittingReportPresentation(report: report, localization: localization)
    }

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(content.title, systemImage: "doc.richtext").font(.title2.weight(.semibold))
                        Text(content.date).font(AppType.callout).foregroundStyle(.secondary)
                        Text(content.capture).font(AppType.caption.weight(.medium)).foregroundStyle(Brand.accent)
                    }
                    Spacer(minLength: 0)
                    Button(action: close) { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).accessibilityLabel(L("Close summary preview"))
                }
                Text(content.subtitle).font(AppType.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(action: preparePDF) { Label(L("Save PDF…"), systemImage: "arrow.down.doc") }
                        .buttonStyle(.borderedProminent).tint(Brand.controlTint).font(AppType.body).accessibilityIdentifier("save-fitting-summary-pdf")
                    Button(action: printReport) { Label(L("Print…"), systemImage: "printer") }
                        .buttonStyle(.bordered).font(AppType.body).accessibilityIdentifier("print-fitting-summary")
                }
                Label(content.privacy, systemImage: "hand.raised")
                    .font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let status { Text(status).font(AppType.caption).foregroundStyle(.secondary) }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(Array(content.pages.enumerated()), id: \.offset) { _, page in
                            earCard(page).frame(minWidth: 300)
                        }
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(content.pages.enumerated()), id: \.offset) { _, page in
                            earCard(page)
                        }
                    }
                }
            }
        }.accessibilityIdentifier("saved-fitting-summary-preview")
            .fileExporter(isPresented: $exporting, document: document, contentType: .pdf,
                defaultFilename: "Audifern-saved-fitting-summary") { result in
                switch result {
                case .success: status = L("Summary PDF saved.")
                case .failure: status = L("The summary PDF was not saved.")
                }
            }
    }

    private func earCard(_ page: SavedFittingReportPresentation.Page) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(page.title).font(AppType.subheading.weight(.semibold)).foregroundStyle(Brand.accent)
            ForEach(Array(page.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.title).font(AppType.callout.weight(.semibold))
                    ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title).font(AppType.caption).foregroundStyle(.secondary)
                            Text(row.value).font(AppType.callout).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let note = section.note {
                        Text(note).font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Brand.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 15))
    }

    private func preparePDF() {
        do {
            document = SavedFittingPDFDocument(data: try SavedFittingReportExporter.pdfData(report: report, localization: localization))
            status = nil; exporting = true
        } catch { status = L("The summary could not be prepared. Your backup has not changed.") }
    }
    private func printReport() {
        do {
            let sent = try SavedFittingReportExporter.printReport(report: report, localization: localization)
            status = sent ? L("Summary sent to the print system.") : L("Printing was canceled.")
        } catch { status = L("The summary could not be prepared. Your backup has not changed.") }
    }
}
