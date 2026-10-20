import Foundation

/// Read-only identification recovered from Companion's detect_info / HIID path.
/// Only an allowlist of identity and version fields is retained; private fitting
/// data and credentials are skipped without exposing them.
public enum OticonIdentification {
    public static let serviceID: UInt32 = 0x02000004
    public static let hiidInfoOpcode: UInt8 = 3
    public static let gattService = "4F6CF751-176C-4DE1-A25E-D218F1901CCF"
    public static let gattRequest = "19D82B8B-F66F-43DF-A843-8508E2DA564A"
    public static let gattResponse = "6C9BB68D-1E4E-4073-944F-6B06D849446D"
    public static let gattVersion = "C7E127D3-0215-43E6-BC26-3F331D3747A2"

    public enum DecodeError: Error, Equatable {
        case malformed, unsupportedHIIDVersion
    }

    public struct Identity: Equatable, Sendable {
        public let hiidMajor: UInt8
        public let hiidMinor: UInt8
        public let serialNumber: String?
        public let metadata: Metadata
    }

    public struct Metadata: Equatable, Sendable {
        public let hiidVersion: String
        public let manufacturer: String?
        public let model: String?
        public let hardwareRevision: String?
        public let firmwareRevision: String?
        public let softwareRevision: String?
        public let runtimeMemoryMapVersion: String?
        public let releasePackageVersion: String?
        public let primaryAppVersion: String?
        public let maintenanceAppVersion: String?
        /// Labels only: no raw HIID values, identifiers or fitting information.
        public let invalidFields: [String]
    }

    public static func supports(_ service: UTLProtocol.Service) -> Bool {
        service.isAvailable && service.id == serviceID && service.major == 1 && service.minor <= 2
    }

    /// Decode opcode 3's HIID CBOR map, after UTL or DetectInfo GATT reassembly.
    /// Integer keys and their text forms are normalized as in the shipped SDK.
    public static func decodeHiid(_ payload: Data) throws -> Identity {
        guard payload.count <= 65_535 else { throw DecodeError.malformed }
        var reader = Reader(bytes: Array(payload))
        let root = try reader.header()
        guard root.major == 5, root.argument <= 256 else { throw DecodeError.malformed }
        var keys = Set<String>(), version: Data?, serial: Data?
        var metadataBlocks: [String: Data] = [:]
        for _ in 0..<Int(root.argument) {
            let key = try reader.key()
            guard keys.insert(key).inserted else { throw DecodeError.malformed }
            switch key {
            case "1001": version = try reader.byteString()
            case "2003": serial = try reader.byteString()
            case "1012", "2007", "2009", "2019", "2020":
                metadataBlocks[key] = try reader.byteString()
            default: try reader.skip(depth: 0)
            }
        }
        guard reader.index == reader.bytes.count, let version, version.count == 2 else {
            throw DecodeError.malformed
        }
        let bytes = Array(version), major = bytes[0], minor = bytes[1]
        guard (major == 3 && [4, 5, 7].contains(minor))
                || (major == 4 && [3, 5, 6].contains(minor)) else {
            throw DecodeError.unsupportedHIIDVersion
        }
        return Identity(hiidMajor: major, hiidMinor: minor,
                        serialNumber: try serial.flatMap { try serialNumber($0) },
                        metadata: metadata(major: major, minor: minor, blocks: metadataBlocks))
    }

