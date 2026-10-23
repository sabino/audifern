import Foundation
import Testing
@testable import Audifern

@MainActor private final class AutomationClock {
    var date = Date(timeIntervalSince1970: 10_000)
}
@MainActor private final class AutomationTransport: AutomaticConnectionTransport {
    var automationPoweredOn = false
    var automationPhases: [UUID: ConnectionPhase] = [:]
    var automationSignals: [UUID: ConnectionSignal] = [:]
    var automationCurrentAids: [RememberedHearingAid] = []
    var available = Set<UUID>()
    var requested: [UUID] = []
    var retrieved: [[UUID]] = []
    var scans = 0
    var stops = 0
    var disconnects = 0
    var measurements = 0
    func retrieveRemembered(_ ids: [UUID]) { retrieved.append(ids) }
    func scanForRemembered() { scans += 1 }
    func stopAutomaticScan() { stops += 1 }
    func connectRemembered(_ id: UUID) -> Bool {
        guard available.contains(id) else { return false }
        requested.append(id); automationPhases[id] = .connecting; return true
    }
    func disconnectAutomaticConnections() { disconnects += 1; automationPhases = [:] }
    func measureConnectedSignal() { measurements += 1 }
}
@MainActor private final class AutomationAudio: MacAudioOutputClient {
    var routes: [MacAudioOutput] = [.init(id: "speakers", name: "Synthetic speakers"), .init(id: "aids", name: "Synthetic aids"), .init(id: "other", name: "Synthetic output")]
    var current = "speakers"
    var selected: [String] = []
    var acceptsSelection = true
    func outputs() -> [MacAudioOutput] { routes }
    func currentOutput() -> String? { current }
    func selectOutput(_ uid: String) -> Bool {
        selected.append(uid)
        guard acceptsSelection, routes.contains(where: { $0.id == uid }) else { return false }
        current = uid; return true
    }
}
@MainActor private final class AutomationFixture {
    let suite = "org.audifern.tests.connection-" + UUID().uuidString
    let defaults: UserDefaults
    let transport = AutomationTransport()
    let audio = AutomationAudio()
    let clock = AutomationClock()
    let aids = [RememberedHearingAid(id: UUID(), side: "Left"), RememberedHearingAid(id: UUID(), side: "Right")]
    let automation: ConnectionAutomation
    init(readSession: (() -> Bool)? = nil) throws {
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(try JSONEncoder().encode(aids), forKey: "autoConnectionKnownAids")
        transport.available = Set(aids.map(\.id))
        let clock = clock
        automation = ConnectionAutomation(defaults: defaults, transport: transport, audio: audio,
            now: { clock.date }, runTimer: false, observeSession: false, readSession: readSession)
    }
    func clean() { defaults.removePersistentDomain(forName: suite) }
    func connected() { transport.automationPhases = Dictionary(uniqueKeysWithValues: aids.map { ($0.id, .connected) }) }
    func failed() { transport.automationPhases = Dictionary(uniqueKeysWithValues: aids.map { ($0.id, .failed) }) }
}

@MainActor private final class SessionProbe { var unlocked = false }

@Test func currentSessionSnapshotRequiresAnAwakeUnlockedConsole() {
    #expect(ConnectionSessionSnapshot(onConsole: true, displayAwake: true, screenLocked: nil, foregroundBundle: "com.apple.finder").isUnlocked)
    #expect(!ConnectionSessionSnapshot(onConsole: true, displayAwake: true, screenLocked: true, foregroundBundle: "com.apple.finder").isUnlocked)
    #expect(!ConnectionSessionSnapshot(onConsole: true, displayAwake: false, screenLocked: false, foregroundBundle: "com.apple.finder").isUnlocked)
    #expect(!ConnectionSessionSnapshot(onConsole: false, displayAwake: true, screenLocked: false, foregroundBundle: "com.apple.finder").isUnlocked)
    #expect(!ConnectionSessionSnapshot(onConsole: true, displayAwake: true, screenLocked: nil, foregroundBundle: "com.apple.loginwindow").isUnlocked)
    #expect(!ConnectionSessionSnapshot(onConsole: true, displayAwake: true, screenLocked: nil, foregroundBundle: nil).isUnlocked)
}

