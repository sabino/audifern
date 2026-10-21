import CompanionCore
import SwiftUI

struct SavedHardwareView: View {
    let profile: OticonHardwareProfile.Profile

    var body: some View {
        Surface {
            ExpandableSection {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent(L("Instrument style"), value: code(profile.hardware.audiologicalStyle))
                    LabeledContent(L("Receiver connection"), value: code(profile.hardware.hearingInstrumentInterface))
                    LabeledContent(L("Replaceable receiver"), value: replaceableReceiver)
                    LabeledContent(L("Hardware fitting category"), value: code(profile.hardware.fittingLevel))
                    Text(L("Reported hardware categories help identify the device. They do not verify receiver size, physical parts or fitting compatibility."))
                        .font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    LabeledContent(L("HIID format"), value: "\(profile.hiidMajor).\(profile.hiidMinor)")
                    LabeledContent(L("Model identifier"), value: String(profile.product.modelUID))
                    LabeledContent(L("Generic model identifier"), value: String(profile.product.genericModelUID))
                    LabeledContent(L("Hardware configuration"), value:
                        "\(profile.hardwarePlatformConfigurationUID) · v\(profile.hardwarePlatformConfigurationVersion)")
                }.font(AppType.callout).textSelection(.enabled).padding(.top, 14)
            } label: {
                Label(L("Hardware identification"), systemImage: "cpu").font(AppType.headline)
            }
        }.accessibilityIdentifier("saved-hardware-identification")
    }

    private var replaceableReceiver: String {
        switch profile.hardware.removableSpeaker.identifier {
        case "Yes": L("Yes")
        case "No": L("No")
        case "Undefined": L("Not specified")
        default: L("Unknown code %@", String(profile.hardware.removableSpeakerCode))
        }
    }

    private func code(_ value: OticonHardwareProfile.Value) -> String {
        guard let identifier = value.identifier else { return L("Unknown code %@", String(value.rawCode)) }
        if identifier == "Undefined" { return L("Not specified") }
        if identifier == "None" { return L("None") }
        return identifier
    }
}