    private static func metadata(major: UInt8, minor: UInt8, blocks: [String: Data]) -> Metadata {
        var invalid: [String] = []
        func text(_ key: String, at offset: Int = 0, label: String) -> String? {
            guard let data = blocks[key] else { return nil }
            guard offset + 18 <= data.count else { invalid.append(label); return nil }
            // WirelessNameStringReader takes at most 18 bytes and stops at NUL.
            let value = Data(data.dropFirst(offset).prefix(18).prefix { $0 != 0 })
            guard let decoded = String(data: value, encoding: .utf8) else {
                invalid.append(label); return nil
            }
            let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                invalid.append(label); return nil
            }
            return trimmed.isEmpty ? nil : trimmed
        }
        func version(_ key: String, at offset: Int, label: String) -> String? {
            guard let data = blocks[key] else { return nil }
            guard offset + 3 <= data.count else { invalid.append(label); return nil }
            // TripleVersionReader maps these three individual bytes to Version.
            return data.dropFirst(offset).prefix(3).map(String.init).joined(separator: ".")
        }
        // HIID 3.x begins entry 1012 with DefaultProductionSettingsVersion;
        // supported 4.x removed that first three-byte field.
        let runtimeOffset = major == 3 ? 3 : 0
        let manufacturer = text("2009", label: "Manufacturer")
        let model = text("2009", at: 18, label: "Model")
        let hardware = text("2009", at: 36, label: "Hardware revision")
        let firmware = text("2007", label: "Firmware revision")
        let software = text("2019", label: "Software revision")
        let runtime = version("1012", at: runtimeOffset, label: "Runtime memory-map version")
        let release = version("1012", at: runtimeOffset + 3, label: "Release-package version")
        let primary = version("2020", at: 0, label: "Primary application version")
        let maintenance = version("2020", at: 3, label: "Maintenance application version")
        return Metadata(hiidVersion: "\(major).\(minor)", manufacturer: manufacturer, model: model,
                        hardwareRevision: hardware, firmwareRevision: firmware, softwareRevision: software,
                        runtimeMemoryMapVersion: runtime, releasePackageVersion: release,
                        primaryAppVersion: primary, maintenanceAppVersion: maintenance, invalidFields: invalid)
    }

    /// Four bytes from DIET entry 2003, not the production or companion serial.
    public static func serialNumber(_ data: Data) throws -> String? {
        guard data.count == 4 else { throw DecodeError.malformed }
        let bytes = Array(data)
        guard bytes.contains(where: { $0 != 0 }) else { return nil }
        let value = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        if bytes[0] & 0x80 != 0 || bytes[0] & 0xF0 == 0 {
            let decimal = String(value & 0x0FFF_FFFF)
            return String(repeating: "0", count: max(0, 8 - decimal.count)) + decimal
        }
        let alphabet = Array("0123456789ABCEFGHIJKLMNPRSTUVWXZ")
        return String(stride(from: 25, through: 0, by: -5).map {
            alphabet[Int((value >> $0) & 0x1F)]
        })
    }

    /// A bounded CBOR walker for this map only. It does not retain unknown values
    /// or perform tagged/executable deserialization. Existing EQ CBOR is separate.
    private struct Reader {
        let bytes: [UInt8]
        var index = 0
        var items = 0

        mutating func byte() throws -> UInt8 {
            guard index < bytes.count else { throw DecodeError.malformed }
            defer { index += 1 }
            return bytes[index]
        }

        mutating func header() throws -> (major: UInt8, info: UInt8, argument: UInt64) {
            items += 1
            guard items <= 4096 else { throw DecodeError.malformed }
            let initial = try byte(), info = initial & 31
            let count: Int
            switch info {
            case 0..<24: return (initial >> 5, info, UInt64(info))
            case 24: count = 1
            case 25: count = 2
            case 26: count = 4
            case 27: count = 8
            default: throw DecodeError.malformed
            }
            var value: UInt64 = 0
            for _ in 0..<count { value = (value << 8) | UInt64(try byte()) }
            return (initial >> 5, info, value)
        }

        mutating func take(_ count: UInt64) throws -> Data {
            guard count <= UInt64(bytes.count - index) else { throw DecodeError.malformed }
            let length = Int(count)
            defer { index += length }
            return Data(bytes[index..<(index + length)])
        }

        mutating func key() throws -> String {
            let value = try header()
            switch value.major {
            case 0: return String(value.argument)
            case 3:
                guard let text = String(data: try take(value.argument), encoding: .utf8) else {
                    throw DecodeError.malformed
                }
                return text
            default: throw DecodeError.malformed
            }
        }

        mutating func byteString() throws -> Data {
            let value = try header()
            guard value.major == 2 else { throw DecodeError.malformed }
            return try take(value.argument)
        }

        mutating func skip(depth: Int) throws {
            guard depth <= 12 else { throw DecodeError.malformed }
            let value = try header()
            switch value.major {
            case 0, 1: break
            case 2, 3: _ = try take(value.argument)
            case 4, 5:
                guard value.argument <= 1024 else { throw DecodeError.malformed }
                let count = Int(value.argument) * (value.major == 5 ? 2 : 1)
                for _ in 0..<count { try skip(depth: depth + 1) }
            case 7:
                guard [20, 21, 22, 25, 26, 27].contains(value.info) else { throw DecodeError.malformed }
            default: throw DecodeError.malformed
            }
        }
    }
}
