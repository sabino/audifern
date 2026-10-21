import CompanionCore
import Foundation
import QuickAccessKit

@MainActor final class BatteryRuntimeCache {
    private let defaults: UserDefaults
    private let key = "batteryRuntimeReadings"
    private let now: () -> Date
    init(defaults: UserDefaults, now: @escaping () -> Date = Date.init) { self.defaults = defaults; self.now = now }
    private func readings() -> [UUID: BatteryRuntimeReading] {
        guard let bytes = defaults.data(forKey: key), bytes.count <= 32_768,
              let stored = try? JSONDecoder().decode([UUID: BatteryRuntimeReading].self, from: bytes) else { return [:] }
        return stored.filter { $0.value.isValid(at: now()) }
    }
    func reading(for id: UUID) -> BatteryRuntimeReading? { readings()[id] }
    @discardableResult func record(_ telemetry: OticonBattery.State, for id: UUID) -> BatteryRuntimeReading? {
        // Some aids initially return all-zero charge/draw. Keep the last good
        // reading and its original timestamp while the short bounded retry runs.
        guard !telemetry.hasCorruptZeroTelemetry else { return reading(for: id) }
        let sample = BatteryRuntimeReading(percentage: telemetry.percentage, measuredAt: now(),
            secondsAtMeasurement: telemetry.estimatedTimeLeftSeconds,
            isCharging: telemetry.isCharging == true, isCharged: telemetry.chargingDone == true)
        guard sample.isValid(at: now()) else { return reading(for: id) }
        var all = readings(); all[id] = sample
        let recent = all.sorted { $0.value.measuredAt > $1.value.measuredAt }.prefix(8)
        defaults.set(try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: recent.map { ($0.key, $0.value) })), forKey: key)
        return sample
    }
}
