import AppKit
import Combine
import Darwin
import QuickAccessKit
import WidgetKit

@MainActor final class QuickAccessHost {
    private let store: BluetoothStore
    private let automation: ConnectionAutomation
    private let preferences: AppPreferences
    private let storage: QuickAccessStorage?
    private var watcher: DispatchSourceFileSystemObject?
    private var timer: Task<Void, Never>?
    private var observations: [AnyCancellable] = []
    private var session = UUID()
    private var connectionSignature = ""
    private var processing = false
    private var lastPublished: QuickAccessState?
    private var stopped = false
    init(store: BluetoothStore, automation: ConnectionAutomation, preferences: AppPreferences, storage: QuickAccessStorage? = .applicationGroup()) {
        self.store = store; self.automation = automation; self.preferences = preferences
        self.storage = store.isDemo ? nil : storage
        guard let storage = self.storage else { return }
        do { try storage.prepare(); storage.cleanup() } catch { return }
        let descriptor = Darwin.open(storage.inbox.path, O_EVTONLY)
        if descriptor >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename], queue: .main)
            source.setEventHandler { [weak self] in Task { @MainActor in await self?.drain() } }
            source.setCancelHandler { Darwin.close(descriptor) }; watcher = source; source.resume()
        }
        observations.append(store.$connections.debounce(for: .milliseconds(120), scheduler: RunLoop.main).sink { [weak self] _ in self?.publish() })
        observations.append(automation.objectWillChange.debounce(for: .milliseconds(120), scheduler: RunLoop.main).sink { [weak self] _ in self?.publish() })
        observations.append(preferences.objectWillChange.debounce(for: .milliseconds(120), scheduler: RunLoop.main).sink { [weak self] _ in self?.publish() })
        observations.append(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification).sink { [weak self] _ in self?.shutdown() })
        publish()
        timer = Task { [weak self] in
            await self?.drain()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self else { return }
                self.automation.refreshAudio(); self.publish(); self.storage?.cleanup()
            }
        }
    }
    func snapshot(at now: Date = Date()) -> QuickAccessState {
        let signature = store.orderedConnections.map { "\($0.id):\($0.connectedAt?.timeIntervalSince1970 ?? 0):\($0.isConnected)" }.joined(separator: ";")
        if signature != connectionSignature { connectionSignature = signature; session = UUID() }
        let ears = store.orderedConnections.compactMap { aid -> QuickEar? in
            guard aid.sideLabel == "Left" || aid.sideLabel == "Right" else { return nil }
            return .init(side: aid.sideLabel == "Left" ? .left : .right, connected: aid.isConnected, battery: aid.battery,
                runtime: aid.batteryReading(at: now), level: aid.volume?.level, muted: aid.volume?.muted,
                minimum: aid.volumeRanges?.main.lowerBound, maximum: aid.volumeRanges?.main.upperBound,
                canChangeVolume: aid.canChangeVolume, speechBooster: aid.speechBoosterEnabled, canChangeSpeechBooster: aid.canChangeSpeechBooster)
        }
        return .init(session: session, updatedAt: now, sharingEnabled: preferences.widgetsEnabled && !stopped, ears: ears,
            paused: automation.paused, canReconnect: !automation.remembered.isEmpty && store.isPoweredOn,
            macAudio: automation.macAudioSelected, canSwitchAudio: automation.canSwitchAudio)
    }
    private func publish() {
        guard let storage else { return }
        automation.connectionStateChanged()
        let state = snapshot()
        let changed = lastPublished.map {
            $0.session != state.session || $0.sharingEnabled != state.sharingEnabled || $0.ears != state.ears
                || $0.paused != state.paused || $0.canReconnect != state.canReconnect
                || $0.macAudio != state.macAudio || $0.canSwitchAudio != state.canSwitchAudio
        } ?? true
        guard changed || Date().timeIntervalSince(lastPublished?.updatedAt ?? .distantPast) >= 25 else { return }
        do { try storage.save(state); lastPublished = state } catch { return }
        guard changed else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: "org.audifern.batteries")
        WidgetCenter.shared.reloadTimelines(ofKind: "org.audifern.quick-controls")
        if #available(macOS 26.0, *) { ControlCenter.shared.reloadAllControls() }
    }
    private func shutdown() { stopped = true; publish(); watcher?.cancel(); timer?.cancel() }
    private func drain() async {
        guard let storage, !processing else { return }
        processing = true; defer { processing = false }
        while let command = storage.claimNext() {
            let state = snapshot()
            guard state.permits(command, at: Date()) else {
                try? storage.acknowledge(.init(id: command.id, accepted: false, message: "Refresh Audifern before using this control.")); continue
            }
            let result = await execute(command)
            try? storage.acknowledge(.init(id: command.id, accepted: result, message: result ? "Change confirmed." : "The requested change was not confirmed."))
            publish()
        }
    }
    private func execute(_ command: QuickCommand) async -> Bool {
        guard !store.isDemo else { return false }
        let aids = store.orderedConnections.filter { aid in
            command.target == .both ? ["Left", "Right"].contains(aid.sideLabel) : aid.sideLabel.lowercased() == command.target.rawValue
        }
        let ids = aids.map(\.id), beforeLevels = Dictionary(uniqueKeysWithValues: aids.compactMap { aid in aid.volume.map { (aid.id, $0.level) } })
        switch command.kind {
        case .connection:
            if command.flag == true { automation.connectNow() } else { automation.pause() }
        case .audio:
            automation.setMacAudio(command.flag == true)
            return !automation.audioError && automation.macAudioSelected == command.flag
        case .volume:
            guard let first = aids.first, let selection = MainVolumeSelection(aids: aids, anchorID: first.id), let delta = command.delta else { return false }
            store.setMainVolume(selection, level: selection.level + delta)
        case .mute:
            guard let flag = command.flag else { return false }
            if aids.count == 2 { store.setLinkedMuted(flag) }
            else if let aid = aids.first { store.setMuted(aid.id, muted: flag) }
        case .speechBooster:
            guard let flag = command.flag else { return false }
            store.setSpeechBoosters(ids, enabled: flag)
        }
        let deadline = Date().addingTimeInterval(command.kind == .connection ? 6 : 12)
        repeat {
            if command.kind == .connection {
                if command.flag == false && store.connectedCount == 0 { return true }
                if command.flag == true && !automation.paused && store.connectedCount > 0 { return true }
            } else if !store.linkedActionPending && ids.allSatisfy({ id in
                guard let aid = store.connections[id] else { return false }
                return aid.isConnected && !aid.actionPending && !aid.groupActionPending && !aid.advancedBusy
            }) {
                return ids.allSatisfy { id in
                    guard let aid = store.connections[id], !aid.actionFailed else { return false }
                    switch command.kind {
                    case .volume: return beforeLevels[id].map { aid.volume?.level == $0 + (command.delta ?? 0) } ?? false
                    case .mute: return aid.volume?.muted == command.flag
                    case .speechBooster: return aid.speechBoosterEnabled == command.flag
                    default: return false
                    }
                }
            }
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return false }
        } while Date() < deadline
        return false
    }
}
