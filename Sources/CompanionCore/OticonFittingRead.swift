import Foundation

/// Bounded decoding of HIID 4.5 DIET entry 1009. This codec performs no device
/// operations and does not interpret or write individual fitted parameters.
public enum OticonFittingRead {
    public static let serviceID: UInt32 = 0x02000006
    public static let readOpcode: UInt8 = 0
    public static let recordKey: UInt16 = 1009
    public static let headerSize = 16
    public static let maximumPayloadSize = 4000
    public static let maximumRecordSize = headerSize + maximumPayloadSize
    /// The shipped HIID read scheduler splits reads at this limit.
    public static let maximumReadLength = 950

    public enum DecodeError: Error, Equatable {
        case unsupportedHIIDVersion, invalidReadRange, unexpectedResponseLength
        case malformedHeader, invalidPayloadSize, payloadLengthMismatch
        case headerChanged, checksumMismatch, unsupportedFormat, malformedBlob
    }

    public static func supports(service: UTLProtocol.Service, hiidVersion: String) -> Bool {
        hiidVersion == "4.5" && service.isAvailable && service.id == serviceID
            && service.major == 1 && service.minor <= 1
    }

    /// Body of hiid.get_hiid_data_nvram, opcode 0. UTL framing and the owning
    /// READ_NVRAM transaction are supplied by the caller. All integers are BE.
    public static func readRequest(offset: Int, length: Int) throws -> Data {
        guard offset >= 0, length > 0, length <= maximumReadLength,
              offset < maximumRecordSize, length <= maximumRecordSize - offset else {
            throw DecodeError.invalidReadRange
        }
        return Data([1, UInt8(recordKey >> 8), UInt8(recordKey & 0xFF),
                     UInt8(offset >> 8), UInt8(offset & 0xFF),
                     UInt8(length >> 8), UInt8(length & 0xFF)])
    }

    /// The service response body is exactly the requested bytes. It contains no
    /// CBOR, count, DIET key or per-entry envelope; remove UTL status first.
    public static func decodeReadResponse(_ payload: Data, expectedLength: Int) throws -> Data {
        guard expectedLength > 0, expectedLength <= maximumReadLength,
              payload.count == expectedLength else { throw DecodeError.unexpectedResponseLength }
        return payload
    }

    public struct Header: Equatable, Sendable {
        public let version: String
        public let size: Int
        public let checksum: UInt16
        /// Includes the eight reserved bytes; keep these in the private archive.
        public let bytes: Data
        public var isKnownFormat: Bool { version == "0.1.0" }

        public init(data: Data) throws {
            guard data.count == headerSize else { throw DecodeError.malformedHeader }
            let b = Array(data)
            // FittingVersionReader: major 12 bits, minor 10, build 10, MSB first.
            let major = (Int(b[0]) << 4) | (Int(b[1]) >> 4)
            let minor = ((Int(b[1]) & 0x0F) << 6) | (Int(b[2]) >> 2)
            let build = ((Int(b[2]) & 3) << 8) | Int(b[3])
            version = "\(major).\(minor).\(build)"
            size = (Int(b[4]) << 8) | Int(b[5])
            guard size <= maximumPayloadSize else { throw DecodeError.invalidPayloadSize }
            checksum = (UInt16(b[6]) << 8) | UInt16(b[7])
            bytes = Data(b)
        }
    }

    public struct ReadChunk: Equatable, Sendable {
        public let offset: Int
        public let length: Int
    }

    /// Read the header first, then these body chunks, then the header again.
    /// Zero-sized data has no body chunks and cannot contain a decoded fitting.
    public static func payloadChunks(size: Int) throws -> [ReadChunk] {
        guard (0...maximumPayloadSize).contains(size) else { throw DecodeError.invalidPayloadSize }
        return stride(from: 0, to: size, by: maximumReadLength).map {
            ReadChunk(offset: headerSize + $0, length: min(maximumReadLength, size - $0))
        }
    }

    /// Validate the exact declared payload and optionally the second header read.
    /// Returns the complete archive record: the 16-byte header followed by Size
    /// meaningful bytes. Unread vector padding is not invented or appended.
    /// Unknown format versions remain valid opaque records after CRC validation.
    public static func validateRecord(header: Data, payload: Data, repeatedHeader: Data? = nil) throws -> Data {
        let decoded = try Header(data: header)
        if let repeatedHeader {
            _ = try Header(data: repeatedHeader)
            guard header == repeatedHeader else { throw DecodeError.headerChanged }
        }
        guard payload.count == decoded.size else { throw DecodeError.payloadLengthMismatch }
        guard checksum(payload) == decoded.checksum else { throw DecodeError.checksumMismatch }
        return Data(header) + payload
    }

    /// Vendor fitting-data CRC: polynomial 0x1021, initial 0xFFFF, input bits
    /// shifted into the low bit MSB first, then 16 zero bits, no final XOR.
    /// This is the augmented algorithm, not ordinary CRC-16/CCITT-FALSE.
    public static func checksum(_ data: Data) -> UInt16 {
        var value: UInt16 = 0xFFFF
        for byte in data {
            for bit in stride(from: 7, through: 0, by: -1) {
                let polynomial: UInt16 = value & 0x8000 == 0 ? 0 : 0x1021
                value = (value &<< 1) | UInt16((byte >> bit) & 1)
                value ^= polynomial
            }
        }
        for _ in 0..<16 {
            let polynomial: UInt16 = value & 0x8000 == 0 ? 0 : 0x1021
            value = (value &<< 1) ^ polynomial
        }
        return value
    }

    /// Byte sections of the known 0.1.0 serializer, without interpreting model
    /// dependent register bits. EUS scopes are separate and are not in this blob.
    public struct Blob: Equatable, Sendable {
        /// Raw Guid.ToByteArray() layout; this is not RFC UUID byte order.
        public let fittingIDBytes: Data
        /// EarPiece, Hook, Vent, Tubing, FittingLevelAcoustics, FittedSide.
        public let selection: Data
        /// Starts with four ordinary version bytes, then packed register bits.
        public let prodRegs: Data
        public let businessData: Data
        public var prodRegsVersionBytes: Data { Data(prodRegs.prefix(4)) }
    }

    /// Optional structural decoding. Keep a validated raw record even if its
    /// version is unknown; never substitute an assumed model or register map.
    public static func decodeBlob(_ payload: Data, header: Header, hiidVersion: String) throws -> Blob {
        guard hiidVersion == "4.5" else { throw DecodeError.unsupportedHIIDVersion }
        guard header.isKnownFormat else { throw DecodeError.unsupportedFormat }
        _ = try validateRecord(header: header.bytes, payload: payload)
        let b = Array(payload)
        guard b.count >= 16 else { throw DecodeError.malformedBlob }
        var index = 16
        func section() throws -> Data {
            guard b.count - index >= 2 else { throw DecodeError.malformedBlob }
            // BitReader reads these aligned 16-bit counts least-significant bit
            // first, unlike the big-endian HIID header and read request.
            let length = Int(b[index]) | (Int(b[index + 1]) << 8)
            index += 2
            guard length <= b.count - index else { throw DecodeError.malformedBlob }
            defer { index += length }
            return Data(b[index..<(index + length)])
        }
        let selection = try section()
        let prodRegs = try section()
        let business = try section()
        guard selection.count == 6, prodRegs.count >= 4, index == b.count else {
            throw DecodeError.malformedBlob
        }
        return Blob(fittingIDBytes: Data(b.prefix(16)), selection: selection,
                    prodRegs: prodRegs, businessData: business)
    }
}
