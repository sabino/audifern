import CompanionCore
import Foundation
import Testing
@testable import Audifern

@MainActor
private final class FakeBatteryNotificationDelivery: BatteryNotificationDelivery {
    var status: BatteryNotificationPermission = .allowed
    var requestCount = 0
    var permissionQueries = 0
    var delivered: [BatteryLocalNotification] = []
    var accepted = Set<String>()
    var failDelivery = false
    var onDelivery: (() -> Void)?

    func permission() async -> BatteryNotificationPermission { permissionQueries += 1; return status }
    func requestPermission() async throws -> Bool { requestCount += 1; return status.canDeliver }
    func containsNotification(identifier: String) async -> Bool { accepted.contains(identifier) }
    func deliver(_ notification: BatteryLocalNotification) async throws {
        if failDelivery { throw CocoaError(.fileWriteUnknown) }
        delivered.append(notification); accepted.insert(notification.identifier); onDelivery?()
    }
    func cancelPendingBatteryNotifications() async {}
}

@MainActor
private final class FakeBatteryNotificationPersistence: BatteryNotificationPersistence {
    var archive: BatteryAlertArchive
    var saveCount = 0
    var failSave = false
    var failLoad = false
    init(enabled: Bool = false) { archive = BatteryAlertArchive(configuration: .init(enabled: enabled)) }
    func load() throws -> BatteryAlertArchive {
        if failLoad { throw CocoaError(.fileReadCorruptFile) }
        return archive
    }
    func save(_ archive: BatteryAlertArchive) throws {
        if failSave { throw CocoaError(.fileWriteUnknown) }
        self.archive = archive; saveCount += 1
    }
}

@Test @MainActor func batteryAlertsNeverAskPermissionOrDeliverUntilExplicitEnable() async {
    let delivery = FakeBatteryNotificationDelivery(), persistence = FakeBatteryNotificationPersistence()
    let manager = BatteryNotificationManager(delivery: delivery, persistence: persistence, refreshPermissionOnInit: false)
    let left = UUID(), right = UUID()
    manager.observe(deviceID: left, side: .left, percentage: 9)
    manager.observe(deviceID: right, side: .right, percentage: 8)
    await manager.waitForPendingDeliveries()
    #expect(delivery.requestCount == 0 && delivery.delivered.isEmpty && persistence.saveCount == 0)
    await manager.setEnabled(true)
    await manager.waitForPendingDeliveries()
    #expect(delivery.requestCount == 1)
    #expect(Set(delivery.delivered.map(\.title)) == ["Left battery: 9%", "Right battery: 8%"])
    #expect(delivery.delivered.allSatisfy { !$0.playSound })
    #expect(manager.pendingDeviceCount == 0)

    let relaunchedDelivery = FakeBatteryNotificationDelivery()
    let relaunched = BatteryNotificationManager(delivery: relaunchedDelivery, persistence: persistence, refreshPermissionOnInit: false)
    relaunched.observe(deviceID: left, side: .left, percentage: 9)
    relaunched.observe(deviceID: right, side: .right, percentage: 8)
    await relaunched.waitForPendingDeliveries()
    #expect(relaunchedDelivery.requestCount == 0 && relaunchedDelivery.delivered.isEmpty)
}

@Test @MainActor func failedBatteryDeliveryRemainsPendingAndRetriesWithoutPrematureAcknowledgment() async {
    let delivery = FakeBatteryNotificationDelivery(), persistence = FakeBatteryNotificationPersistence(enabled: true)
    delivery.failDelivery = true
    let manager = BatteryNotificationManager(delivery: delivery, persistence: persistence, refreshPermissionOnInit: false)
    let id = UUID()
    manager.observe(deviceID: id, side: .left, percentage: 80)
    manager.observe(deviceID: id, side: .left, percentage: 30)
    await manager.waitForPendingDeliveries()
    #expect(delivery.delivered.isEmpty)
    #expect(persistence.archive.devices[id.uuidString]?.pendingThresholds.contains(.thirty) == true)
    #expect(persistence.archive.devices[id.uuidString]?.handledThresholds.contains(.thirty) == false)
    delivery.failDelivery = false
    manager.retryPendingAlerts()
    await manager.waitForPendingDeliveries()
    #expect(delivery.delivered.count == 1)
    #expect(delivery.delivered[0].title == "Left battery: 30%")
    #expect(persistence.archive.devices[id.uuidString]?.pendingThresholds.isEmpty == true)
}

