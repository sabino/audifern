import CompanionCore
import SwiftUI

/// A same-window revision browser. Restoring here changes only the local plan
/// editor; it has no BluetoothStore or device-control dependency.
struct FittingPlanHistoryView: View {
    @ObservedObject var workspace: FittingWorkspaceStore
    @State private var expanded: Bool
    @State private var selectedID: UUID?
    @State private var confirmingRestore = false

    init(workspace: FittingWorkspaceStore, expanded: Bool = false) {
        self.workspace = workspace
        _expanded = State(initialValue: expanded)
    }

    private var selected: FittingWorkspaceStore.Revision? {
        workspace.revisions.first { $0.id == selectedID } ?? workspace.revisions.first
    }

    var body: some View {
        Surface {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("Review earlier plans and bring one back into the editor. Your current draft is saved in history before it is replaced."))
                        .font(.callout).foregroundStyle(.secondary)
                    if workspace.historyReadFailed {
                        Label(L("Plan history could not be read. Existing files have been preserved."), systemImage: "exclamationmark.circle")
                            .font(.callout).foregroundStyle(.orange)
                    }
                    if workspace.failedRevisionCount > 0 {
                        Label(L("%d revisions could not be verified. Their files have been preserved.", workspace.failedRevisionCount), systemImage: "exclamationmark.shield")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if workspace.revisions.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.badge.clock").font(.title2).foregroundStyle(Brand.accent)
                            Text(L("Your first saved plan starts its history. Revisions stay privately on this Mac."))
                                .font(.callout).foregroundStyle(.secondary)
                        }.padding(.vertical, 10)
                    } else {
                        HStack(alignment: .top, spacing: 20) {
                            revisionList.frame(width: 230)
                            if let selected { revisionDetail(selected).frame(maxWidth: .infinity, alignment: .leading) }
                        }
                    }
                    Text(L("Plan history contains preparation details. It cannot restore the fitting in your hearing aids."))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 16)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(Brand.accent)
                    Text(L("Plan history")).font(.headline)
                    Spacer(minLength: 8)
                    Text(LP("%d revision", "%d revisions", count: workspace.revisions.count)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("fitting-plan-history")
        .confirmationDialog(L("Use this plan revision?"), isPresented: $confirmingRestore, titleVisibility: .visible) {
            if let selected {
                Button(L("Load into editor")) { workspace.useRevision(selected.id) }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Your current draft will be preserved in history. The saved plan stays in place until you choose Save plan."))
        }
    }

    private var revisionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 7) {
                ForEach(workspace.revisions) { revision in
                    Button { selectedID = revision.id } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(revision.plan.name).font(.callout.weight(.medium)).lineLimit(2)
                            Text(revision.archive.savedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute().second())
                                .font(.caption).foregroundStyle(.secondary)
                            Text(L(revision.archive.reason.title)).font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(selected?.id == revision.id ? Brand.accent.opacity(0.1) : Brand.background.opacity(0.5),
                                        in: RoundedRectangle(cornerRadius: 11))
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(selected?.id == revision.id ? .isSelected : [])
                }
            }
        }.frame(height: 242)
    }

    private func revisionDetail(_ revision: FittingWorkspaceStore.Revision) -> some View {
        let comparison = FittingPlanComparison(revision.plan, workspace.draft)
        return VStack(alignment: .leading, spacing: 13) {
            Text(revision.plan.name).font(.title3.weight(.semibold)).textSelection(.enabled)
            Text(L("%@ · %@", L(revision.plan.model.title), LP("%d program idea", "%d program ideas", count: revision.plan.programs.count)))
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            if comparison.isUnchanged {
                Label(L("Matches the current editor"), systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(Brand.accent)
            } else {
                Text(L("Different from your current editor")).font(.callout.weight(.medium))
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(comparison.changedSections) { section in
                            Label(L(section.title), systemImage: "circle.fill")
                                .font(.caption).foregroundStyle(.secondary)
                                .labelStyle(RevisionChangeLabelStyle())
                        }
                    }
                    Text(comparison.changedSections.map { L($0.title) }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxHeight: 105, alignment: .topLeading)
            }
            Button { selectedID = revision.id; confirmingRestore = true } label: {
                Label(L("Use this revision…"), systemImage: "arrow.uturn.backward")
            }.buttonStyle(.bordered).disabled(comparison.isUnchanged || workspace.loadFailed || workspace.historyReadFailed)
                .accessibilityIdentifier("fitting-use-revision")
        }
    }
}

private struct RevisionChangeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon.font(.system(size: 4)).accessibilityHidden(true)
            configuration.title
        }
    }
}