@MainActor @Test func reconnectRecoversAMissedUnlockNotificationAndStillStopsWhileLocked() throws {
    let session = SessionProbe()
    let f = try AutomationFixture(readSession: { session.unlocked }); defer { f.clean() }
    f.transport.automationPoweredOn = true; f.automation.enabled = true; f.automation.releaseOnLock = true
    f.automation.tick()
    #expect(f.transport.requested.isEmpty && f.automation.status == "Waiting for this Mac to unlock.")
    // No notification: the next background tick must read the actual session.
    session.unlocked = true; f.automation.tick()
    #expect(f.transport.requested.count == 2)
    f.connected(); f.automation.tick()
    session.unlocked = false; f.automation.tick(); f.automation.tick()
    #expect(f.transport.disconnects == 1 && f.transport.requested.count == 2)
    session.unlocked = true; f.automation.tick()
    #expect(f.transport.requested.count == 4)
}

@MainActor @Test func explicitReconnectCanDiscoverRememberedAidsWithAutomationOffAndExpires() throws {
    let f = try AutomationFixture(); defer { f.clean() }
    f.transport.automationPoweredOn = true; f.transport.available = []
    f.automation.connectNow()
    #expect(!f.automation.enabled && f.transport.scans == 1 && f.transport.requested.isEmpty)
    f.clock.date += 4; f.transport.available = Set(f.aids.map(\.id)); f.automation.tick()
    #expect(f.transport.requested.count == 2)
    f.failed(); f.clock.date += 21; f.automation.tick()
    f.clock.date += 1_000; f.automation.tick()
    #expect(f.transport.requested.count == 2 && f.transport.scans == 1 && !f.automation.enabled)
}

@MainActor @Test func connectionAutomationDefaultsOffAndDisablingItStopsAllAutomaticActions() throws {
    let f = try AutomationFixture(); defer { f.clean() }
    f.transport.automationPoweredOn = true
    f.automation.releaseOnLock = true; f.automation.restoreAudioOnLock = true
    f.automation.tick(); f.automation.sessionChanged(unlocked: false)
    #expect(!f.automation.enabled && f.transport.requested.isEmpty && f.transport.scans == 0 && f.transport.disconnects == 0)
    #expect(f.audio.selected.isEmpty)
    f.automation.enabled = true; f.automation.sessionChanged(unlocked: true)
    #expect(Set(f.transport.requested) == Set(f.aids.map(\.id)))
    f.failed(); f.automation.enabled = false; f.clock.date += 1_000; f.automation.tick()
    #expect(f.transport.requested.count == 2)
}

@MainActor @Test func automaticConnectionsUseOnlyChosenIDsAndBackOffWithoutScanningCachedDevices() throws {
    let f = try AutomationFixture(); defer { f.clean() }
    let stranger = UUID(); f.transport.available.insert(stranger)
    f.automation.enabled = true; f.transport.automationPoweredOn = true; f.automation.tick()
    #expect(Set(f.transport.requested) == Set(f.aids.map(\.id)))
    #expect(!f.transport.requested.contains(stranger) && f.transport.scans == 0)
    for delay in [30.0, 60, 120, 300] {
        f.failed(); let count = f.transport.requested.count
        f.clock.date += delay - 1; f.automation.tick(); #expect(f.transport.requested.count == count)
        f.clock.date += 1; f.automation.tick(); #expect(f.transport.requested.count == count + 2)
    }
    f.connected(); let count = f.transport.requested.count
    f.clock.date += 1_000; f.automation.tick()
    #expect(f.transport.requested.count == count && f.transport.scans == 0 && f.audio.selected.isEmpty)
}

@MainActor @Test func freshPerEarSignalIsRequiredAndAnUnknownOrStaleSignalCannotReconnect() throws {
    let f = try AutomationFixture(); defer { f.clean() }
    f.automation.limitSignal = true; f.automation.minimumRSSI = -70; f.automation.enabled = true
    f.transport.automationSignals = [f.aids[0].id: .init(rssi: -80, measuredAt: f.clock.date),
        f.aids[1].id: .init(rssi: -60, measuredAt: f.clock.date - 13), UUID(): .init(rssi: -40, measuredAt: f.clock.date)]
    f.transport.automationPoweredOn = true; f.automation.tick()
    #expect(f.transport.requested.isEmpty && f.transport.scans == 1)
    f.transport.automationSignals[f.aids[1].id] = .init(rssi: 127, measuredAt: f.clock.date)
    f.automation.tick(); #expect(f.transport.requested.isEmpty)
    f.transport.automationSignals[f.aids[1].id] = .init(rssi: -60, measuredAt: f.clock.date)
    f.automation.tick(); #expect(f.transport.requested == [f.aids[1].id])
    f.transport.automationSignals[f.aids[0].id] = .init(rssi: -65, measuredAt: f.clock.date)
    f.automation.tick(); #expect(Set(f.transport.requested) == Set(f.aids.map(\.id)))
}