@Test @MainActor func blockedBatteryPermissionKeepsAlertsPendingWithoutPromptingAndCanRefresh() async {
    let delivery = FakeBatteryNotificationDelivery(), persistence = FakeBatteryNotificationPersistence(enabled: true)
    delivery.status = .denied
    let manager = BatteryNotificationManager(delivery: delivery, persistence: persistence, refreshPermissionOnInit: false)
    let id = UUID()
    manager.observe(deviceID: id, side: .right, percentage: 80)
    manager.observe(deviceID: id, side: .right, percentage: 20)
    await manager.waitForPendingDeliveries()
    #expect(manager.permission == .denied && manager.pendingDeviceCount == 1)
    #expect(delivery.requestCount == 0 && delivery.delivered.isEmpty)
    let queries = delivery.permissionQueries
    for _ in 0..<30 { manager.observe(deviceID: id, side: .right, percentage: 20) }
    await manager.waitForPendingDeliveries()
    #expect(delivery.permissionQueries == queries)
    delivery.status = .allowed
    await manager.refreshPermission()
    await manager.waitForPendingDeliveries()
    #expect(delivery.requestCount == 0 && delivery.delivered.count == 1)
}

@Test @MainActor func repeatedUnchangedBatteryReadingsDoNotWriteDiskOrPollPermissions() async {
    let delivery = FakeBatteryNotificationDelivery(), persistence = FakeBatteryNotificationPersistence(enabled: true)
    let manager = BatteryNotificationManager(delivery: delivery, persistence: persistence, refreshPermissionOnInit: false)
    let id = UUID()
    manager.observe(deviceID: id, side: .left, percentage: 80)
    for _ in 0..<100 { manager.observe(deviceID: id, side: .left, percentage: 80) }
    #expect(persistence.saveCount == 1 && delivery.permissionQueries == 0)
    manager.observe(deviceID: id, side: .left, percentage: 50)
    await manager.waitForPendingDeliveries()
    let saves = persistence.saveCount, queries = delivery.permissionQueries
    for _ in 0..<100 { manager.observe(deviceID: id, side: .left, percentage: 50) }
    await manager.waitForPendingDeliveries()
    #expect(persistence.saveCount == saves && delivery.permissionQueries == queries && delivery.delivered.count == 1)
}

@Test @MainActor func batterySideAndThresholdSwitchesAreIndependent() async {
    let delivery = FakeBatteryNotificationDelivery(), persistence = FakeBatteryNotificationPersistence(enabled: true)
    persistence.archive.configuration.sides = [.right]
    persistence.archive.configuration.thresholds = [.low]
    let manager = BatteryNotificationManager(delivery: delivery, persistence: persistence, refreshPermissionOnInit: false)
    let left = UUID(), right = UUID()
    manager.observe(deviceID: left, side: .left, percentage: 9)
    manager.observe(deviceID: right, side: .right, percentage: 20)
    #expect(delivery.delivered.isEmpty)
    manager.observe(deviceID: right, side: .right, percentage: 9)
    await manager.waitForPendingDeliveries()
    #expect(delivery.delivered.map(\.title) == ["Right battery: 9%"])
    manager.setSide(.left, enabled: true)
    await manager.waitForPendingDeliveries()
    #expect(delivery.delivered.map(\.title) == ["Right battery: 9%", "Left battery: 9%"])
}

@Test @MainActor func batteryTestNotificationIsExplicitAndDoesNotAlterThresholdHistory() async {
    let delivery = FakeBatteryNotificationDelivery(), persistence = FakeBatteryNotificationPersistence()
    let manager = BatteryNotificationManager(delivery: delivery, persistence: persistence, refreshPermissionOnInit: false)
    manager.observe(deviceID: UUID(), side: .left, percentage: 80)
    await manager.setEnabled(true)
    await manager.waitForPendingDeliveries()
    #expect(delivery.delivered.isEmpty)
    let previous = persistence.archive.devices
    await manager.sendTestNotification()
    #expect(delivery.delivered.count == 1 && delivery.delivered[0].title == "Battery alerts are ready")
    #expect(persistence.archive.devices == previous)
}

