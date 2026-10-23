import AppKit
import Combine
import CoreGraphics
import Foundation

struct RememberedHearingAid: Codable, Equatable, Identifiable {
    let id: UUID
    let side: String
}

struct ConnectionSignal {
    let rssi: Int
    let measuredAt: Date
    func isFresh(at now: Date) -> Bool { (-127 ... -1).contains(rssi) && (0...12).contains(now.timeIntervalSince(measuredAt)) }
}

@MainActor protocol AutomaticConnectionTransport: AnyObject {
    var automationPoweredOn: Bool { get }
    var automationPhases: [UUID: ConnectionPhase] { get }
    var automationSignals: [UUID: ConnectionSignal] { get }
    var automationCurrentAids: [RememberedHearingAid] { get }
    func retrieveRemembered(_ ids: [UUID])
    func scanForRemembered()
    func stopAutomaticScan()
    func connectRemembered(_ id: UUID) -> Bool
    func disconnectAutomaticConnections()
    func measureConnectedSignal()
}

/// Opt-in control-channel reconnection. It never discovers an identity by name,
/// replays a sound command, powers Bluetooth off, or claims to transfer audio.
@MainActor final class ConnectionAutomation: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "autoConnectionEnabled")
            if enabled && !oldValue && remembered.isEmpty { _ = useConnectedAids() }
            settingsChanged()
        }
    }
    @Published var whenNearby: Bool { didSet { defaults.set(whenNearby, forKey: "autoConnectionNearby"); settingsChanged() } }
    @Published var afterUnlock: Bool { didSet { defaults.set(afterUnlock, forKey: "autoConnectionUnlock"); settingsChanged() } }
    @Published var limitSignal: Bool { didSet { defaults.set(limitSignal, forKey: "autoConnectionLimitSignal"); settingsChanged() } }
    @Published var minimumRSSI: Double { didSet { defaults.set(minimumRSSI, forKey: "autoConnectionMinimumRSSI"); settingsChanged() } }
    @Published var releaseOnLock: Bool { didSet { defaults.set(releaseOnLock, forKey: "autoConnectionReleaseOnLock") } }
    @Published var preferMacAudio: Bool { didSet { defaults.set(preferMacAudio, forKey: "autoConnectionPreferAudio"); audioContext = nil; settingsChanged() } }
    @Published var restoreAudioOnLock: Bool { didSet { defaults.set(restoreAudioOnLock, forKey: "autoConnectionRestoreAudio") } }
    @Published var preferredOutputUID: String { didSet { defaults.set(preferredOutputUID, forKey: "autoConnectionOutputUID"); audioContext = nil; settingsChanged() } }
    @Published var fallbackOutputUID: String { didSet { defaults.set(fallbackOutputUID, forKey: "autoConnectionFallbackOutputUID"); refreshAudio() } }
    @Published private(set) var remembered: [RememberedHearingAid]
    @Published private(set) var paused: Bool
    @Published private(set) var status = "Automatic connection is off."
    @Published private(set) var availableOutputs: [MacAudioOutput] = []
    @Published private(set) var currentOutputUID: String?
    @Published private(set) var audioError = false
    @Published private(set) var currentSignal: Int?
    private let defaults: UserDefaults
    private let transport: any AutomaticConnectionTransport
    private let audio: any MacAudioOutputClient
    private let now: () -> Date
    private let runTimer: Bool
    private var task: Task<Void, Never>?
    private var observer: ConnectionSessionObserver?
    private var readSession: (() -> Bool)?
    private var manualDeadline: Date?
    private var manualTask: Task<Void, Never>?
    private var observedPhases: [UUID: ConnectionPhase] = [:]
    private var unlocked = true
    private var unlockWindow: Date = .distantPast
    private var nextScan: Date = .distantPast
    private var retryAt: [UUID: Date] = [:]
    private var attempts: [UUID: Int] = [:]
    private var audioContext: String?
    private var ownedOutput: String?
    private var previousOutput: String?
    private var calibrationDeadline: Date?
    private var calibrationTask: Task<Void, Never>?
    private var pendingManualTargets: Set<UUID> = []

    init(defaults: UserDefaults, transport: any AutomaticConnectionTransport,
         audio: any MacAudioOutputClient, now: @escaping () -> Date = Date.init,
         runTimer: Bool = true, observeSession: Bool = true, readSession: (() -> Bool)? = nil) {
        self.defaults = defaults; self.transport = transport; self.audio = audio; self.now = now; self.runTimer = runTimer
        enabled = defaults.bool(forKey: "autoConnectionEnabled")
        whenNearby = defaults.object(forKey: "autoConnectionNearby") as? Bool ?? true
        afterUnlock = defaults.object(forKey: "autoConnectionUnlock") as? Bool ?? true
        limitSignal = defaults.bool(forKey: "autoConnectionLimitSignal")
        let rssi = defaults.object(forKey: "autoConnectionMinimumRSSI") as? Double ?? -70
        minimumRSSI = rssi.isFinite ? min(-35, max(-90, rssi)) : -70
        releaseOnLock = defaults.bool(forKey: "autoConnectionReleaseOnLock")
        preferMacAudio = defaults.bool(forKey: "autoConnectionPreferAudio")
        restoreAudioOnLock = defaults.bool(forKey: "autoConnectionRestoreAudio")
        preferredOutputUID = defaults.string(forKey: "autoConnectionOutputUID") ?? ""
        fallbackOutputUID = defaults.string(forKey: "autoConnectionFallbackOutputUID") ?? ""
        paused = defaults.bool(forKey: "autoConnectionPaused")
        let saved = defaults.data(forKey: "autoConnectionKnownAids").flatMap { try? JSONDecoder().decode([RememberedHearingAid].self, from: $0) } ?? []
        remembered = Self.validTargets(saved) ? saved : []
        self.readSession = readSession
        if observeSession {
            observer = ConnectionSessionObserver { [weak self] in self?.sessionChanged(unlocked: $0) }
            if readSession == nil { self.readSession = { [weak observer] in observer?.isUnlocked ?? false } }
        }
        if let readSession = self.readSession { unlocked = readSession() }
        unlockWindow = now().addingTimeInterval(45)
        settingsChanged()
    }
    static func validTargets(_ aids: [RememberedHearingAid]) -> Bool {
        (1...2).contains(aids.count) && Set(aids.map(\.id)).count == aids.count && Set(aids.map(\.side)).count == aids.count
            && aids.allSatisfy { ["Left", "Right"].contains($0.side) }
    }
    @discardableResult func useConnectedAids() -> Bool {
        let aids = transport.automationCurrentAids
        guard Self.validTargets(aids) else { return false }
        remembered = aids
        defaults.set(try? JSONEncoder().encode(aids), forKey: "autoConnectionKnownAids")
        retryAt = [:]; attempts = [:]; nextScan = .distantPast; settingsChanged()
        return true
    }
    var canUseConnectedAids: Bool { Self.validTargets(transport.automationCurrentAids) }
    func forgetAids() {
        pendingManualTargets = []
        remembered = []; defaults.removeObject(forKey: "autoConnectionKnownAids")
        retryAt = [:]; attempts = [:]; transport.stopAutomaticScan(); tick()
    }
    func pause(disconnect: Bool = true) {
        endManualAttempt()
        paused = true; defaults.set(true, forKey: "autoConnectionPaused")
        transport.stopAutomaticScan()
        if disconnect { transport.disconnectAutomaticConnections() }
        restoreOwnedAudio(); tick()
    }
    func resume() {
        paused = false; defaults.set(false, forKey: "autoConnectionPaused")
        retryAt = [:]; attempts = [:]; nextScan = .distantPast; unlockWindow = now().addingTimeInterval(45); audioContext = nil; tick()
    }
    func manualConnectionRequested() {
        pendingManualTargets.formUnion(transport.automationPhases.filter { [.connecting, .connected].contains($0.value) }.map(\.key))
        resume()
    }
    func connectionStateChanged() {
        defer {
            let phases = transport.automationPhases
            if phases != observedPhases { observedPhases = phases; tick() }
        }
        guard !pendingManualTargets.isEmpty else { return }
        let ids = Set(transport.automationCurrentAids.map(\.id))
        guard pendingManualTargets.isSubset(of: ids), Self.validTargets(transport.automationCurrentAids) else { return }
        pendingManualTargets = []; _ = useConnectedAids()
    }
    /// Explicit quick reconnect works independently of the automatic preference.
    func connectNow() {
        manualDeadline = now().addingTimeInterval(20)
        resume()
        guard unlocked, transport.automationPoweredOn, !remembered.isEmpty else { endManualAttempt(); return }
        if runTimer, manualDeadline != nil {
            manualTask?.cancel()
            manualTask = Task { [weak self] in
                for _ in 0..<21 {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard let self, self.manualDeadline != nil else { return }
                    self.tick()
                }
            }
        }
    }
    func sessionChanged(unlocked value: Bool) {
        updateSession(unlocked: value)
        tick()
    }
    private func updateSession(unlocked value: Bool) {
        let wasUnlocked = unlocked; unlocked = value
        if !value && wasUnlocked {
            endManualAttempt()
            transport.stopAutomaticScan()
            if enabled && releaseOnLock { transport.disconnectAutomaticConnections() }
            if enabled && restoreAudioOnLock { restoreOwnedAudio() }
        } else if !wasUnlocked {
            if afterUnlock { unlockWindow = now().addingTimeInterval(45); retryAt = [:]; nextScan = .distantPast }
            audioContext = nil
        }
    }
    private func endManualAttempt() {
        manualDeadline = nil; manualTask?.cancel(); manualTask = nil
    }
    var retryDelay: Int? {
        let phases = transport.automationPhases
        return remembered.filter { phases[$0.id] != .connected }.compactMap { retryAt[$0.id] }
            .filter { $0 > now() }.min().map { Int(ceil($0.timeIntervalSince(now()))) }
    }
    private func settingsChanged() {
        if enabled && afterUnlock { unlockWindow = now().addingTimeInterval(45) }
        task?.cancel(); task = nil
        if !enabled { transport.stopAutomaticScan() }
        if enabled && runTimer {
            task = Task { [weak self] in
                while !Task.isCancelled {
                    self?.tick()
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                }
            }
        }
        tick()
    }
    func refreshAudio() {
        availableOutputs = audio.outputs(); currentOutputUID = audio.currentOutput()
    }
    func usePreferredAudio() {
        refreshAudio()
        guard !preferredOutputUID.isEmpty, availableOutputs.contains(where: { $0.id == preferredOutputUID }) else { audioError = true; return }
        let previous = audio.currentOutput()
        guard previous != preferredOutputUID else { audioError = false; return }
        guard audio.selectOutput(preferredOutputUID) else { audioError = true; return }
        if ownedOutput == nil || previous != ownedOutput { previousOutput = previous }
        ownedOutput = preferredOutputUID; audioError = false; refreshAudio()
    }
    var macAudioSelected: Bool { !preferredOutputUID.isEmpty && currentOutputUID == preferredOutputUID }
    var canSwitchAudio: Bool {
        preferredOutputUID != fallbackOutputUID && !preferredOutputUID.isEmpty && !fallbackOutputUID.isEmpty
            && [preferredOutputUID, fallbackOutputUID].allSatisfy { id in availableOutputs.contains { $0.id == id } }
    }
    func selectAudioOutput(_ uid: String) {
        if uid == preferredOutputUID { usePreferredAudio(); return }
        refreshAudio()
        guard availableOutputs.contains(where: { $0.id == uid }), audio.selectOutput(uid) else { audioError = true; return }
        ownedOutput = nil; previousOutput = nil; audioError = false
        // A deliberate output change must not be immediately undone by retry.
        audioContext = remembered.map(\.id.uuidString).joined() + preferredOutputUID
        refreshAudio()
    }
    func setMacAudio(_ enabled: Bool) {
        refreshAudio()
        guard canSwitchAudio else { audioError = true; return }
        selectAudioOutput(enabled ? preferredOutputUID : fallbackOutputUID)
    }
    private func restoreOwnedAudio() {
        defer { ownedOutput = nil; previousOutput = nil; audioContext = nil }
        // Respect an output the user selected after Audifern's own change.
        if let ownedOutput, let previousOutput, audio.currentOutput() == ownedOutput,
           audio.outputs().contains(where: { $0.id == previousOutput }) {
            audioError = !audio.selectOutput(previousOutput)
        }
        refreshAudio()
    }
    func calibrateSignal() {
        calibrationTask?.cancel()
        calibrationDeadline = now().addingTimeInterval(10)
        transport.measureConnectedSignal()
        updateSignal()
        // Measurements arrive asynchronously, including when automatic
        // reconnection is off and its regular timer is not running.
        if runTimer && calibrationDeadline != nil {
            calibrationTask = Task { [weak self] in
                for _ in 0..<11 {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard let self, self.calibrationDeadline != nil else { return }
                    self.updateSignal()
                }
            }
        }
    }
    private func updateSignal() {
        let signals = transport.automationSignals
        let fresh = remembered.compactMap { signals[$0.id] }.filter { $0.isFresh(at: now()) }
        currentSignal = fresh.count == remembered.count && !fresh.isEmpty ? fresh.map(\.rssi).min() : nil
        if let deadline = calibrationDeadline {
            if now() > deadline { calibrationDeadline = nil }
            else if let currentSignal, fresh.allSatisfy({ $0.measuredAt >= deadline.addingTimeInterval(-10) }) {
                calibrationDeadline = nil
                minimumRSSI = Double(min(-35, max(-90, currentSignal)))
            }
        }
    }
    func tick() {
        // Notifications can be missed during sleep or fast user switching.
        // Re-read the current session instead of keeping a stale lock latch.
        if let readSession { updateSession(unlocked: readSession()) }
        refreshAudio(); updateSignal()
        if let manualDeadline, now() >= manualDeadline { endManualAttempt(); transport.stopAutomaticScan() }
        let manual = manualDeadline != nil
        guard enabled || manual else { status = "Automatic connection is off."; return }
        guard !paused else { status = "App connection is paused."; return }
        guard unlocked else { status = "Waiting for this Mac to unlock."; return }
        guard !remembered.isEmpty else { status = "Choose your hearing aids first."; return }
        guard transport.automationPoweredOn else { status = "Waiting for Bluetooth."; return }
        let ids = remembered.map(\.id)
        let phases = transport.automationPhases
        let missing = ids.filter { ![ConnectionPhase.connected, .connecting, .disconnecting].contains(phases[$0] ?? .disconnected) }
        if ids.allSatisfy({ phases[$0] == .connected }) {
            endManualAttempt()
            retryAt = [:]; attempts = [:]; transport.stopAutomaticScan(); status = "App controls connected."
            let context = ids.map(\.uuidString).joined() + preferredOutputUID
            if preferMacAudio && audioContext != context && availableOutputs.contains(where: { $0.id == preferredOutputUID }) {
                usePreferredAudio(); audioContext = context
            }
            return
        }
        audioContext = nil
        guard manual || whenNearby || (afterUnlock && now() < unlockWindow) else {
            status = afterUnlock ? "Waiting for the next unlock." : "Choose a reconnect trigger."
            return
        }
        guard !missing.isEmpty else { status = "Connecting app controls…"; return }
        let eligible = missing.filter { now() >= retryAt[$0, default: .distantPast] }
        guard !eligible.isEmpty else { status = "Waiting before trying again."; return }
        transport.retrieveRemembered(eligible)
        var attempted = false
        var needsScan = false
        for id in eligible {
            if limitSignal && !manual {
                guard let signal = transport.automationSignals[id], signal.isFresh(at: now()), Double(signal.rssi) >= minimumRSSI else { needsScan = true; continue }
            }
            guard transport.connectRemembered(id) else { needsScan = true; continue }
            let attempt = attempts[id, default: 0]
            retryAt[id] = now().addingTimeInterval([30.0, 60, 120, 300][min(attempt, 3)])
            attempts[id] = attempt + 1; attempted = true
        }
        if needsScan && now() >= nextScan {
            transport.scanForRemembered(); nextScan = now().addingTimeInterval(30)
        }
        status = attempted ? "Connecting app controls…" : limitSignal ? "Waiting for a stronger Bluetooth signal." : "Waiting for your hearing aids."
    }
}