@MainActor @Test func anUncachedAidScansInShortSeparatedWindowsAndConnectsAfterDiscovery() throws {
    let f = try AutomationFixture(); defer { f.clean() }
    f.transport.available = []; f.automation.enabled = true; f.transport.automationPoweredOn = true
    f.automation.tick(); #expect(f.transport.scans == 1 && f.transport.requested.isEmpty)
    f.clock.date += 29; f.automation.tick(); #expect(f.transport.scans == 1)
    f.clock.date += 1; f.automation.tick(); #expect(f.transport.scans == 2)
    f.transport.available = Set(f.aids.map(\.id)); f.clock.date += 5; f.automation.tick()
    #expect(f.transport.requested.count == 2)
}

@MainActor @Test func manualPauseSurvivesUnlockAndRelaunchAndManualConnectExplicitlyResumes() throws {
    let f = try AutomationFixture(); defer { f.clean() }
    f.automation.enabled = true; f.transport.automationPoweredOn = true; f.automation.tick()
    f.automation.pause(); #expect(f.transport.disconnects == 1)
    f.clock.date += 1_000; f.automation.sessionChanged(unlocked: false); f.automation.sessionChanged(unlocked: true)
    #expect(f.transport.requested.count == 2 && f.automation.paused)
    let relaunched = ConnectionAutomation(defaults: f.defaults, transport: f.transport, audio: f.audio,
        now: { f.clock.date }, runTimer: false, observeSession: false)
    #expect(relaunched.paused && f.transport.requested.count == 2)
    f.automation.manualConnectionRequested(); #expect(!f.automation.paused && f.transport.requested.count == 4)
}

@MainActor @Test func unlockOnlyModeHasABoundedWindowAndNeverConnectsWhileLocked() throws {
    let f = try AutomationFixture(); defer { f.clean() }
    f.automation.whenNearby = false; f.automation.enabled = true
    f.automation.sessionChanged(unlocked: false); f.transport.automationPoweredOn = true; f.automation.tick()
    #expect(f.transport.requested.isEmpty)
    f.automation.sessionChanged(unlocked: true); #expect(f.transport.requested.count == 2)
    f.failed(); f.clock.date += 46; f.automation.tick(); #expect(f.transport.requested.count == 2)
    f.automation.sessionChanged(unlocked: false); f.automation.sessionChanged(unlocked: true)
    #expect(f.transport.requested.count == 4)
}

@MainActor @Test func forgettingTargetsCannotBeUndoneByChangingAnotherPreference() throws {
    let f = try AutomationFixture(); defer { f.clean() }
    f.transport.automationCurrentAids = f.aids; f.automation.enabled = true
    f.automation.forgetAids(); f.automation.minimumRSSI = -60
    #expect(f.automation.remembered.isEmpty && f.defaults.data(forKey: "autoConnectionKnownAids") == nil)
    f.transport.automationCurrentAids = [f.aids[0], f.aids[0]]
    #expect(!f.automation.useConnectedAids() && f.automation.remembered.isEmpty)
    f.transport.automationCurrentAids = f.aids
    #expect(f.automation.useConnectedAids() && f.automation.remembered == f.aids)
}

@MainActor @Test func disablingBothTriggersDoesNotReconnectAfterAnUnlock() throws {
    let f = try AutomationFixture(); defer { f.clean() }
    f.automation.whenNearby = false; f.automation.afterUnlock = false
    f.automation.enabled = true; f.transport.automationPoweredOn = true
    f.automation.sessionChanged(unlocked: false); f.automation.sessionChanged(unlocked: true)
    #expect(f.transport.requested.isEmpty && f.transport.scans == 0)
    #expect(f.automation.status == "Choose a reconnect trigger.")
}

@MainActor @Test func audioRoutingNeedsAnExplicitPreferenceAndAnAvailableOutput() throws {
    let f = try AutomationFixture(); defer { f.clean() }
    f.connected(); f.automation.preferredOutputUID = "aids"; f.automation.enabled = true
    f.transport.automationPoweredOn = true; f.automation.tick(); #expect(f.audio.selected.isEmpty)
    f.audio.routes.removeAll { $0.id == "aids" }; f.automation.preferMacAudio = true
    f.automation.tick(); #expect(f.audio.selected.isEmpty)
    f.audio.routes.append(.init(id: "aids", name: "Synthetic aids")); f.automation.tick()
    #expect(f.audio.selected == ["aids"])
    f.automation.tick(); #expect(f.audio.selected == ["aids"])
    f.audio.current = "other"; f.automation.tick(); #expect(f.audio.current == "other")
    f.automation.restoreAudioOnLock = true; f.automation.sessionChanged(unlocked: false)
    #expect(f.audio.current == "other" && f.audio.selected == ["aids"])
}

