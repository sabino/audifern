import Foundation

public enum BatteryAlertSide: String, CaseIterable, Codable, Sendable {
    case left, right
    public var label: String { rawValue.capitalized }
}

public enum BatteryAlertThreshold: String, CaseIterable, Codable, Sendable {
    case fifty, thirty, twenty, low

    public var percentage: Int {
        switch self { case .fifty: 50; case .thirty: 30; case .twenty: 20; case .low: 10 }
    }
    public var label: String { self == .low ? "Low battery · below 10%" : "\(percentage)%" }
    public var rearmPercentage: Int { percentage + 5 }
    public func isReached(at percentage: Int) -> Bool {
        self == .low ? percentage < self.percentage : percentage <= self.percentage
    }
}

public struct BatteryAlertConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var thresholds: Set<BatteryAlertThreshold>
    public var sides: Set<BatteryAlertSide>
    public var playSound: Bool

    public init(enabled: Bool = false, thresholds: Set<BatteryAlertThreshold> = Set(BatteryAlertThreshold.allCases),
                sides: Set<BatteryAlertSide> = Set(BatteryAlertSide.allCases), playSound: Bool = false) {
        self.enabled = enabled; self.thresholds = thresholds; self.sides = sides; self.playSound = playSound
    }
}

public struct BatteryAlertDecision: Equatable, Sendable {
    public let threshold: BatteryAlertThreshold
    public let percentage: Int
    public let cycle: UUID
    /// A large downward jump produces one current alert, covering earlier milestones.
    public let coveredThresholds: Set<BatteryAlertThreshold>
}

/// Per-device history. Keep this across disconnects; missing readings never mean 0%.
/// A first reading above30% establishes a baseline rather than inventing a50% crossing.
/// Already-low first readings produce one most-urgent enabled alert, not a burst.
public struct BatteryAlertDeviceState: Codable, Equatable, Sendable {
    public private(set) var lastPercentage: Int?
    public private(set) var handledThresholds: Set<BatteryAlertThreshold>
    public private(set) var pendingThresholds: Set<BatteryAlertThreshold>
    public private(set) var cycle: UUID

    public init() {
        lastPercentage = nil; handledThresholds = []; pendingThresholds = []; cycle = UUID()
    }

    @discardableResult
    public mutating func observe(percentage: Int, enabledThresholds: Set<BatteryAlertThreshold>) -> BatteryAlertDecision? {
        guard (0...100).contains(percentage) else { return nil }
        let previous = lastPercentage
        if let previousAlert = pendingDecision(enabledThresholds: Set(BatteryAlertThreshold.allCases)),
           !previousAlert.threshold.isReached(at: percentage) {
            // Keep a failed current alert retryable through small jitter, but do not resurrect its
            // older coalesced milestones as separate alerts while the battery is recovering.
            let olderMilestones = previousAlert.coveredThresholds.subtracting([previousAlert.threshold])
            pendingThresholds.subtract(olderMilestones)
            handledThresholds.formUnion(olderMilestones)
        }
        var rearmed = false
        for threshold in BatteryAlertThreshold.allCases where percentage >= threshold.rearmPercentage {
            if handledThresholds.remove(threshold) != nil { rearmed = true }
            if pendingThresholds.remove(threshold) != nil { rearmed = true }
        }
        if rearmed { cycle = UUID() }
        lastPercentage = percentage
        for threshold in BatteryAlertThreshold.allCases where threshold.isReached(at: percentage) {
            guard !handledThresholds.contains(threshold), !pendingThresholds.contains(threshold) else { continue }
            let firstLowObservation = previous == nil && threshold != .fifty
            let downwardCrossing = previous.map { !threshold.isReached(at: $0) } ?? false
            if enabledThresholds.contains(threshold), firstLowObservation || downwardCrossing {
                pendingThresholds.insert(threshold)
            } else {
                // The milestone was already passed before observation, or was disabled at the crossing.
                handledThresholds.insert(threshold)
            }
        }
        let disabled = pendingThresholds.subtracting(enabledThresholds)
        pendingThresholds.subtract(disabled)
        handledThresholds.formUnion(disabled)
        return pendingDecision(enabledThresholds: enabledThresholds)
    }

    public func pendingDecision(enabledThresholds: Set<BatteryAlertThreshold>) -> BatteryAlertDecision? {
        guard let percentage = lastPercentage else { return nil }
        let reached = pendingThresholds.intersection(enabledThresholds).filter { $0.isReached(at: percentage) }
        guard let threshold = reached.min(by: { $0.percentage < $1.percentage }) else { return nil }
        return BatteryAlertDecision(threshold: threshold, percentage: percentage, cycle: cycle,
                                    coveredThresholds: Set(reached))
    }

    /// Call only after the notification service accepted the request. A failed request stays pending.
    @discardableResult
    public mutating func markDelivered(_ decision: BatteryAlertDecision) -> Bool {
        guard decision.cycle == cycle, pendingThresholds.contains(decision.threshold),
              let level = lastPercentage, decision.threshold.isReached(at: level) else { return false }
        let acknowledged = decision.coveredThresholds.intersection(pendingThresholds)
        handledThresholds.formUnion(acknowledged)
        pendingThresholds.subtract(acknowledged)
        return true
    }

    public func validate() throws {
        guard lastPercentage.map({ (0...100).contains($0) }) ?? true,
              handledThresholds.isDisjoint(with: pendingThresholds),
              lastPercentage != nil || (handledThresholds.isEmpty && pendingThresholds.isEmpty) else {
            throw BatteryAlertStorageError.invalidHistory
        }
    }
}

public struct BatteryAlertArchive: Codable, Equatable, Sendable {
    public let version: Int
    public var configuration: BatteryAlertConfiguration
    /// Keys are CoreBluetooth UUIDs, never serial numbers or display names.
    public var devices: [String: BatteryAlertDeviceState]

    public init(configuration: BatteryAlertConfiguration = .init(), devices: [String: BatteryAlertDeviceState] = [:]) {
        version = 1; self.configuration = configuration; self.devices = devices
    }

    public func validated() throws -> BatteryAlertArchive {
        guard version == 1, devices.count <= 64 else { throw BatteryAlertStorageError.unsupportedArchive }
        for (key, state) in devices {
            guard UUID(uuidString: key) != nil else { throw BatteryAlertStorageError.invalidHistory }
            try state.validate()
        }
        return self
    }

    public func encoded() throws -> Data {
        _ = try validated()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 131_072 else { throw BatteryAlertStorageError.tooLarge }
        return data
    }

    public static func decode(_ data: Data) throws -> BatteryAlertArchive {
        guard data.count <= 131_072 else { throw BatteryAlertStorageError.tooLarge }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }
}

public enum BatteryAlertStorageError: Error, LocalizedError, Equatable {
    case invalidHistory, unsupportedArchive, tooLarge, insecurePath
    public var errorDescription: String? {
        switch self {
        case .invalidHistory: "The saved battery alert history is invalid."
        case .unsupportedArchive: "The saved battery alert settings use an unsupported format."
        case .tooLarge: "The saved battery alert settings are too large."
        case .insecurePath: "Battery alert storage cannot use a symbolic link."
        }
    }
}
