import Foundation

/// Bounded CBOR subset used by the statically recovered service contracts.
/// No tagged objects, indefinite byte strings or executable deserialization.
public indirect enum UTLCBOR: Equatable, Sendable {
    case integer(Int), number(Double), text(String), bytes(Data), array([UTLCBOR]), map([String: UTLCBOR]), boolean(Bool), null

    public var int: Int? { if case .integer(let value) = self { return value }; return nil }
    public var double: Double? {
        if case .number(let value) = self { return value }
        return int.map(Double.init)
    }

    public static func decodeSequence(_ data: Data) throws -> [UTLCBOR] {
        guard data.count <= 65_535 else { throw OticonEqualizer.EQError.malformed }
        var decoder = Decoder(bytes: Array(data)), result: [UTLCBOR] = []
        while decoder.index < decoder.bytes.count { result.append(try decoder.read(depth: 0)) }
        return result
    }

    public static func unsignedVector(_ steps: [Int]) throws -> Data {
        guard steps.count == 8, steps.allSatisfy({ (-128...127).contains($0) }) else { throw OticonEqualizer.EQError.malformed }
        var result = Data([0x88])
        for step in steps {
            let byte = UInt8(bitPattern: Int8(step))
            if byte < 24 { result.append(byte) } else { result.append(contentsOf: [0x18, byte]) }
        }
        return result
    }

    private struct Decoder {
        let bytes: [UInt8]
        var index = 0
        var count = 0

        mutating func byte() throws -> UInt8 {
            guard index < bytes.count else { throw OticonEqualizer.EQError.malformed }
            defer { index += 1 }; return bytes[index]
        }
        mutating func argument(_ additional: UInt8) throws -> UInt64 {
            if additional < 24 { return UInt64(additional) }
            let size: Int
            switch additional { case 24: size = 1; case 25: size = 2; case 26: size = 4; case 27: size = 8; default: throw OticonEqualizer.EQError.unsupported }
            var result: UInt64 = 0
            for _ in 0..<size { result = result << 8 | UInt64(try byte()) }
            return result
        }
        mutating func read(depth: Int) throws -> UTLCBOR {
            count += 1
            guard depth <= 12, count <= 2048 else { throw OticonEqualizer.EQError.malformed }
            let initial = try byte(), major = initial >> 5, info = initial & 31
            if major == 7 {
                switch info {
                case 20: return .boolean(false)
                case 21: return .boolean(true)
                case 22: return .null
                case 25:
                    let bits = UInt16(try argument(25))
                    let sign = bits & 0x8000 == 0 ? 1.0 : -1.0, exponent = Int((bits >> 10) & 31), mantissa = Double(bits & 1023)
                    guard exponent != 31 else { throw OticonEqualizer.EQError.malformed }
                    return .number(sign * (exponent == 0 ? pow(2, -14) * mantissa / 1024 : pow(2, Double(exponent - 15)) * (1 + mantissa / 1024)))
                case 26:
                    let value = Double(Float(bitPattern: UInt32(try argument(26))))
                    guard value.isFinite else { throw OticonEqualizer.EQError.malformed }; return .number(value)
                case 27:
                    let value = Double(bitPattern: try argument(27))
                    guard value.isFinite else { throw OticonEqualizer.EQError.malformed }; return .number(value)
                default: throw OticonEqualizer.EQError.unsupported
                }
            }
            let argument = try argument(info)
            guard argument <= UInt64(Int.max) else { throw OticonEqualizer.EQError.malformed }
            let length = Int(argument)
            switch major {
            case 0: return .integer(length)
            case 1: return .integer(-1 - length)
            case 2, 3:
                guard length <= bytes.count - index else { throw OticonEqualizer.EQError.malformed }
                let value = Data(bytes[index..<(index + length)]); index += length
                if major == 2 { return .bytes(value) }
                guard let text = String(data: value, encoding: .utf8) else { throw OticonEqualizer.EQError.malformed }
                return .text(text)
            case 4:
                guard length <= 256 else { throw OticonEqualizer.EQError.malformed }
                var result: [UTLCBOR] = []
                for _ in 0..<length { result.append(try read(depth: depth + 1)) }; return .array(result)
            case 5:
                guard length <= 256 else { throw OticonEqualizer.EQError.malformed }
                var result: [String: UTLCBOR] = [:]
                for _ in 0..<length {
                    guard case .text(let key) = try read(depth: depth + 1), result[key] == nil else { throw OticonEqualizer.EQError.malformed }
                    result[key] = try read(depth: depth + 1)
                }
                return .map(result)
            default: throw OticonEqualizer.EQError.unsupported
            }
        }
    }
}
