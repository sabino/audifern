import Foundation

/// A timestamped device reading. Percentage is never converted into runtime.
public struct BatteryRuntimeReading: Codable, Equatable, Sendable {
    public static let refreshInterval: TimeInterval = 3_600
    public static let maximumEstimateAge: TimeInterval = 7_200
    public let percentage: Int?
    public let measuredAt: Date
    public let secondsAtMeasurement: TimeInterval?
    public let isCharging: Bool
    public let isCharged: Bool

    public init(percentage: Int?, measuredAt: Date, secondsAtMeasurement: TimeInterval?, isCharging: Bool, isCharged: Bool) {
        self.percentage = percentage; self.measuredAt = measuredAt
        self.secondsAtMeasurement = secondsAtMeasurement; self.isCharging = isCharging; self.isCharged = isCharged
    }
    public func isValid(at now: Date) -> Bool {
        let age = now.timeIntervalSince(measuredAt)
        return age >= 0 && age <= Self.maximumEstimateAge
            && (percentage == nil || (0...100).contains(percentage!))
            && (secondsAtMeasurement == nil || (secondsAtMeasurement!.isFinite && (0...604_800).contains(secondsAtMeasurement!)))
    }
    public func remainingSeconds(at now: Date) -> TimeInterval? {
        guard isValid(at: now), !isCharging, !isCharged, let secondsAtMeasurement else { return nil }
        return max(0, secondsAtMeasurement - floor(now.timeIntervalSince(measuredAt)))
    }
}
