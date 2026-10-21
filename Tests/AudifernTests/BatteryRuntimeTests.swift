import CompanionCore
import Foundation
import QuickAccessKit
import Testing
@testable import Audifern

@Test func batteryRuntimeCountsDownWithoutChangingItsMeasurementAndExpires() {
    let date = Date(timeIntervalSince1970: 100_000)
    let reading = BatteryRuntimeReading(percentage: 50, measuredAt: date, secondsAtMeasurement: 43_200, isCharging: false, isCharged: false)
    #expect(reading.remainingSeconds(at: date + 3_600) == 39_600)
    #expect(reading.measuredAt == date)
    #expect(reading.remainingSeconds(at: date - 1) == nil)
    #expect(reading.remainingSeconds(at: date + 7_201) == nil)
    let exhausted = BatteryRuntimeReading(percentage: 1, measuredAt: date, secondsAtMeasurement: 5, isCharging: false, isCharged: false)
    #expect(exhausted.remainingSeconds(at: date + 10) == 0)
}

@MainActor @Test func cachedBatterySurvivesRelaunchAndBadZeroReadsDoNotRenewItsAge() throws {
    let suite = "org.audifern.tests.battery-runtime-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let id = UUID(), other = UUID(), date = Date(timeIntervalSince1970: 100_000)
    var now = date
    let cache = BatteryRuntimeCache(defaults: defaults, now: { now })
    let service = UTLProtocol.Service(id: OticonBattery.serviceID, handle: 7, major: 2, minor: 0, status: 255)
    let good = try OticonBattery.fastState(Data([0, 0, 0, 50, 0, 0, 0x2E, 0xE0, 0, 0, 3, 0xE8, 0x40]), service: service)
    let zero = try OticonBattery.fastState(Data([UInt8](repeating: 0, count: 13)), service: service)
    cache.record(good, for: id)
    now += 3_600
    cache.record(zero, for: id)
    let restarted = BatteryRuntimeCache(defaults: defaults, now: { now })
    #expect(restarted.reading(for: id)?.measuredAt == date)
    #expect(restarted.reading(for: id)?.remainingSeconds(at: now) == 39_600)
    #expect(restarted.reading(for: other) == nil)
    now += 3_601
    #expect(restarted.reading(for: id) == nil)
}

@Test func chargingAndUnknownRuntimeNeverProduceACountdownFromPercentage() {
    let now = Date()
    for sample in [
        BatteryRuntimeReading(percentage: 80, measuredAt: now, secondsAtMeasurement: nil, isCharging: false, isCharged: false),
        BatteryRuntimeReading(percentage: 80, measuredAt: now, secondsAtMeasurement: 8_000, isCharging: true, isCharged: false),
        BatteryRuntimeReading(percentage: 100, measuredAt: now, secondsAtMeasurement: 8_000, isCharging: false, isCharged: true),
        BatteryRuntimeReading(percentage: 101, measuredAt: now, secondsAtMeasurement: 8_000, isCharging: false, isCharged: false)
    ] { #expect(sample.remainingSeconds(at: now) == nil) }
}