@MainActor @Test func lockingRestoresOnlyAnAudioRouteOwnedByAudifernAndCanReleaseItsControls() throws {
    let f = try AutomationFixture(); defer { f.clean() }
    f.connected(); f.automation.preferredOutputUID = "aids"; f.automation.preferMacAudio = true
    f.automation.restoreAudioOnLock = true; f.automation.releaseOnLock = true; f.automation.enabled = true
    f.transport.automationPoweredOn = true; f.automation.tick(); #expect(f.audio.current == "aids")
    f.automation.sessionChanged(unlocked: false)
    #expect(f.audio.current == "speakers" && f.audio.selected == ["aids", "speakers"] && f.transport.disconnects == 1)
    let count = f.transport.requested.count; f.automation.tick(); #expect(f.transport.requested.count == count)
}

@MainActor @Test func failedAudioSelectionDoesNotLoopAndLeavesThePreviousOutputIntact() throws {
    let f = try AutomationFixture(); defer { f.clean() }
    f.connected(); f.automation.preferredOutputUID = "aids"; f.automation.preferMacAudio = true
    f.audio.acceptsSelection = false; f.automation.enabled = true; f.transport.automationPoweredOn = true
    f.automation.tick(); f.automation.tick(); f.automation.tick()
    #expect(f.automation.audioError && f.audio.selected == ["aids"] && f.audio.current == "speakers")
    f.audio.acceptsSelection = true; f.automation.usePreferredAudio(); #expect(f.audio.current == "aids")
}

@MainActor @Test func signalCalibrationAcceptsAFreshAsyncReadingAndExpiresUnansweredRequests() throws {
    let f = try AutomationFixture(); defer { f.clean() }
    f.transport.automationSignals = Dictionary(uniqueKeysWithValues: f.aids.map { ($0.id, .init(rssi: -80, measuredAt: f.clock.date - 5)) })
    f.automation.calibrateSignal(); #expect(f.transport.measurements == 1 && f.automation.minimumRSSI == -70)
    f.transport.automationSignals = Dictionary(uniqueKeysWithValues: f.aids.map { ($0.id, .init(rssi: -63, measuredAt: f.clock.date)) })
    f.automation.tick(); #expect(f.automation.minimumRSSI == -63)
    f.transport.automationSignals = [:]; f.automation.calibrateSignal(); f.clock.date += 11
    f.transport.automationSignals = Dictionary(uniqueKeysWithValues: f.aids.map { ($0.id, .init(rssi: -40, measuredAt: f.clock.date)) })
    f.automation.tick(); #expect(f.automation.minimumRSSI == -63)
}

@MainActor @Test func explicitQuickReconnectWorksWithAutomationDisabledAndRespectsTheLockedSession() throws {
    let f = try AutomationFixture(); defer { f.clean() }
    f.transport.automationPoweredOn = true
    f.automation.connectNow()
    #expect(!f.automation.enabled && Set(f.transport.requested) == Set(f.aids.map(\.id)))
    f.failed(); f.transport.requested = []
    f.automation.sessionChanged(unlocked: false)
    f.automation.connectNow()
    #expect(f.transport.requested.isEmpty)
}

@MainActor @Test func deliberateFallbackAudioSelectionIsNotImmediatelyUndoneByAutomaticRouting() throws {
    let f = try AutomationFixture(); defer { f.clean() }
    f.connected(); f.transport.automationPoweredOn = true
    f.automation.preferredOutputUID = "aids"; f.automation.fallbackOutputUID = "speakers"
    f.automation.preferMacAudio = true; f.automation.enabled = true
    #expect(f.audio.current == "aids" && f.automation.canSwitchAudio)
    f.automation.setMacAudio(false)
    #expect(f.audio.current == "speakers" && !f.automation.macAudioSelected)
    f.automation.tick()
    #expect(f.audio.current == "speakers")
    f.audio.routes.removeAll { $0.id == "aids" }
    f.automation.refreshAudio()
    #expect(!f.automation.canSwitchAudio)
    f.automation.setMacAudio(true)
    #expect(f.audio.current == "speakers" && f.automation.audioError)
}

@MainActor @Test func manualPairCanBeRememberedWithoutEnablingAutomaticReconnectAndForgetStaysForgotten() throws {
    let f = try AutomationFixture(); defer { f.clean() }
    f.automation.forgetAids(); f.connected()
    f.automation.manualConnectionRequested()
    f.transport.automationCurrentAids = f.aids
    f.automation.connectionStateChanged()
    #expect(f.automation.remembered == f.aids && !f.automation.enabled)
    f.automation.forgetAids(); f.automation.connectionStateChanged()
    #expect(f.automation.remembered.isEmpty)
}
