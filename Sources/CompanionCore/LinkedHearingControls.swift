import Foundation

/// A linked step preserves the two ears' existing balance and is valid only
/// when both reported volume ranges permit the entire operation.
public struct LinkedHearingControls: Equatable, Sendable {
    public struct Aid: Equatable, Sendable {
        public let level: Int
        public let muted: Bool
        public let range: ClosedRange<Int>

        public init(level: Int, muted: Bool, range: ClosedRange<Int>) {
            self.level = level; self.muted = muted; self.range = range
        }
    }

    public let aids: [Aid]

    public init?(aids: [Aid]) {
        guard aids.count == 2,
              aids.allSatisfy({ (-128...127).contains($0.range.lowerBound)
                  && (-128...127).contains($0.range.upperBound) && $0.range.contains($0.level) }) else { return nil }
        self.aids = aids
    }

    public var allMuted: Bool { aids.allSatisfy(\.muted) }
    public var sharedLevel: Int? { aids[0].level == aids[1].level ? aids[0].level : nil }

    public func levels(adjustingBy delta: Int) -> [Int]? {
        guard delta == -1 || delta == 1 else { return nil }
        let proposed = aids.map { $0.level + delta }
        guard zip(aids, proposed).allSatisfy({ $0.range.contains($1) }) else { return nil }
        return proposed
    }
}
