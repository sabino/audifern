import AppKit
import SwiftUI

/// The same shortcuts in Sound and the menu bar. Active state always comes
/// from the aids; hiding a shortcut cannot pretend that it is the active one.
struct QuickProgramPicker: View {
    @ObservedObject var store: BluetoothStore
    let aids: [AidConnection]
    let identifier: String
    @EnvironmentObject private var preferences: AppPreferences
    private var catalog: ProgramShortcutCatalog { .init(aids: aids) }
    private var programs: [ProgramShortcutCatalog.Program] { catalog.visible(saved: preferences.quickProgramSelections[catalog.scope]) }
    private var current: String {
        if let id = catalog.activeID {
            return aids.first?.programNames[id] ?? L("Program %d", id + 1)
        }
        return aids.map { L("%@ · %@", L($0.sideLabel), $0.activeProgramName ?? L("Not loaded")) }.joined(separator: " / ")
    }
    var body: some View {
        Group {
            if programs.count > 1 {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        if !programs.contains(where: { $0.id == catalog.activeID }) {
                            Text(current).font(AppType.caption).foregroundStyle(.secondary)
                        }
                        ForEach(programs) { program in chip(program) }
                    }.fixedSize()
                    Menu {
                        ForEach(programs) { program in
                            Button { select(program.id) } label: {
                                Label(program.name, systemImage: catalog.activeID == program.id ? "checkmark.circle.fill" : "circle")
                            }.disabled(!canSelect(program.id))
                        }
                    } label: { Label(current, systemImage: "waveform") }
                        .menuStyle(.borderlessButton).fixedSize()
                }
            } else {
                Label(current, systemImage: "waveform").font(AppType.caption.weight(.medium))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Listening program"))
        .accessibilityValue(current)
        .accessibilityIdentifier(identifier)
        .help(L("Current program: %@", current) + (aids.count == 2 ? "\n" + L("Program shortcuts change both ears.") : ""))
    }
    private func canSelect(_ id: Int) -> Bool {
        !store.isDemo && !store.linkedActionPending && (try? ConsumerControlPlan(aids: aids, change: .program(id))) != nil
    }
    private func select(_ id: Int) {
        guard canSelect(id), catalog.activeID != id else { return }
        store.selectPrograms(aids.map(\.id), program: id)
    }
    private func chip(_ program: ProgramShortcutCatalog.Program) -> some View {
        let active = catalog.activeID == program.id
        let color = ProgramAccent.color(program.id)
        return Button { select(program.id) } label: {
            HStack(spacing: 5) {
                Image(systemName: active ? "checkmark.circle.fill" : "circle").font(.system(size: 11))
                Text(program.name).font(AppType.caption.weight(.semibold)).lineLimit(1)
            }
            .padding(.horizontal, 12).frame(height: 30)
            .foregroundStyle(color)
            .background(color.opacity(active ? 0.17 : 0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(active ? 0.6 : 0.2)))
            .contentShape(Capsule())
        }.buttonStyle(.plain).disabled(!canSelect(program.id))
            .accessibilityAddTraits(active ? [.isSelected] : [])
            .accessibilityIdentifier("\(identifier)-program-\(program.id)")
    }
}

struct QuickProgramSettings: View {
    let aids: [AidConnection]
    @EnvironmentObject private var preferences: AppPreferences
    private var catalog: ProgramShortcutCatalog { .init(aids: aids) }
    private var visible: [ProgramShortcutCatalog.Program] { catalog.visible(saved: preferences.quickProgramSelections[catalog.scope]) }
    var body: some View {
        if catalog.programs.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(L("Quick programs")).font(AppType.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(L("Keep at least one")).font(AppType.small).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [.init(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(catalog.programs) { program in
                        let included = visible.contains { $0.id == program.id }
                        Toggle(program.name, isOn: Binding(get: { included }, set: { value in
                            preferences.setQuickProgram(program.id, included: value, catalog: catalog)
                        })).toggleStyle(.checkbox).font(AppType.caption)
                            .tint(ProgramAccent.color(program.id))
                            .disabled(included && visible.count == 1)
                            .accessibilityIdentifier("quick-program-included-\(program.id)")
                    }
                }
                Text(L("Shown in Sound and the menu bar. This does not change the active program."))
                    .font(AppType.small).foregroundStyle(.secondary)
            }.accessibilityIdentifier("quick-program-settings")
        }
    }
}

private enum ProgramAccent {
    static func color(_ id: Int) -> Color {
        let hue = (Double(id) * 0.381966 + 0.43).truncatingRemainder(dividingBy: 1)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(calibratedHue: hue, saturation: dark ? 0.42 : 0.76, brightness: dark ? 0.95 : 0.43, alpha: 1)
        })
    }
}
