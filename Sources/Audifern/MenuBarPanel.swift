import SwiftUI

struct MenuBarPanel: View {
    @ObservedObject var store: BluetoothStore
    @ObservedObject var automation: ConnectionAutomation
    @ObservedObject var help: AppHelpController
    var didChangeLayout: (() -> Void)? = nil
    @EnvironmentObject private var preferences: AppPreferences
    @AppStorage("groupedHearingAidControls") private var together = true
    private var aids: [AidConnection] { store.orderedConnections.filter { ["Left", "Right"].contains($0.sideLabel) }.sorted { $0.sideLabel < $1.sideLabel } }
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: AppResources.brandMark).resizable().scaledToFit().frame(width: 25, height: 31)
                Text(Brand.name).font(.system(size: 21, weight: .semibold))
                Spacer()
                Menu {
                    Button(L("Quick access settings…")) { help.openFeature("menu-bar") }
                    Button(L("Battery alerts…")) { help.openFeature("battery-alerts") }
                    Divider()
                    Button(L("Quit Audifern")) { NSApplication.shared.terminate(nil) }
                } label: { Image(systemName: "gearshape").font(.system(size: 18)) }.menuStyle(.borderlessButton).fixedSize()
            }
            HStack(spacing: 6) {
                Circle().fill(store.connectedCount > 0 ? Brand.accent : .secondary).frame(width: 6, height: 6)
                Text(store.isDemo ? L("Preview mode") : store.connectedCount > 0 ? L("%d connected", store.connectedCount) : L("Disconnected"))
            }.font(AppType.caption).foregroundStyle(.secondary).frame(height: 20)
            HStack(alignment: .top, spacing: 16) {
                ear("Left")
                Divider().frame(height: preferences.menuBarArtwork ? 146 : 68)
                ear("Right")
            }.padding(.vertical, 2)
            if preferences.menuBarSound { soundControls }
            if preferences.menuBarPrograms, let first = aids.first {
                panel {
                    HStack(spacing: 14) {
                        if together {
                            ProgramSelectionView(store: store, aid: first, targetIDs: aids.map(\.id), compact: true)
                        } else {
                            ForEach(aids) { aid in ProgramSelectionView(store: store, aid: aid, targetIDs: [aid.id], compact: true) }
                        }
                    }.frame(minHeight: 44)
                }
            }
            if preferences.menuBarAudio { audioControls }
            panel {
                HStack(spacing: 10) {
                    Image(systemName: automation.paused ? "link.badge.plus" : "link").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("App controls")).font(AppType.callout.weight(.medium))
                        Text(automation.paused ? L("Paused") : store.connectedCount > 0 ? L("Connected") : L("Disconnected"))
                            .font(AppType.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 2)
                    Button(automation.paused || store.connectedCount == 0 ? L("Reconnect") : L("Pause")) {
                        if automation.paused || store.connectedCount == 0 {
                            if !automation.remembered.isEmpty { automation.connectNow() }
                            else if store.pairCandidateIDs.count == 2 { store.connectPair() }
                            else { help.openFeature("getting-started") }
                        }
                        else { automation.pause() }
                    }.frame(width: 100).controlSize(.regular)
                }.frame(height: 43)
            }
            Divider()
            HStack {
                Button { help.openFeature("volume") } label: { Label(L("Open Audifern"), systemImage: "arrow.up.forward.square") }
                Spacer()
                Button { help.openHelp() } label: { Label(L("Help"), systemImage: "questionmark.circle") }
            }.buttonStyle(.plain).font(AppType.callout).padding(.vertical, 4)
        }.padding(18).frame(width: preferences.menuBarExpanded ? 422 : 382)
            .background(.regularMaterial).tint(Brand.accent)
            .preferredColorScheme(preferences.appearance.colorScheme)
            .accessibilityIdentifier("menu-bar-panel")
            .onAppear { automation.refreshAudio() }
            .onChange(of: together) { _, _ in didChangeLayout?() }
    }
    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().padding(13).frame(maxWidth: .infinity).background(Brand.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.quaternary))
    }
    private func ear(_ side: String) -> some View {
        let aid = aids.first { $0.sideLabel == side }
        return VStack(spacing: 7) {
            Text(L(side)).font(AppType.callout.weight(.semibold))
            if preferences.menuBarArtwork { HearingAidArtwork(right: side == "Right", size: 0.42).frame(height: 86) }
            if let aid, preferences.menuBarTime { AidBatteryView(store: store, aid: aid, compact: true) }
            else { Label(aid?.battery.map { "\($0)%" } ?? "—", systemImage: "battery.75percent").font(AppType.callout.monospacedDigit()).frame(height: 26) }
            ProgressView(value: Double(aid?.battery ?? 0), total: 100).tint(Brand.accent).frame(maxWidth: 92)
        }.frame(maxWidth: .infinity)
    }
    private var soundControls: some View {
        panel {
            VStack(spacing: 10) {
                HStack {
                    Text(L("Volume")).font(AppType.callout.weight(.semibold))
                    Spacer()
                    Button { together.toggle() } label: { Label(together ? L("Together") : L("Separate"), systemImage: together ? "link" : "ear") }
                        .buttonStyle(.plain).font(AppType.caption).foregroundStyle(Brand.accent).frame(width: 108)
                }
                if let first = aids.first {
                    if together || aids.count == 1 {
                        if preferences.menuBarExpanded { horizontalVolume(first, targets: aids) }
                        HStack {
                            VolumeLevelButtons(store: store, aid: first, targets: aids)
                            Spacer(minLength: 4)
                            StableMuteToggle(store: store, targets: aids)
                        }
                    } else {
                        ForEach(aids) { aid in
                            HStack(spacing: 6) {
                                Text(L(aid.sideLabel)).font(AppType.caption).frame(width: 72, alignment: .leading)
                                VolumeLevelButtons(store: store, aid: aid, targets: [aid], compact: true)
                                StableMuteToggle(store: store, targets: [aid])
                            }
                            if preferences.menuBarExpanded { horizontalVolume(aid, targets: [aid]) }
                        }
                    }
                    Divider()
                    if together {
                        Toggle(L("SpeechBooster"), isOn: Binding(get: { !aids.isEmpty && aids.allSatisfy { $0.speechBoosterEnabled == true } },
                            set: { store.setSpeechBoosters(aids.map(\.id), enabled: $0) }))
                            .toggleStyle(.switch).font(AppType.callout)
                            .disabled(store.isDemo || !aids.allSatisfy(\.canChangeSpeechBooster))
                    } else {
                        Text(L("SpeechBooster")).font(AppType.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        HStack { ForEach(aids) { aid in
                            Toggle(L(aid.sideLabel), isOn: Binding(get: { aid.speechBoosterEnabled == true }, set: { store.setSpeechBooster(aid.id, enabled: $0) }))
                                .toggleStyle(.switch).font(AppType.caption).disabled(store.isDemo || !aid.canChangeSpeechBooster)
                        }}.accessibilityLabel(L("SpeechBooster"))
                    }
                } else { Text(L("Connect your hearing aids")).font(AppType.callout).foregroundStyle(.secondary).frame(height: 58) }
            }
        }
    }
    private func horizontalVolume(_ aid: AidConnection, targets: [AidConnection]) -> some View {
        HorizontalVolumeFader(store: store, aid: aid, targets: targets)
    }
    private var audioControls: some View {
        panel {
            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.2").foregroundStyle(Brand.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Mac audio output")).font(AppType.callout.weight(.medium))
                    Text(automation.availableOutputs.first { $0.id == automation.currentOutputUID }?.name ?? L("Unavailable"))
                        .font(AppType.caption).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }
                Menu {
                    ForEach(automation.availableOutputs) { output in
                        Button { automation.selectAudioOutput(output.id) } label: {
                            if output.id == automation.currentOutputUID { Label(output.name, systemImage: "checkmark") }
                            else { Text(output.name) }
                        }
                    }
                    Divider()
                    Button(L("Audio output settings…")) { help.openFeature("mac-audio") }
                } label: { Text(L("Switch…")) }.menuStyle(.borderlessButton).fixedSize()
            }.frame(height: 43)
        }
    }
}

