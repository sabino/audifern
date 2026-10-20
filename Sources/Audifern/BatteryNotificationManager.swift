import Combine
import CompanionCore
import Foundation
import UserNotifications

enum BatteryNotificationPermission: Equatable, Sendable {
    case checking, notRequested, allowed, quietlyAllowed, denied, alertsDisabled, unavailable

    var canDeliver: Bool { self == .allowed || self == .quietlyAllowed }
    var label: String {
        switch self {
        case .checking: "Checking macOS permission…"
        case .notRequested: "macOS permission has not been requested."
        case .allowed: "Notifications are allowed by macOS."
        case .quietlyAllowed: "macOS permits quiet notifications."
        case .denied: "Notifications are blocked in macOS Settings."
        case .alertsDisabled: "Notification alerts are turned off in macOS Settings."
        case .unavailable: "Notification permission is unavailable."
        }
    }
}

struct BatteryLocalNotification: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let playSound: Bool
}

@MainActor
protocol BatteryNotificationDelivery: AnyObject {
    func permission() async -> BatteryNotificationPermission
    func requestPermission() async throws -> Bool
    func containsNotification(identifier: String) async -> Bool
    func deliver(_ notification: BatteryLocalNotification) async throws
    func cancelPendingBatteryNotifications() async
}

@MainActor
final class SystemBatteryNotificationDelivery: NSObject, BatteryNotificationDelivery, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter

    override init() {
        center = .current()
        super.init()
        center.delegate = self
    }

    func permission() async -> BatteryNotificationPermission {
        // Older SDKs do not mark UserNotifications objects Sendable. Convert
        // them within the callback so only value types cross the actor boundary.
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                let permission: BatteryNotificationPermission
                switch settings.authorizationStatus {
                case .notDetermined: permission = .notRequested
                case .denied: permission = .denied
                case .authorized: permission = settings.alertSetting == .disabled ? .alertsDisabled : .allowed
                case .provisional: permission = .quietlyAllowed
                @unknown default: permission = .unavailable
                }
                continuation.resume(returning: permission)
            }
        }
    }

    func requestPermission() async throws -> Bool {
        // Called only from the user's Enable action; never on launch or from a BLE update.
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func containsNotification(identifier: String) async -> Bool {
        if await deliveredIdentifiers().contains(identifier) { return true }
        return await pendingIdentifiers().contains(identifier)
    }

    func deliver(_ notification: BatteryLocalNotification) async throws {
        try Task.checkCancellation()
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        if notification.playSound { content.sound = .default }
        try await center.add(UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil))
    }

    func cancelPendingBatteryNotifications() async {
        let identifiers = await pendingIdentifiers()
        center.removePendingNotificationRequests(withIdentifiers: identifiers.filter { $0.hasPrefix("battery-alert-") })
    }

    private func deliveredIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications.map { $0.request.identifier })
            }
        }
    }

    private func pendingIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // The request has a sound only if the user enabled it. Foreground use retains native banners.
        [.banner, .list, .sound]
    }
}

@MainActor
protocol BatteryNotificationPersistence {
    func load() throws -> BatteryAlertArchive
    func save(_ archive: BatteryAlertArchive) throws
}

struct BatteryNotificationFile: BatteryNotificationPersistence {
    let file: URL

    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audifern", isDirectory: true).appendingPathComponent("battery-alerts.json")
    }

    func load() throws -> BatteryAlertArchive {
        try refuseSymbolicLinks()
        guard FileManager.default.fileExists(atPath: file.path) else { return BatteryAlertArchive() }
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw BatteryAlertStorageError.insecurePath }
        guard (values.fileSize ?? 0) <= 131_072 else { throw BatteryAlertStorageError.tooLarge }
        return try BatteryAlertArchive.decode(Data(contentsOf: file))
    }

    func save(_ archive: BatteryAlertArchive) throws {
        let data = try archive.encoded()
        try refuseSymbolicLinks()
        let manager = FileManager.default
        let folder = file.deletingLastPathComponent()
        try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let temporary = folder.appendingPathComponent(".battery-alerts-\(UUID().uuidString).tmp")
        guard manager.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? manager.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.write(contentsOf: data); try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); throw error }
        if manager.fileExists(atPath: file.path) { _ = try manager.replaceItemAt(file, withItemAt: temporary) }
        else { try manager.moveItem(at: temporary, to: file) }
    }

    private func refuseSymbolicLinks() throws {
        for url in [file.deletingLastPathComponent(), file] {
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw BatteryAlertStorageError.insecurePath
            }
        }
    }
}

