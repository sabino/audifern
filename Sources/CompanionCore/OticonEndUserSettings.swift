import Foundation

/// Read contracts for the EUS 2.1 service advertised by the matched Intent model.
/// The inventory is supplied by the aid; program counts and IDs are not inferred.
public enum OticonEndUserSettings {
    public static let serviceID: UInt32 = 0x02000017
    public static let inventoryOpcode: UInt8 = 0
    public static let metadataOpcode: UInt8 = 1
    public static let readOpcode: UInt8 = 2
    public static let maximumResponseBytes = 65_535
    public static let maximumRecords = 128

    public enum DecodeError: Error, Equatable {
        case malformedCBOR, responseTooLarge, invalidInventory
        case invalidAccess, countLimit, duplicateScope
    }

    public static func supports(service: UTLProtocol.Service) -> Bool {
        service.isAvailable && service.id == serviceID && service.major == 2 && service.minor == 1
    }

    public struct Scope: Equatable, Sendable {
        public let name: String
        public let count: Int
        public let access: String
        /// Unknown names retain their inventory but never receive a guessed ID.
        public let wireID: UInt8?
    }

    public struct Read: Equatable, Sendable {
        public let scope: UInt8
        public let id: UInt8
        public let scopeName: String
    }

    public struct Inventory: Equatable, Sendable {
        public let raw: Data
        public let scopes: [Scope]
        public let reads: [Read]
        public let hasAdditionalScopeGroups: Bool
        public var unknownScopes: [String] { scopes.filter { $0.wireID == nil }.map(\.name) }
        /// Includes known RAM-only scopes because this plan reads NVRAM only.
        public var unreadScopes: [String] { scopes.filter { $0.wireID == nil || $0.access == "RAM" }.map(\.name) }
        /// This describes the read plan, not completed reads or restore coverage.
        public var isComplete: Bool { unreadScopes.isEmpty && !hasAdditionalScopeGroups }
    }

    /// Input to opcode 2 inside an owned READ_NVRAM transaction. Metadata and
    /// inventory opcodes take empty bodies and use a COMMAND transaction.
    public static func readRequest(_ read: Read) -> Data { Data([read.scope, read.id]) }

    /// Preserve exactly one bounded complete CBOR value, including opaque EUS
    /// maps. There is no additional length envelope or fitting-data CRC here.
    public static func validateResponse(_ payload: Data) throws -> Data {
        _ = try decode(payload)
        return payload
    }

    /// get_eus_scope_info returns {"scopes": [[{name, count, access}, ...], ...]}.
    /// The shipped getter uses the first inner array. Unknown scopes are retained
    /// but omitted from the plan. Counts must be below 256 and total at most 128.
    public static func decodeInventory(_ payload: Data) throws -> Inventory {
        let root = try textMap(decode(payload))
        guard case .array(let scopeGroups)? = root["scopes"],
              let first = scopeGroups.first, case .array(let rows) = first else {
            throw DecodeError.invalidInventory
        }
        var scopes: [Scope] = [], reads: [Read] = [], names = Set<String>(), total = 0
        for row in rows {
            let fields = try textMap(row)
            guard case .text(let name)? = fields["name"], !name.isEmpty, name.utf8.count <= 128,
                  !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  case .text(let access)? = fields["access"], let countValue = fields["count"] else {
                throw DecodeError.invalidInventory
            }
            guard ["NVRAM", "RAM_NVRAM", "RAM"].contains(access) else { throw DecodeError.invalidAccess }
            guard names.insert(name).inserted else { throw DecodeError.duplicateScope }
            let count: Int
            switch countValue {
            case .unsigned(let value) where value < 256: count = Int(value)
            case .text(let text) where !text.isEmpty && text.utf8.count <= 3
                    && text.utf8.allSatisfy({ (48...57).contains($0) }):
                guard let value = Int(text), value < 256 else { throw DecodeError.countLimit }
                count = value
            default: throw DecodeError.countLimit
            }
            guard count <= maximumRecords - total else { throw DecodeError.countLimit }
            total += count
            let wireID: UInt8?
            switch name {
            case "global": wireID = 0
            case "situation": wireID = 1
            case "profile": wireID = 2
            default: wireID = nil
            }
            scopes.append(Scope(name: name, count: count, access: access, wireID: wireID))
            if let wireID, access != "RAM" {
                for id in 0..<count { reads.append(Read(scope: wireID, id: UInt8(id), scopeName: name)) }
            }
        }
        return Inventory(raw: Data(payload), scopes: scopes, reads: reads,
                         hasAdditionalScopeGroups: scopeGroups.count > 1)
    }

