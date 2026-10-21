import CompanionCore
import SwiftUI

struct SavedPreferencesView: View {
    let preferences: OticonSavedPreferences.Snapshot
    @State private var tapsExpanded: Bool
    @State private var indicatorsExpanded: Bool

    init(preferences: OticonSavedPreferences.Snapshot, showDetails: Bool = false) {
        self.preferences = preferences
        _tapsExpanded = State(initialValue: showDetails)
        _indicatorsExpanded = State(initialValue: showDetails)
    }

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                Label(L("Saved buttons and notifications"), systemImage: "hand.tap").font(.headline)
                Text(L(OticonSavedPreferences.limits)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup(L("Tap actions by listening context"), isExpanded: $tapsExpanded) {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                        GridRow {
                            Text(L("Context")).foregroundStyle(.secondary)
                            Text(L("Single tap")).foregroundStyle(.secondary)
                            Text(L("Double tap")).foregroundStyle(.secondary)
                        }.font(.caption.weight(.medium))
                        ForEach(OticonSavedPreferences.UseCase.allCases, id: \.self) { context in
                            GridRow {
                                Text(L(context.label)).font(.callout.weight(.medium))
                                Text(tap(.singleTap, context: context))
                                Text(tap(.doubleTap, context: context))
                            }
                        }
                    }.font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
                }
                DisclosureGroup(L("Hearing-aid notification sounds"), isExpanded: $indicatorsExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(preferences.audibleIndicators, id: \.event) { indicator in
                            valueRow(L(indicator.event.label), value: choice(indicator.mode))
                        }
                        Divider()
                        ForEach(preferences.indicatorSettings, id: \.kind) { setting in
                            valueRow(L(setting.kind.label), value: choice(setting.value))
                        }
                        Text(L("Low, medium and high are saved categories. No notification or test tone is played when you inspect them."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
                }
            }.font(.callout)
        }.accessibilityIdentifier("saved-preferences")
    }

    private func tap(_ gesture: OticonSavedPreferences.Gesture, context: OticonSavedPreferences.UseCase) -> String {
        preferences.taps.first { $0.gesture == gesture && $0.context == context }.map { choice($0.action) } ?? L("Not captured")
    }
    private func choice(_ value: OticonSavedPreferences.Choice) -> String {
        value.label.map { L($0) } ?? L("Unknown code %@", String(value.rawCode))
    }
    private func valueRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(label)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }
}