private struct HorizontalVolumeFader: View {
    @ObservedObject var store: BluetoothStore
    let aid: AidConnection
    let targets: [AidConnection]
    @State private var draft: Double?
    @State private var editing = false
    @State private var captured: MainVolumeSelection?
    private var selection: MainVolumeSelection? { .init(aids: targets, anchorID: aid.id) }
    var body: some View {
        let range = selection?.range ?? aid.volumeRanges?.main ?? 0...0
        HStack {
            Image(systemName: "speaker.wave.1").foregroundStyle(.secondary)
            Slider(value: Binding(get: { draft ?? Double(aid.volume?.level ?? 0) }, set: { draft = $0 }),
                in: Double(range.lowerBound)...Double(max(range.lowerBound + 1, range.upperBound)), step: 1,
                onEditingChanged: { value in
                    editing = value
                    if value { captured = selection }
                    else if let captured, let draft { store.setMainVolume(captured, level: Int(draft.rounded())); self.captured = nil }
                }).disabled(store.isDemo || selection == nil)
            Image(systemName: "speaker.wave.3").foregroundStyle(.secondary)
        }.frame(height: 25)
            .onChange(of: aid.volume?.level) { _, _ in if !editing { draft = nil } }
            .onChange(of: aid.actionFailed) { _, failed in if failed { draft = nil } }
    }
}
