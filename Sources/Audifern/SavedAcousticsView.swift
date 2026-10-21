import CompanionCore
import SwiftUI

struct SavedAcousticsView: View {
    let labels: OticonSavedAcoustics.Labels

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                Label(L("Saved acoustics"), systemImage: "ear").font(AppType.headline)
                LabeledContent(L("Earpiece"), value: label(labels.earpiece))
                LabeledContent(L("Vent"), value: label(labels.vent))
                LabeledContent(L("Acoustic fitting level"), value: label(labels.fittingLevel))
                Text(L(OticonSavedAcoustics.limits)).font(AppType.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ExpandableSection(L("Hook, tubing and recorded codes")) {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent(L("Hook"), value: label(labels.hook))
                        LabeledContent(L("Tubing"), value: label(labels.tubing))
                        LabeledContent(L("Recorded fitting side"), value: label(labels.fittedSide))
                        ForEach(Array(values.enumerated()), id: \.offset) { _, item in
                            HStack {
                                Text(item.0)
                                Spacer()
                                Text("\(item.1.rawCode) · \(item.1.identifier ?? "?")")
                                    .font(AppType.caption.monospaced()).textSelection(.enabled)
                            }
                        }
                    }.font(AppType.caption).padding(.top, 12)
                }.font(AppType.callout)
            }.font(AppType.callout)
        }.accessibilityIdentifier("saved-acoustics")
    }

    private var values: [(String, OticonSavedAcoustics.Value)] {
        [(L("Earpiece"), labels.earpiece), (L("Vent"), labels.vent), (L("Hook"), labels.hook),
         (L("Tubing"), labels.tubing), (L("Acoustic fitting level"), labels.fittingLevel),
         (L("Recorded fitting side"), labels.fittedSide)]
    }
    private func label(_ value: OticonSavedAcoustics.Value) -> String {
        value.label.map { L($0) } ?? L("Unknown code %d", Int(value.rawCode))
    }
}