/// Consumes confirmed battery updates; never scans, polls, connects, or requests permission on launch.
@MainActor
final class BatteryNotificationManager: ObservableObject {
    @Published private(set) var configuration = BatteryAlertConfiguration()
    @Published private(set) var permission: BatteryNotificationPermission = .checking
    @Published private(set) var isRequestingPermission = false
    @Published private(set) var pendingDeviceCount = 0
    @Published private(set) var error: String?
    @Published private(set) var loadFailed = false

    private struct Observation { let side: BatteryAlertSide; let percentage: Int }
    private var latest: [UUID: Observation] = [:]
    private var archive = BatteryAlertArchive()
    private let delivery: any BatteryNotificationDelivery
    private let persistence: any BatteryNotificationPersistence
    private var deliveryTasks: [UUID: Task<Void, Never>] = [:]
    private var failedAt: [UUID: Date] = [:]
    private var acceptedIdentifiers = Set<String>()

    init(delivery: (any BatteryNotificationDelivery)? = nil,
         persistence: (any BatteryNotificationPersistence)? = nil, refreshPermissionOnInit: Bool = true) {
        self.delivery = delivery ?? SystemBatteryNotificationDelivery()
        self.persistence = persistence ?? BatteryNotificationFile()
        do {
            archive = try self.persistence.load().validated()
            configuration = archive.configuration
            updatePendingCount()
        } catch {
            loadFailed = true
            self.error = "Could not read battery alert settings. The saved file was left unchanged."
        }
        if refreshPermissionOnInit { Task { await refreshPermission(retryPending: false) } }
    }

    func observe(deviceID: UUID, side: BatteryAlertSide, percentage: Int) {
        guard (0...100).contains(percentage) else { return }
        latest[deviceID] = Observation(side: side, percentage: percentage)
        guard !loadFailed, configuration.enabled, configuration.sides.contains(side) else { return }
        if let state = archive.devices[deviceID.uuidString], state.lastPercentage == percentage, state.pendingThresholds.isEmpty {
            return
        }
        var updated = archive
        var state = updated.devices[deviceID.uuidString] ?? BatteryAlertDeviceState()
        state.observe(percentage: percentage, enabledThresholds: configuration.thresholds)
        updated.devices[deviceID.uuidString] = state
        guard updated == archive || persist(updated) else { return }
        scheduleDelivery(for: deviceID)
    }

    /// Call before feeding connected readings. Going offline clears live values, not recharge/dedup history.
    func retainConnectedDevices(_ deviceIDs: Set<UUID>) {
        for id in Array(latest.keys) where !deviceIDs.contains(id) { latest.removeValue(forKey: id) }
        for (id, task) in deliveryTasks where !deviceIDs.contains(id) { task.cancel() }
        failedAt = failedAt.filter { deviceIDs.contains($0.key) }
        // Accepted request identifiers are intentionally retained. A request accepted just before
        // disconnect still needs acknowledgment; reconnect must not turn it into a second alert.
    }

    func setEnabled(_ enabled: Bool) async {
        guard !loadFailed, !isRequestingPermission else { return }
        var updated = archive; updated.configuration.enabled = enabled
        guard persist(updated) else { return }
        if !enabled {
            for task in deliveryTasks.values { task.cancel() }
            await delivery.cancelPendingBatteryNotifications()
            return
        }
        isRequestingPermission = true
        defer { isRequestingPermission = false }
        do {
            _ = try await delivery.requestPermission()
            permission = await delivery.permission()
            error = nil
            processLatest()
        } catch { self.error = "macOS notification permission could not be requested. Try enabling alerts again." }
    }

    func setThreshold(_ threshold: BatteryAlertThreshold, enabled: Bool) {
        var updated = archive
        if enabled { updated.configuration.thresholds.insert(threshold) }
        else { updated.configuration.thresholds.remove(threshold) }
        if persist(updated) { processLatest() }
    }

    func setSide(_ side: BatteryAlertSide, enabled: Bool) {
        var updated = archive
        if enabled { updated.configuration.sides.insert(side) }
        else { updated.configuration.sides.remove(side) }
        if persist(updated) { processLatest() }
    }

    func setPlaySound(_ enabled: Bool) {
        var updated = archive; updated.configuration.playSound = enabled
        _ = persist(updated)
    }

