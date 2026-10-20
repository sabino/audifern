import CompanionCore
import SwiftUI

/// Dedicated legacy source gains. These are separate from microphone gain,
/// streamed-audio EQ and the Mac's system media-volume control.
struct AuxiliaryVolumeSectionView: View {
    @EnvironmentObject private var preferences: AppPreferences
    enum Source: Equatable {
        case streaming, tinnitus
        var title: String { self == .tinnitus ? "Tinnitus relief" : "Streaming-source volume" }
        var symbol: String { self == .tinnitus ? "waveform.path" : "headphones" }
        var tint: Color { self == .tinnitus ? .orange : .teal }
    }
    @ObservedObject var store: BluetoothStore
    let aids: [AidConnection]
    let source: Source
    @Binding var linked: Bool

    private var linkAvailable: Bool {
        aids.count == 2 && Set(aids.map(\.id)) == Set(store.connectedPair.map(\.id))
            && aids.allSatisfy { eligibility($0) == true }
    }
    private func targets(_ aid: AidConnection) -> [AidConnection] { linked && aids.count == 2 ? aids : [aid] }
    private func volume(_ aid: AidConnection) -> OticonRemoteProtocol.Volume? { source == .tinnitus ? aid.tinnitusVolume : aid.streamingVolume }
    private func range(_ aid: AidConnection) -> ClosedRange<Int>? { source == .tinnitus ? aid.volumeRanges?.tinnitus : aid.volumeRanges?.streaming }
    private func eligibility(_ aid: AidConnection) -> Bool? {
        guard let program = aid.activeProgram else { return nil }
        if source == .tinnitus { return aid.programTinnitus[program] }
        guard let tinnitus = aid.programTinnitus[program] else { return nil }
        return tinnitus ? false : aid.programStreaming[program]
    }
    private func ready(_ aid: AidConnection) -> Bool { source == .tinnitus ? aid.canChangeTinnitusVolume : aid.canChangeStreamingVolume }
    private func canChange(_ aid: AidConnection) -> Bool { targets(aid).allSatisfy(ready) }
    private func canStep(_ aid: AidConnection, _ delta: Int) -> Bool {
        canChange(aid) && targets(aid).allSatisfy { target in
            guard let current = volume(target), let bounds = range(target) else { return false }
            return bounds.contains(current.level + delta)
        }
    }
    private func adjust(_ aid: AidConnection, _ delta: Int) {
        let ids = targets(aid).map(\.id)
        if source == .tinnitus { store.adjustTinnitusVolume(ids: ids, by: delta) }
        else { store.adjustStreamingVolume(ids: ids, by: delta) }
    }
    private func setMuted(_ aid: AidConnection, _ value: Bool) {
        let ids = targets(aid).map(\.id)
        if source == .tinnitus { store.setTinnitusMuted(ids: ids, muted: value) }
        else { store.setStreamingMuted(ids: ids, muted: value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L(source.title), systemImage: source.symbol).font(.headline).foregroundStyle(source.tint)
            if aids.count == 2 {
                EarSettingsRow {
                    cell(aids[0], showButtons: !linked)
                } center: {
                    EarLinkButton(title: source.title, linked: $linked, available: linkAvailable,
                                  identifier: source == .tinnitus ? "link-tinnitus-volume" : "link-streaming-volume", accent: source.tint)
                } right: {
                    cell(aids[1], showButtons: !linked)
                }
                if linked { buttons(aids[0]) }
            } else {
                ForEach(aids) { cell($0, showButtons: true) }
            }
            if source == .tinnitus {
                Label(L("This adjusts the tinnitus relief sound, separately from microphone and streaming volume. Use only a program fitted for you and follow your hearing care professional’s level and daily-use limits. A reported range does not enable tinnitus therapy."), systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Link("Oticon’s Tinnitus SoundSupport guidance", destination: URL(string: "https://www.oticon.com/support/oticon-app/help-with-the-oticon-app/how-to-use-tinnitus-soundsupport-program")!)
                    .font(.caption)
            } else {
                Text(L("The dedicated streaming-source gain is available in TV or generic-streamer programs. It is separate from streamed-audio EQ and your Mac’s media volume."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(16).tint(source.tint)
            .background(source.tint.opacity(source == .tinnitus ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(source.tint.opacity(source == .tinnitus ? 0.22 : 0.1)))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(source == .tinnitus ? "tinnitus-section" : "streaming-volume-section")
    }

    private func cell(_ aid: AidConnection, showButtons: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L(aid.sideLabel)).font(.callout.weight(.medium))
                Spacer()
                Text(volume(aid).map { "\($0.level > 0 ? "+" : "")\($0.level) · \($0.muted ? "Muted" : "Unmuted")" } ?? "Not read")
                    .font(.callout.monospacedDigit())
                    .accessibilityIdentifier("\(source == .tinnitus ? "tinnitus" : "streaming")-\(aid.sideLabel.lowercased())-volume")
            }
            if let bounds = range(aid) {
                Text(L("Reported range: %@…%@ device steps", String(describing: bounds.lowerBound), String(describing: bounds.upperBound)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if showButtons { buttons(aid) }
            if !aid.isConnected {
                Text(L("Connect this aid to read its controls.")).font(.caption).foregroundStyle(.secondary)
            } else if eligibility(aid) == false {
                Text(source == .tinnitus
                     ? L("%@ does not report tinnitus support.", String(describing: aid.activeProgramName ?? L("This program")))
                     : L("%@ is not a supported streaming-source program.", String(describing: aid.activeProgramName ?? L("This program"))))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if eligibility(aid) == nil {
                Button(L("Read program details")) { store.refreshProgramInfo(aid.id) }
                    .buttonStyle(.borderless).font(.caption).disabled(!canRead(aid))
                    .accessibilityLabel(L("Read %@ %@ eligibility", L(aid.sideLabel), String(describing: source == .tinnitus ? "tinnitus" : "streaming")))
            } else if volume(aid) == nil {
                Button(L("Read current volume")) { store.refresh(aid.id) }.font(.caption).disabled(!canRead(aid))
            }
            let status = source == .tinnitus ? aid.tinnitusStatus : aid.streamingVolumeStatus
            let failed = source == .tinnitus ? aid.tinnitusStatusFailed : aid.streamingVolumeStatusFailed
            if let status { Text(M(status)).font(.caption).foregroundStyle(failed ? Color.orange : Color.secondary).textSelection(.enabled) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func canRead(_ aid: AidConnection) -> Bool {
        aid.isConnected && !aid.actionPending && !aid.advancedBusy && !aid.groupActionPending
    }
    private func buttons(_ aid: AidConnection) -> some View {
        let allMuted = targets(aid).allSatisfy { volume($0)?.muted == true }
        let subject = linked && aids.count == 2 ? "both" : aid.sideLabel.lowercased()
        let name = source == .tinnitus ? "tinnitus" : "streaming-source"
        return HStack(spacing: 8) {
            Button { adjust(aid, -1) } label: { Image(systemName: "minus").frame(width: 28, height: 24) }
                .disabled(!canStep(aid, -1)).accessibilityLabel(L("Decrease %@ %@ volume", String(describing: subject), String(describing: name)))
            Button { setMuted(aid, !allMuted) } label: {
                Label(allMuted ? (linked ? L("Unmute both") : L("Unmute")) : (linked ? L("Mute both") : L("Mute")),
                      systemImage: allMuted ? "speaker.wave.2" : "speaker.slash")
                    .lineLimit(1).frame(maxWidth: .infinity, minHeight: 24)
            }.disabled(!canChange(aid)).accessibilityLabel(L("%@ %@ %@ sound", String(describing: allMuted ? L("Unmute") : L("Mute")), String(describing: subject), String(describing: name)))
            Button { adjust(aid, 1) } label: { Image(systemName: "plus").frame(width: 28, height: 24) }
                .disabled(!canStep(aid, 1)).accessibilityLabel(L("Increase %@ %@ volume", String(describing: subject), String(describing: name)))
        }.buttonStyle(.bordered)
    }
}