@Test @MainActor func offlineBatteryCacheCannotAlertOnEnableAndReconnectRetainsDeliveryHistory() async {
    let delivery = FakeBatteryNotificationDelivery(), persistence = FakeBatteryNotificationPersistence()
    let manager = BatteryNotificationManager(delivery: delivery, persistence: persistence, refreshPermissionOnInit: false)
    let id = UUID()
    manager.observe(deviceID: id, side: .left, percentage: 9)
    manager.retainConnectedDevices([])
    await manager.setEnabled(true)
    await manager.waitForPendingDeliveries()
    #expect(delivery.delivered.isEmpty)
    #expect(persistence.archive.devices.isEmpty)

    manager.retainConnectedDevices([id])
    manager.observe(deviceID: id, side: .left, percentage: 9)
    await manager.waitForPendingDeliveries()
    #expect(delivery.delivered.count == 1)
    let savedHistory = persistence.archive.devices
    await manager.setEnabled(false)
    manager.retainConnectedDevices([])
    await manager.setEnabled(true)
    await manager.waitForPendingDeliveries()
    #expect(delivery.delivered.count == 1)
    manager.retainConnectedDevices([id])
    manager.observe(deviceID: id, side: .left, percentage: 9)
    await manager.waitForPendingDeliveries()
    #expect(delivery.delivered.count == 1 && persistence.archive.devices == savedHistory)
}

@Test @MainActor func batteryPersistenceFailurePreventsNewAlertsAndCorruptSettingsArePreserved() async {
    let delivery = FakeBatteryNotificationDelivery(), persistence = FakeBatteryNotificationPersistence(enabled: true)
    persistence.failSave = true
    let manager = BatteryNotificationManager(delivery: delivery, persistence: persistence, refreshPermissionOnInit: false)
    let id = UUID()
    manager.observe(deviceID: id, side: .left, percentage: 9)
    await manager.waitForPendingDeliveries()
    #expect(delivery.delivered.isEmpty && manager.error != nil && persistence.archive.devices.isEmpty)
    persistence.failSave = false
    manager.retryPendingAlerts()
    await manager.waitForPendingDeliveries()
    #expect(delivery.delivered.count == 1)

    persistence.failLoad = true
    let unreadable = BatteryNotificationManager(delivery: delivery, persistence: persistence, refreshPermissionOnInit: false)
    #expect(unreadable.loadFailed)
    let previous = persistence.archive
    await unreadable.setEnabled(false)
    #expect(persistence.archive == previous)
}

@Test @MainActor func acceptedBatteryNotificationIsNotRepeatedIfHistorySaveNeedsRetry() async {
    let delivery = FakeBatteryNotificationDelivery(), persistence = FakeBatteryNotificationPersistence(enabled: true)
    let manager = BatteryNotificationManager(delivery: delivery, persistence: persistence, refreshPermissionOnInit: false)
    delivery.onDelivery = { persistence.failSave = true }
    let id = UUID()
    manager.observe(deviceID: id, side: .left, percentage: 9)
    await manager.waitForPendingDeliveries()
    #expect(delivery.delivered.count == 1 && manager.pendingDeviceCount == 1)
    persistence.failSave = false
    delivery.onDelivery = nil
    manager.retryPendingAlerts()
    await manager.waitForPendingDeliveries()
    #expect(delivery.delivered.count == 1 && manager.pendingDeviceCount == 0)
}

@Test @MainActor func batteryAlertFileIsPrivateAndRejectsCorruptDataOrSymbolicLinks() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("battery-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("battery.json")
    let persistence = BatteryNotificationFile(file: file)
    #expect(try persistence.load() == BatteryAlertArchive())
    let archive = BatteryAlertArchive(configuration: .init(enabled: true))
    try persistence.save(archive)
    #expect(try persistence.load() == archive)
    let fileAttributes = try FileManager.default.attributesOfItem(atPath: file.path)
    let folderAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect((folderAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    try persistence.save(BatteryAlertArchive())
    #expect(try persistence.load() == BatteryAlertArchive())
    let corrupt = Data("malformed settings".utf8)
    try corrupt.write(to: file)
    #expect(throws: (any Error).self) { try persistence.load() }
    #expect(try Data(contentsOf: file) == corrupt)
    let link = directory.appendingPathComponent("link.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    #expect(throws: (any Error).self) { try BatteryNotificationFile(file: link).save(archive) }
    #expect(try Data(contentsOf: file) == corrupt)
}