    func refreshPermission(retryPending: Bool = true) async {
        permission = await delivery.permission()
        if retryPending { retryPendingAlerts() }
    }

    func retryPendingAlerts() {
        failedAt = [:]
        processLatest()
    }

    /// Only the explicit Settings button calls this; it does not change threshold history.
    func sendTestNotification() async {
        guard configuration.enabled, !loadFailed else { return }
        permission = await delivery.permission()
        guard permission.canDeliver else { return }
        do {
            try await delivery.deliver(.init(identifier: "battery-alert-test-\(UUID().uuidString)", title: "Battery alerts are ready",
                                             body: "Audifern will notify you at your selected battery levels.",
                                             playSound: configuration.playSound))
            error = nil
        } catch { self.error = "The test notification could not be delivered. Your battery alert history is unchanged." }
    }

    /// Also used by deterministic tests; no timers or repeated polling are created by this manager.
    func waitForPendingDeliveries() async {
        while !deliveryTasks.isEmpty {
            for task in Array(deliveryTasks.values) { await task.value }
        }
    }

    private func processLatest() {
        for (id, reading) in latest { observe(deviceID: id, side: reading.side, percentage: reading.percentage) }
    }

    @discardableResult
    private func persist(_ updated: BatteryAlertArchive) -> Bool {
        guard !loadFailed else { return false }
        do {
            try persistence.save(updated)
            archive = updated; configuration = updated.configuration; updatePendingCount()
            error = nil
            return true
        } catch {
            self.error = "Could not save battery alert settings. The previous file was preserved and new alerts are paused."
            return false
        }
    }

    private func updatePendingCount() {
        pendingDeviceCount = archive.devices.values.filter { $0.pendingDecision(enabledThresholds: configuration.thresholds) != nil }.count
    }

    private func scheduleDelivery(for id: UUID) {
        guard deliveryTasks[id] == nil,
              permission.canDeliver || permission == .checking,
              failedAt[id].map({ Date().timeIntervalSince($0) >= 30 }) ?? true,
              archive.devices[id.uuidString]?.pendingDecision(enabledThresholds: configuration.thresholds) != nil else { return }
        deliveryTasks[id] = Task { [weak self] in
            guard let self else { return }
            await self.deliverPending(for: id)
            self.deliveryTasks[id] = nil
            if Task.isCancelled, self.latest[id] != nil, self.configuration.enabled {
                // A quick reconnect can arrive while a cancelled delivery is finishing. Resume its
                // current, confirmed reading only after that task releases the per-device slot.
                self.scheduleDelivery(for: id)
            }
        }
    }

    private func deliverPending(for id: UUID) async {
        permission = await delivery.permission()
        guard permission.canDeliver else { return }
        while !Task.isCancelled, configuration.enabled, let reading = latest[id], configuration.sides.contains(reading.side),
              let decision = archive.devices[id.uuidString]?.pendingDecision(enabledThresholds: configuration.thresholds) {
            let identifier = "battery-alert-\(id.uuidString)-\(decision.cycle.uuidString)-\(decision.threshold.rawValue)"
            do {
                let alreadyAccepted: Bool
                if acceptedIdentifiers.contains(identifier) { alreadyAccepted = true }
                else { alreadyAccepted = await delivery.containsNotification(identifier: identifier) }
                try Task.checkCancellation()
                // Permission/status queries can yield while a newer reading cancels the old milestone.
                guard configuration.enabled, configuration.sides.contains(reading.side),
                      archive.devices[id.uuidString]?.pendingDecision(enabledThresholds: configuration.thresholds) == decision else { continue }
                if !alreadyAccepted {
                    try await delivery.deliver(.init(identifier: identifier, title: "\(reading.side.label) battery: \(decision.percentage)%",
                                                     body: decision.threshold == .low ? "Low battery. Charge soon." : "Charge when convenient.",
                                                     playSound: configuration.playSound))
                }
                acceptedIdentifiers.insert(identifier)
                var updated = archive
                guard var state = updated.devices[id.uuidString] else { return }
                if state.markDelivered(decision) {
                    updated.devices[id.uuidString] = state
                    guard persist(updated) else { failedAt[id] = Date(); return }
                }
                failedAt.removeValue(forKey: id)
            } catch is CancellationError { return }
            catch {
                failedAt[id] = Date()
                self.error = "A battery notification could not be delivered. It will retry on a later reading, or choose Retry pending alerts."
                return
            }
        }
    }
}
