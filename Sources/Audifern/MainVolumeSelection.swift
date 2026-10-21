import CompanionCore
import Foundation

/// A fader's permitted range is the intersection of relative movement across
/// its targets. Linking preserves the existing balance and each ear's mute.
struct MainVolumeSelection {
    let aids: [AidConnection]
    let anchorID: UUID
    let level: Int
    let range: ClosedRange<Int>

    init?(aids: [AidConnection], anchorID: UUID) {
        guard (1...2).contains(aids.count), Set(aids.map(\.id)).count == aids.count,
              let anchor = aids.first(where: { $0.id == anchorID }), let anchorVolume = anchor.volume,
              aids.allSatisfy({ aid in
                  guard let volume = aid.volume, let range = aid.volumeRanges?.main else { return false }
                  return aid.canChangeVolume && range.contains(volume.level)
                      && (-128...127).contains(range.lowerBound) && (-128...127).contains(range.upperBound)
              }) else { return nil }
        let minimum = aids.map { $0.volumeRanges!.main.lowerBound - $0.volume!.level }.max()!
        let maximum = aids.map { $0.volumeRanges!.main.upperBound - $0.volume!.level }.min()!
        self.aids = aids; self.anchorID = anchorID; self.level = anchorVolume.level
        self.range = (anchorVolume.level + minimum)...(anchorVolume.level + maximum)
    }

    func levels(setting target: Int) -> [UUID: Int]? {
        guard range.contains(target) else { return nil }
        let delta = target - level
        return Dictionary(uniqueKeysWithValues: aids.map { ($0.id, $0.volume!.level + delta) })
    }

    func matches(_ connections: [UUID: AidConnection]) -> Bool {
        aids.allSatisfy { expected in
            guard let current = connections[expected.id], current.canChangeVolume else { return false }
            return current.volume == expected.volume && current.volumeRanges == expected.volumeRanges
                && current.activeProgram == expected.activeProgram
        }
    }
}
