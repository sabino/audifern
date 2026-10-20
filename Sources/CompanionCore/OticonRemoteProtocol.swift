import Foundation

/// Remote-control wire formats recovered from Companion 1.8.0's managed SDK.
/// This does not establish that a particular aid exposes the legacy service.
/// See docs/legacy-protocol.md for artifact identity and evidence boundaries.
public enum OticonRemoteProtocol {
    public static let service = "56772EAF-2153-4F74-ACF3-4368D99FBF5A"
    public static let mainVolume = "1454E9D6-F658-4190-8589-22AA9E3021EB"
    public static let volumeRanges = "58BBCCC5-5A57-4E00-98D5-18C6A0408DFD"
    public static let activeProgram = "535442F7-0FF7-4FEC-9780-742F3EB00EDA"
    public static let availablePrograms = "DCBE7A3E-A742-4527-AEB5-CD8DEE63167F"
    public static let ear = "D28617FE-0AD5-40C5-A04A-BC89051FF755"

    public struct Volume: Equatable, Sendable {
        public let level: Int
        public let muted: Bool

        public init?(data: Data) {
            let bytes = Array(data)
            guard bytes.count == 2, bytes[1] <= 1 else { return nil }
            level = Int(Int8(bitPattern: bytes[0]))
            muted = bytes[1] == 0
        }
    }

    public struct VolumeRanges: Equatable, Sendable {
        public let main: ClosedRange<Int>
        public let streaming: ClosedRange<Int>
        public let tinnitus: ClosedRange<Int>

        public init?(data: Data) {
            let values = data.map { Int(Int8(bitPattern: $0)) }
            guard values.count >= 6,
                  values[0] <= values[1], values[2] <= values[3], values[4] <= values[5] else { return nil }
            main = values[0]...values[1]
            streaming = values[2]...values[3]
            tinnitus = values[4]...values[5]
        }
    }

    /// Explicit-user-action payload only. Refuses values outside the aid's reported range.
    public static func volumePayload(level: Int, muted: Bool, reportedRange: ClosedRange<Int>) -> Data? {
        guard reportedRange.contains(level), let signed = Int8(exactly: level) else { return nil }
        return Data([UInt8(bitPattern: signed), muted ? 0 : 1])
    }

    public static func programIDs(bitmap: Data) -> [Int]? {
        guard !bitmap.isEmpty, bitmap.count <= 32 else { return nil }
        return bitmap.enumerated().flatMap { index, byte in
            (0..<8).compactMap { bit in byte & (1 << bit) != 0 ? index * 8 + bit : nil }
        }
    }

    public static func programPayload(id: Int, reportedPrograms: [Int]) -> Data? {
        guard reportedPrograms.contains(id), let value = UInt8(exactly: id) else { return nil }
        return Data([value])
    }
}

/// Bluetooth VCS volume is a separate state from Oticon's microphone gain.
public struct BluetoothVolumeState: Equatable, Sendable {
    public let volume: UInt8
    public let muted: Bool
    public let changeCounter: UInt8

    public init?(data: Data) {
        let bytes = Array(data)
        guard bytes.count == 3, bytes[1] <= 1 else { return nil }
        volume = bytes[0]
        muted = bytes[1] == 1
        changeCounter = bytes[2]
    }
}
