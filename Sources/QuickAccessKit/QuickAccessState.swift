import Foundation

public enum QuickTarget: String, Codable, CaseIterable, Sendable { case both, left, right }
public struct QuickEar: Codable, Equatable, Sendable {
    public let side: QuickTarget
    public let connected: Bool
    public let battery: Int?
    public let runtime: BatteryRuntimeReading?
    public let level: Int?
    public let muted: Bool?
    public let minimum: Int?
    public let maximum: Int?
    public let canChangeVolume: Bool
    public let speechBooster: Bool?
    public let canChangeSpeechBooster: Bool
    public init(side: QuickTarget, connected: Bool, battery: Int?, runtime: BatteryRuntimeReading?, level: Int?, muted: Bool?, minimum: Int?, maximum: Int?, canChangeVolume: Bool, speechBooster: Bool?, canChangeSpeechBooster: Bool) {
        self.side = side; self.connected = connected; self.battery = battery; self.runtime = runtime
        self.level = level; self.muted = muted; self.minimum = minimum; self.maximum = maximum
        self.canChangeVolume = canChangeVolume; self.speechBooster = speechBooster; self.canChangeSpeechBooster = canChangeSpeechBooster
    }
}
public struct QuickAccessState: Codable, Equatable, Sendable {
    public static let maximumAge: TimeInterval = 90
    public let schema: Int
    public let session: UUID
    public let updatedAt: Date
    public let sharingEnabled: Bool
    public let ears: [QuickEar]
    public let paused: Bool
    public let canReconnect: Bool
    public let macAudio: Bool
    public let canSwitchAudio: Bool
    public init(session: UUID, updatedAt: Date, sharingEnabled: Bool, ears: [QuickEar], paused: Bool, canReconnect: Bool, macAudio: Bool, canSwitchAudio: Bool) {
        schema = 1; self.session = session; self.updatedAt = updatedAt; self.sharingEnabled = sharingEnabled
        self.ears = ears; self.paused = paused; self.canReconnect = canReconnect; self.macAudio = macAudio; self.canSwitchAudio = canSwitchAudio
    }
    public func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(updatedAt)
        return schema == 1 && sharingEnabled && (0...Self.maximumAge).contains(age)
            && ears.count <= 2 && Set(ears.map(\.side)).count == ears.count
            && ears.allSatisfy { ear in
                ear.side != .both && (ear.battery == nil || (0...100).contains(ear.battery!))
                    && (ear.level == nil || (-128...127).contains(ear.level!))
                    && (ear.minimum == nil || (-128...127).contains(ear.minimum!))
                    && (ear.maximum == nil || (-128...127).contains(ear.maximum!))
            }
    }
    public func targets(_ target: QuickTarget) -> [QuickEar] {
        let chosen = ears.filter { target == .both || $0.side == target }
        guard chosen.count == (target == .both ? 2 : 1), chosen.allSatisfy(\.connected) else { return [] }
        return chosen
    }
    public func permits(_ command: QuickCommand, at now: Date) -> Bool {
        guard isFresh(at: now), command.session == session, command.isValid(at: now) else { return false }
        switch command.kind {
        case .connection: return command.flag == false || canReconnect
        case .audio: return canSwitchAudio
        case .mute: return !targets(command.target).isEmpty && targets(command.target).allSatisfy(\.canChangeVolume)
        case .speechBooster: return !targets(command.target).isEmpty && targets(command.target).allSatisfy(\.canChangeSpeechBooster)
        case .volume:
            let chosen = targets(command.target)
            return !chosen.isEmpty && chosen.allSatisfy { ear in
                guard ear.canChangeVolume, let level = ear.level, let minimum = ear.minimum, let maximum = ear.maximum,
                      let delta = command.delta else { return false }
                return minimum <= maximum && (minimum...maximum).contains(level + delta)
            }
        }
    }
}
public struct QuickCommand: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case volume, mute, speechBooster, connection, audio }
    public let id: UUID
    public let session: UUID
    public let createdAt: Date
    public let kind: Kind
    public let target: QuickTarget
    public let delta: Int?
    public let flag: Bool?
    public init(session: UUID, createdAt: Date = Date(), kind: Kind, target: QuickTarget = .both, delta: Int? = nil, flag: Bool? = nil) {
        id = UUID(); self.session = session; self.createdAt = createdAt; self.kind = kind; self.target = target; self.delta = delta; self.flag = flag
    }
    public func isValid(at now: Date) -> Bool {
        guard (0...8).contains(now.timeIntervalSince(createdAt)) else { return false }
        if kind == .volume { return (delta == -1 || delta == 1) && flag == nil }
        return flag != nil && delta == nil
    }
}
public struct QuickReceipt: Codable, Sendable {
    public let id: UUID
    public let accepted: Bool
    public let message: String
    public init(id: UUID, accepted: Bool, message: String) { self.id = id; self.accepted = accepted; self.message = message }
}