struct ConnectionSessionSnapshot {
    let onConsole: Bool
    let displayAwake: Bool
    let screenLocked: Bool?
    let foregroundBundle: String?
    var isUnlocked: Bool {
        guard onConsole, displayAwake else { return false }
        if let screenLocked { return !screenLocked }
        // macOS normally omits the lock flag in an unlocked session.
        return foregroundBundle != nil && foregroundBundle != "com.apple.loginwindow"
    }
}

/// Workspace sleep/session events plus macOS screen-lock notifications. No
/// Accessibility, screen recording, login-item or Bluetooth power permission.
@MainActor private final class ConnectionSessionObserver {
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private let changed: (Bool) -> Void
    private var blockedUntil = Date.distantPast
    var isUnlocked: Bool {
        guard Date() >= blockedUntil, let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return ConnectionSessionSnapshot(onConsole: session[kCGSessionOnConsoleKey as String] as? Bool == true,
            displayAwake: CGDisplayIsAsleep(CGMainDisplayID()) == 0,
            screenLocked: session["CGSSessionScreenIsLocked"] as? Bool,
            foregroundBundle: NSWorkspace.shared.frontmostApplication?.bundleIdentifier).isUnlocked
    }
    init(changed: @escaping (Bool) -> Void) {
        self.changed = changed
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observe(workspace, name) { [weak self] in self?.blockedUntil = Date().addingTimeInterval(2); self?.changed(false) }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(workspace, name) { [weak self] in guard let self else { return }; self.blockedUntil = .distantPast; self.changed(self.isUnlocked) }
        }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, .init("com.apple.screenIsLocked")) { [weak self] in
            self?.blockedUntil = Date().addingTimeInterval(2); self?.changed(false)
        }
        observe(distributed, .init("com.apple.screenIsUnlocked")) { [weak self] in
            guard let self else { return }
            self.blockedUntil = .distantPast; self.changed(self.isUnlocked)
        }
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in Task { @MainActor in action() } }
        tokens.append((center, token))
    }
}
