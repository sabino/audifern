import CompanionCore
import SwiftUI

/// A projection of a verified private archive. This view never talks to an aid.
struct StoredFittingMetadataView: View {
    let snapshot: OticonBusinessData.Snapshot
    let backup: DeviceBackup
    let audiograms: AudiogramEditorStore?
    @EnvironmentObject private var navigation: AppNavigation
    @State private var showAudiogram = false
    @State private var showImport = false
    @State private var unitsConfirmed = false
    @State private var discardConfirmed = false
    @State private var importError = false

    init(snapshot: OticonBusinessData.Snapshot, backup: DeviceBackup,
         audiograms: AudiogramEditorStore? = nil, showAudiogram: Bool = false) {
        self.snapshot = snapshot; self.backup = backup; self.audiograms = audiograms
        _showAudiogram = State(initialValue: showAudiogram)
    }

    private var rationaleLabels: [String] {
        var labels: [String] = []
        for rationale in snapshot.rationales {
            let label = rationale.label.map { L($0) } ?? L("Unknown code %d", Int(rationale.code))
            if !labels.contains(label) { labels.append(label) }
        }
        return labels
    }
    private var storedValueCount: Int {
        [snapshot.airConduction, snapshot.boneConduction, snapshot.uncomfortableLevel]
            .reduce(0) { $0 + $1.points.filter { $0.level != nil }.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    Label(L("Fitting record details"), systemImage: "doc.text.magnifyingglass").font(.headline)
                    LabeledContent(L("Fitting software version"), value: softwareVersion)
                    LabeledContent(L("Stored rationales"), value: rationaleLabels.isEmpty ? L("Not reported") : rationaleLabels.joined(separator: ", "))
                    LabeledContent(L("Acoustics checked in saved fitting"), value: snapshot.acousticsVerified ? L("Yes") : L("No"))
                    Text(L("The fitting software version describes the software that saved this record. It is separate from the hearing aid’s firmware and software versions. Rationale entries include stored setup positions, not just your listening programs."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.font(.callout)
            }
            Surface {
                DisclosureGroup(isExpanded: $showAudiogram) {
                    VStack(alignment: .leading, spacing: 18) {
                        Label(L("Measurement units are not stored"), systemImage: "info.circle")
                            .font(.callout.weight(.medium)).foregroundStyle(.orange)
                        Text(L("These are saved fitting values, not the original exam. They may have been rounded or interpolated, and may include uncorrected ABR/nHL levels. Audifern does not label them dB HL or use them to calculate a fitting. The original exam date is unknown."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        curvesTable([
                            (L("Air conduction"), snapshot.airConduction),
                            (L("Bone conduction"), snapshot.boneConduction),
                            (L("Uncomfortable level"), snapshot.uncomfortableLevel)
                        ])
                        if audiograms != nil { importControls }
                    }.padding(.top, 16)
                } label: {
                    HStack {
                        Label(L("Saved audiogram"), systemImage: "chart.xyaxis.line").font(.headline)
                        Spacer()
                        Text(L("%d stored values", storedValueCount)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            additionalMetadata
        }
        .onChange(of: backup.id) { _, _ in resetConfirmation() }
        .onChange(of: audiograms?.isDirty) { _, _ in discardConfirmed = false }
    }

    private var softwareVersion: String {
        let version = snapshot.softwareVersion
        let number = "\(version.major).\(version.minor).\(version.patch)"
        return version.isPrerelease ? L("%@ (prerelease)", number) : number
    }

    private var importControls: some View {
        DisclosureGroup(isExpanded: $showImport) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Copy ordinary air and bone response points from both saved ears into a new local draft. No-response, uncertain, uncomfortable-level and in-situ points stay in the backup. Review and save the draft separately; this never changes the aids."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle(L("I have checked the source exam and these stored levels are dB HL"), isOn: $unitsConfirmed)
                    .toggleStyle(.checkbox).font(.callout)
                if audiograms?.isDirty == true {
                    Toggle(L("Replace the unsaved audiogram draft; keep saved exams unchanged"), isOn: $discardConfirmed)
                        .toggleStyle(.checkbox).font(.callout).foregroundStyle(.orange)
                }
                Button(L("Copy to audiogram editor"), action: copyForReview)
                    .buttonStyle(.bordered)
                    .disabled(!unitsConfirmed || (audiograms?.isDirty == true && !discardConfirmed))
                if importError {
                    Text(L("No supported response points could be copied. The backup and saved exams remain unchanged."))
                        .font(.caption).foregroundStyle(.orange)
                }
            }.padding(.top, 12)
        } label: { Text(L("Review as a local audiogram…")).font(.callout.weight(.medium)) }
            .onChange(of: showImport) { _, _ in resetConfirmation() }
    }

    private var additionalMetadata: some View {
        Surface {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("The raw fitting archive also preserves these values. They do not start a measurement, apply a correction or change adaptation."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let adaptation = snapshot.adaptation {
                        LabeledContent(L("Saved adaptation steps"), value: "\(adaptation.startStep) → \(adaptation.endStep)")
                        LabeledContent(L("Time per step · raw value"), value: String(adaptation.timePerStep))
                    }
                    LabeledContent(L("In-situ audiogram"), value: snapshot.inSitu.map { $0.isUsed ? L("Stored · used in fitting") : L("Stored · not in use") } ?? L("Not stored"))
                    if let inSitu = snapshot.inSitu {
                        curvesTable([(L("In-situ · units unconfirmed"), inSitu.audiogram)])
                    }
                    if let flag = snapshot.hasSSD { LabeledContent(L("Single-sided fitting flag"), value: flag ? L("Yes") : L("No")) }
                    if let flag = snapshot.isBoneConductionExcluded {
                        LabeledContent(L("Bone conduction excluded"), value: flag ? L("Yes") : L("No"))
                    }
                    if let act = snapshot.audibleContrastThreshold {
                        LabeledContent(L("ACT · stored value"), value: (Double(act.valueTenths) / 10).formatted(.number.precision(.fractionLength(1))))
                    }
                    DisclosureGroup(L("Real-ear and correction vectors")) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("Raw stored vectors; no acoustic conversion or calibration is applied."))
                                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            vector("RECD", values: snapshot.realEar.measuredRECD)
                            vector("REUG", values: snapshot.realEar.measuredREUG)
                            if let correction = snapshot.autoFitCorrection {
                                vector(L("Auto-fit correction"), values: correction.values)
                            }
                        }.font(.caption).padding(.top, 10)
                    }
                    if snapshot.hasOpaqueTail {
                        Text(L("Additional unrecognized metadata is preserved in the raw backup."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.font(.callout).padding(.top, 16)
            } label: { Label(L("Additional fitting metadata"), systemImage: "slider.horizontal.3").font(.headline) }
        }
    }

    private func curvesTable(_ curves: [(String, OticonBusinessData.Curve)]) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Text("Hz").frame(width: 50, alignment: .trailing)
                    ForEach(curves.indices, id: \.self) { index in
                        Text(curves[index].0).frame(width: 150, alignment: .leading)
                    }
                }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(OticonBusinessData.frequencies.indices, id: \.self) { index in
                    GridRow(alignment: .top) {
                        Text(String(OticonBusinessData.frequencies[index])).font(.callout.monospacedDigit())
                            .frame(width: 50, alignment: .trailing)
                        ForEach(curves.indices, id: \.self) { curve in
                            let point = curves[curve].1.points[index]
                            VStack(alignment: .leading, spacing: 3) {
                                Text(point.level.map(String.init) ?? "—").font(.callout.monospacedDigit())
                                Text(tagLabel(point)).font(.caption2).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.frame(width: 150, alignment: .leading)
                        }
                    }
                    if index != OticonBusinessData.frequencies.count - 1 { Divider().gridCellColumns(curves.count + 1) }
                }
            }.padding(.vertical, 4)
        }.accessibilityIdentifier("stored-audiogram-table")
    }

    private func tagLabel(_ point: OticonBusinessData.Point) -> String {
        switch point.tag {
        case .unmasked: L("Unmasked response")
        case .unmaskedNoResponse: L("Unmasked · no response")
        case .unmaskedUnmeasurable: L("Unmasked · unmeasurable")
        case .masked: L("Masked response")
        case .maskedNoResponse: L("Masked · no response")
        case .maskedUnmeasurable: L("Masked · unmeasurable")
        case .unknown: L("Unknown response status")
        case .noStatus: L("No response status stored")
        case .alwaysResponse: L("Always-response tag")
        case .couldNotTest: L("Could not test")
        case .didNotTest: L("Did not test")
        case nil: point.tagCode == -128 ? L("Not stored") : L("Unknown tag %d", Int(point.tagCode))
        }
    }

    private func vector(_ title: String, values: [Int8]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).fontWeight(.medium)
            Text(values.map(String.init).joined(separator: "  ")).font(.caption.monospaced())
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func resetConfirmation() { unitsConfirmed = false; discardConfirmed = false; importError = false }

    private func copyForReview() {
        guard unitsConfirmed, let audiograms, !audiograms.isDirty || discardConfirmed else { return }
        let points = backup.aids.flatMap { aid -> [AudiogramThreshold] in
            guard let data = try? SavedFitting.businessData(aid) else { return [] }
            return (try? OticonBusinessData.thresholdsForReview(data,
                ear: aid.side == .left ? .left : .right, confirmedDBHL: unitsConfirmed)) ?? []
        }
        guard !points.isEmpty else { importError = true; return }
        let notes = L("Copied from a saved fitting backup after confirming dB HL units against the source exam. Values may be rounded or interpolated. Original exam date unknown. Only ordinary air/bone response points were copied; other metadata remains in the backup.")
        let exam = Audiogram(name: L("Saved fitting audiogram"), notes: notes, thresholds: points)
        if audiograms.reviewImportedExam(exam) { navigation.page = .audiogram }
        else { importError = true }
    }
}
