import SwiftUI

struct FittingPageView: View {
    @ObservedObject var store: BluetoothStore
    @ObservedObject var workspace: FittingWorkspaceStore
    @ObservedObject var backups: DeviceBackupStore
    let audiograms: AudiogramEditorStore
    @State private var section = "current"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker(L("Fitting tools"), selection: $section) {
                    Text(L("Saved fitting")).tag("current")
                    Text(L("Plan a fitting")).tag("plan")
                }.pickerStyle(.segmented).frame(width: 340).accessibilityIdentifier("fitting-section")
                Spacer()
            }.padding(.horizontal, 30).padding(.top, 22).padding(.bottom, 8)
            if section == "current" {
                FittedConfigurationView(store: store, backups: backups, audiograms: audiograms)
            } else {
                FittingWorkspaceView(store: store, audiograms: audiograms, draft: $workspace.draft,
                    saveDraft: { workspace.save() }, loadDraft: { workspace.reload() },
                    persistenceStatus: workspace.status, canLoadDraft: workspace.canLoadDraft && !workspace.loadFailed)
            }
        }
    }
}
