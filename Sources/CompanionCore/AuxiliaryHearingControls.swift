import Foundation

/// Consumer source levels only. This does not create/configure tinnitus therapy,
/// change modulation/EQ, or control Bluetooth VCS / system media volume.
public enum AuxiliaryHearingControls {
    public enum Source: String, Sendable {
        case tinnitus = "Tinnitus", streaming = "Streaming source"
        public var characteristic: String {
            self == .tinnitus ? OticonRemoteProtocol.tinnitusVolume : OticonRemoteProtocol.streamingVolume
        }
    }
    public enum Change: Equatable, Sendable { case adjust(Int), muted(Bool) }
    public struct Aid: Equatable, Sendable {
        public let current: OticonRemoteProtocol.Volume
        public let range: ClosedRange<Int>
        public let programEligible: Bool?
        public init(current: OticonRemoteProtocol.Volume, range: ClosedRange<Int>, programEligible: Bool?) {
            self.current = current; self.range = range; self.programEligible = programEligible
        }
    }

    /// The SDK maps only these legacy raw categories to TV/GenericStreamer.
    /// A tinnitus program exposes Tinnitus + Main instead of Streaming + Main.
    public static func supportsStreaming(category: UInt8, tinnitus: Bool) -> Bool {
        !tinnitus && [UInt8(10), 11, 201, 255].contains(category)
    }

    /// Preflight every aid before any physical write; preserve each ear's current
    /// other field and level offset. Unknown program eligibility fails closed.
    public static func payloads(for aids: [Aid], change: Change) -> [Data]? {
        guard (1...2).contains(aids.count), aids.allSatisfy({ $0.programEligible == true
            && (-128...127).contains($0.range.lowerBound) && (-128...127).contains($0.range.upperBound)
            && $0.range.contains($0.current.level) }) else { return nil }
        var result: [Data] = []
        for aid in aids {
            let level: Int, muted: Bool
            switch change {
            case .adjust(let delta):
                guard delta == -1 || delta == 1 else { return nil }
                level = aid.current.level + delta; muted = aid.current.muted
            case .muted(let value): level = aid.current.level; muted = value
            }
            guard let data = OticonRemoteProtocol.volumePayload(level: level, muted: muted, reportedRange: aid.range) else { return nil }
            result.append(data)
        }
        return result
    }
}