    private indirect enum Value {
        case unsigned(UInt64), bytes(Data), text(String), array([Value]), map([(Value, Value)]), other
    }

    private static func textMap(_ value: Value) throws -> [String: Value] {
        guard case .map(let pairs) = value else { throw DecodeError.invalidInventory }
        var result: [String: Value] = [:]
        for (key, value) in pairs {
            guard case .text(let name) = key else { throw DecodeError.invalidInventory }
            guard case .none = result[name] else { throw DecodeError.invalidInventory }
            result[name] = value
        }
        return result
    }

    private static func decode(_ payload: Data) throws -> Value {
        guard payload.count <= maximumResponseBytes else { throw DecodeError.responseTooLarge }
        var reader = Reader(bytes: Array(payload))
        let value = try reader.value(depth: 0)
        guard reader.index == reader.bytes.count else { throw DecodeError.malformedCBOR }
        return value
    }

    /// A bounded inert CBOR reader. Tags and primitive values are validated but
    /// never instantiated as application objects or evaluated.
    private struct Reader {
        let bytes: [UInt8]
        var index = 0
        var items = 0

        mutating func byte() throws -> UInt8 {
            guard index < bytes.count else { throw DecodeError.malformedCBOR }
            defer { index += 1 }
            return bytes[index]
        }

        mutating func header() throws -> (major: UInt8, info: UInt8, argument: UInt64?) {
            let first = try byte(), major = first >> 5, info = first & 31
            if info < 24 { return (major, info, UInt64(info)) }
            if info == 31 {
                guard (2...5).contains(major) else { throw DecodeError.malformedCBOR }
                return (major, info, nil)
            }
            let length: Int
            switch info {
            case 24: length = 1
            case 25: length = 2
            case 26: length = 4
            case 27: length = 8
            default: throw DecodeError.malformedCBOR
            }
            var argument: UInt64 = 0
            for _ in 0..<length { argument = (argument << 8) | UInt64(try byte()) }
            return (major, info, argument)
        }

        mutating func take(_ count: UInt64) throws -> Data {
            guard count <= UInt64(bytes.count - index) else { throw DecodeError.malformedCBOR }
            let length = Int(count)
            defer { index += length }
            return Data(bytes[index..<(index + length)])
        }

        mutating func isBreak() throws -> Bool {
            guard index < bytes.count else { throw DecodeError.malformedCBOR }
            if bytes[index] == 0xFF { index += 1; return true }
            return false
        }

        mutating func value(depth: Int) throws -> Value {
            items += 1
            guard depth <= 16, items <= 16_384 else { throw DecodeError.malformedCBOR }
            let h = try header()
            switch h.major {
            case 0: return .unsigned(h.argument!)
            case 1: return .other
            case 2, 3:
                var data = Data()
                if let length = h.argument { data = try take(length) }
                else {
                    while try !isBreak() {
                        items += 1
                        guard items <= 16_384 else { throw DecodeError.malformedCBOR }
                        let chunk = try header()
                        guard chunk.major == h.major, let length = chunk.argument else { throw DecodeError.malformedCBOR }
                        let part = try take(length)
                        if h.major == 3, String(data: part, encoding: .utf8) == nil { throw DecodeError.malformedCBOR }
                        data.append(part)
                    }
                }
                if h.major == 2 { return .bytes(data) }
                guard let text = String(data: data, encoding: .utf8) else { throw DecodeError.malformedCBOR }
                return .text(text)
            case 4:
                var values: [Value] = []
                if let count = h.argument {
                    guard count <= 4096 else { throw DecodeError.malformedCBOR }
                    for _ in 0..<Int(count) { values.append(try value(depth: depth + 1)) }
                } else {
                    while try !isBreak() {
                        guard values.count < 4096 else { throw DecodeError.malformedCBOR }
                        values.append(try value(depth: depth + 1))
                    }
                }
                return .array(values)
            case 5:
                var pairs: [(Value, Value)] = []
                if let count = h.argument {
                    guard count <= 4096 else { throw DecodeError.malformedCBOR }
                    for _ in 0..<Int(count) {
                        let key = try value(depth: depth + 1)
                        pairs.append((key, try value(depth: depth + 1)))
                    }
                } else {
                    while try !isBreak() {
                        guard pairs.count < 4096 else { throw DecodeError.malformedCBOR }
                        let key = try value(depth: depth + 1)
                        pairs.append((key, try value(depth: depth + 1)))
                    }
                }
                return .map(pairs)
            case 6:
                _ = try value(depth: depth + 1)
                return .other
            case 7:
                if h.info == 24, h.argument! < 32 { throw DecodeError.malformedCBOR }
                return .other
            default: throw DecodeError.malformedCBOR
            }
        }
    }
}
