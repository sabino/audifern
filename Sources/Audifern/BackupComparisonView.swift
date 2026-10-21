import CompanionCore
import SwiftUI

struct BackupComparisonView: View {
    @ObservedObject var backups: DeviceBackupStore
    @State private var firstSelection: UUID?
    @State private var secondSelection: UUID?
    @State private var consumerExpanded: Set<ConsumerProgramSnapshot.Side> = []
    @State private var scopesExpanded: Set<ConsumerProgramSnapshot.Side> = []

    private var first: DeviceBackupStore.Entry? {
        backups.entries.first { $0.id == firstSelection } ?? backups.entries.dropFirst().first ?? backups.entries.first
    }
    private var second: DeviceBackupStore.Entry? {
        backups.entries.first { $0.id == secondSelection } ?? backups.entries.first
    }
    private var comparison: DeviceBackupComparison? {
        guard let first, let second, first.id != second.id else { return nil }
        return try? DeviceBackupComparison(first: first.backup, second: second.backup)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if backups.entries.count < 2 {
                Text(L("Save at least two backups to compare the state they captured."))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 20) {
                    selection(L("First backup"), selected: first, binding: $firstSelection)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary).accessibilityHidden(true)
                    selection(L("Second backup"), selected: second, binding: $secondSelection)
                }
                if let comparison {
                    ForEach(comparison.aids, id: \.side) { aid in aidComparison(aid) }
                    Text(L("Unchanged means the captured data matches. It does not establish identical sound, a complete fitting or a safe restore. No settings are sent to the hearing aids."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else if first?.id == second?.id {
                    Text(L("Choose two different backups.")).font(.callout).foregroundStyle(.secondary)
                } else {
                    Text(L("These captures could not be compared. Their original files remain unchanged."))
                        .font(.callout).foregroundStyle(.orange)
                }
            }
        }.accessibilityIdentifier("backup-comparison")
    }

    private func selection(_ title: String, selected: DeviceBackupStore.Entry?, binding: Binding<UUID?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Picker(title, selection: Binding(get: { selected?.id }, set: { binding.wrappedValue = $0 })) {
                ForEach(Array(backups.entries.enumerated()), id: \.element.id) { index, entry in
                    Text(L("Backup %d", backups.entries.count - index) + " · " +
                         entry.backup.capturedAt.formatted(.dateTime.month().day().hour().minute().second()))
                        .tag(Optional(entry.id))
                }
            }.labelsHidden()
            if let selected {
                Text(selected.backup.capturedAt, format: .dateTime.day().month(.wide).year().hour().minute().second())
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func aidComparison(_ aid: DeviceBackupComparison.Aid) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L(aid.side.rawValue.capitalized), systemImage: "ear").font(.headline)
                Spacer()
                if aid.isComparable {
                    Label(L("Matching saved identity"), systemImage: "checkmark.shield")
                        .font(.caption).foregroundStyle(Brand.accent)
                }
            }
            if !aid.isComparable {
                Text(aid.identity == .missingEar
                     ? L("This ear was not captured in both backups.")
                     : L("These captures do not identify the same hearing aid. Setting comparisons are unavailable."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                row(L("Fitting-system record"), aid.fittingRecord ?? .notCaptured)
                ForEach(DeviceBackupComparison.Section.allCases, id: \.self) { section in
                    if let value = aid.sections[section] { row(sectionTitle(section), value) }
                }
                if aid.sections.isEmpty {
                    Text(L("Section details need two captured records with a matching supported fitting profile."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup(L("Consumer control comparison"), isExpanded: expansion(aid.side, values: $consumerExpanded)) {
                    VStack(spacing: 10) {
                        ForEach(DeviceBackupComparison.ConsumerField.allCases, id: \.self) { field in
                            row(consumerTitle(field), aid.consumer[field] ?? .notCaptured)
                        }
                    }.padding(.top, 10)
                }.font(.callout)
                DisclosureGroup(L("Persisted setting comparison"), isExpanded: expansion(aid.side, values: $scopesExpanded)) {
                    VStack(alignment: .leading, spacing: 10) {
                        row(L("Scope inventory"), aid.scopeInventory ?? .notCaptured)
                        row(L("Scope metadata"), aid.scopeMetadata ?? .notCaptured)
                        if aid.scopes.isEmpty {
                            Text(L("No persisted scope values were captured in either backup.")).foregroundStyle(.secondary)
                        } else {
                            ForEach(aid.scopes, id: \.selfID) { scope in
                                row(L("Scope %d · item %d", Int(scope.scope), Int(scope.id)), scope.difference)
                            }
                        }
                    }.font(.caption).padding(.top, 10)
                }.font(.callout)
            }
        }.padding(18).background(Brand.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    private func expansion(_ side: ConsumerProgramSnapshot.Side, values: Binding<Set<ConsumerProgramSnapshot.Side>>) -> Binding<Bool> {
        Binding(get: { values.wrappedValue.contains(side) }, set: { expanded in
            if expanded { values.wrappedValue.insert(side) } else { values.wrappedValue.remove(side) }
        })
    }

    private func row(_ title: String, _ difference: DeviceBackupComparison.Difference) -> some View {
        HStack(spacing: 14) {
            Text(title).font(.callout)
            Spacer(minLength: 8)
            Label(differenceTitle(difference), systemImage: difference == .identical ? "equal.circle" : difference == .changed ? "circle.lefthalf.filled" : "minus.circle")
                .font(.caption.weight(.medium)).foregroundStyle(difference == .identical ? Brand.accent : difference == .changed ? .orange : .secondary)
        }
    }
    private func differenceTitle(_ difference: DeviceBackupComparison.Difference) -> String {
        switch difference {
        case .notCaptured: L("Not captured")
        case .firstOnly: L("First only")
        case .secondOnly: L("Second only")
        case .identical: L("Unchanged")
        case .changed: L("Changed")
        }
    }
    private func sectionTitle(_ section: DeviceBackupComparison.Section) -> String {
        switch section {
        case .acoustics: L("Acoustic selection bytes")
        case .fittedParameters: L("Fitted parameter bytes")
        case .fittingMetadata: L("Fitting metadata bytes")
        }
    }
    private func consumerTitle(_ field: DeviceBackupComparison.ConsumerField) -> String {
        switch field {
        case .program: L("Active program metadata")
        case .mainVolume: L("Main volume, mute and limits")
        case .streamingVolume: L("Streaming volume, mute and limits")
        case .tinnitusVolume: L("Tinnitus volume, mute and limits")
        case .microphoneEQ: L("Microphone EQ and limits")
        case .streamingEQ: L("Streaming EQ and limits")
        case .speechBooster: L("SpeechBooster")
        }
    }
}

private extension DeviceBackupComparison.Scope {
    var selfID: Int { (Int(scope) << 8) | Int(id) }
}
