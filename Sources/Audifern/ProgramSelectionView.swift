import SwiftUI

struct ProgramSelectionView: View {
    @ObservedObject var store: BluetoothStore
    let aid: AidConnection
    let targetIDs: [UUID]
    var compact = false
    @EnvironmentObject private var preferences: AppPreferences

    private var targets: [AidConnection] { targetIDs.compactMap { store.connections[$0] } }
    private var programs: [Int] {
        aid.programIDs.filter { id in
            targetIDs.count == 1 || targets.allSatisfy {
                $0.programIDs.contains(id) && aid.programNames[id] != nil && $0.programNames[id] == aid.programNames[id]
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(compact ? L(aid.sideLabel) : L("Fitted program")).font(AppType.caption.weight(.medium)).foregroundStyle(.secondary)
            if let active = aid.activeProgram {
                if programs.count < 2 {
                    Text(aid.activeProgramName ?? L("Current program")).font(AppType.body.weight(.medium))
                    if !compact { Text(L("One program is fitted on this aid.")).font(AppType.caption).foregroundStyle(.secondary) }
                } else {
                    Picker(L("%@ program", L(aid.sideLabel)), selection: Binding(get: { active }, set: { store.selectPrograms(targetIDs, program: $0) })) {
                        ForEach(programs, id: \.self) { id in Text(aid.programNames[id] ?? L("Program %d", id + 1)).tag(id) }
                        if !programs.contains(active) { Text(aid.activeProgramName ?? L("Current program")).tag(active) }
                    }.labelsHidden().disabled(targets.count != targetIDs.count || !targets.allSatisfy(\.canChangeProgram))
                }
            } else { Text(L("Not loaded")).font(AppType.caption).foregroundStyle(.secondary) }
            if !compact || aid.activeProgramName == nil {
                Button(L("Read program names")) { store.refreshProgramInfo(aid.id) }
                    .font(AppType.caption).buttonStyle(.borderless)
                    .disabled(!aid.isConnected || aid.actionPending || aid.advancedBusy || aid.groupActionPending || store.isDemo)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
