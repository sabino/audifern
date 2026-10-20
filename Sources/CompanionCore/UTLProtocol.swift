import Foundation

/// Independently authored codec for the statically recovered Demant UTL wire
/// format. This has no Bluetooth side effects and contains no authentication key.
/// Identifiers, field order, byte order and status rules: docs/managed-protocol.md.
public enum UTLProtocol {
    public static let service = "BA50125D-0806-42AB-8BF1-22E0B954A8FA"
    public static let control = "43C8465E-BA80-451D-8098-57716B4FDBE5"
    public static let information = "E6C02A45-A0E5-41F2-9CD1-C1FAB9EC0C3E"
    public static let inputs = [
        "855C8579-17B7-40A8-BE4F-AD574357F797", "6D6A8B8F-544E-4EF1-BE91-C60DB8E70884",
        "F6C47754-8BD2-4CC2-BF0B-FDEE78FA812E", "46C9AFB1-8FA2-4594-AB2E-F5576F6BC484"
    ]
    public static let outputs = [
        "5EB7FF93-EBEB-479C-85AB-526F25482545", "ED5F901B-FB08-452C-8D01-46B6C9C1BCC5",
        "80911332-EAD5-4DA0-9BFA-4D6286032E25", "689E73AF-BCAC-4280-920D-4710CE2FBB68"
    ]

    public enum CodecError: Error, Equatable, Sendable {
        case malformed(String)
        case unsupported(String)
        case unexpectedSequence(expected: UInt8, received: UInt8)
        case insufficientCredit
        case responseStatus(UInt8)
    }

    public struct Status: Equatable, Sendable {
        public let rawValue: UInt8
        public var group: UInt8 { rawValue >> 5 }
        public var detail: UInt8 { rawValue & 31 }
        /// Accepted (0x41) is deliberately not treated as completed (0x40).
        public var isSuccess: Bool { rawValue == 0x40 }
        public var isAccepted: Bool { rawValue == 0x41 }
        public var isContextSpecific: Bool { group == 6 || group == 7 }
        public init(_ rawValue: UInt8) { self.rawValue = rawValue }
    }

    public struct Channel: Equatable, Sendable {
        public enum State: UInt8, Sendable { case none = 0, open = 1, closed = 2, reserved = 3 }
        public let state: State
        public let lastError: UInt8
        init(_ byte: UInt8) { state = State(rawValue: byte >> 6)!; lastError = byte & 3 }
    }

    public struct GattInformation: Equatable, Sendable {
        public let transportMajor: UInt8
        public let transportMinor: UInt8
        public let adaptationMajor: UInt8
        public let adaptationMinor: UInt8
        public let adaptationMTU: Int
        public let freeConnections: UInt8
        public let maximumChannels: UInt8
        public let channels: [Channel]
        public var isVersionCompatible: Bool { transportMajor == 1 && adaptationMajor == 1 }

        public init(data: Data) throws {
            let b = Array(data)
            guard b.count == 12, b[7] <= 4 else { throw CodecError.malformed("GATT information") }
            transportMajor = b[0]; transportMinor = b[1]
            adaptationMajor = b[2]; adaptationMinor = b[3]
            adaptationMTU = Int(b[4]) << 8 | Int(b[5])
            freeConnections = b[6]; maximumChannels = b[7]
            channels = b[8..<12].map(Channel.init)
        }

        /// physicalATTMTU includes the ATT opcode and handle. UTL reserves one
        /// additional GATT adaptation control byte, as does the shipped client.
        public func negotiatedAdaptationMTU(physicalATTMTU: Int) throws -> Int {
            guard isVersionCompatible else { throw CodecError.unsupported("UTL major version") }
            let mtu = min(adaptationMTU, min(physicalATTMTU, 244) - 4)
            guard (17...244).contains(mtu) else { throw CodecError.malformed("Adaptation MTU") }
            return mtu
        }
    }

    public enum ControlNotification: Equatable, Sendable {
        case status(freeConnections: UInt8, maximumChannels: UInt8, channels: [Channel])
        case closed(clientID: UInt32, channel: UInt8, reason: Status)
        /// The inspected closing handler consumes only the client ID. Preserve
        /// trailing bytes without assigning undocumented channel/status fields.
        case closing(clientID: UInt32, extra: Data)
        case serverHash(clientID: UInt32, channelKeyIndex: UInt8, value: Data)
        case serverChallenge(clientID: UInt32, channelKeyIndex: UInt8, value: Data)

        public init(data: Data) throws {
            let b = Array(data)
            guard let opcode = b.first else { throw CodecError.malformed("Empty control notification") }
            switch opcode {
            case 0x80:
                guard b.count == 7, b[2] <= 4 else { throw CodecError.malformed("Channel status") }
                self = .status(freeConnections: b[1], maximumChannels: b[2], channels: b[3...6].map(Channel.init))
            case 0x40:
                guard b.count == 7, b[5] < 4 else { throw CodecError.malformed("Channel closing notification") }
                let id = read32(b, 1)
                self = .closed(clientID: id, channel: b[5], reason: Status(b[6]))
            case 0x41:
                guard b.count >= 5 else { throw CodecError.malformed("Channel closing notification") }
                self = .closing(clientID: read32(b, 1), extra: Data(b.dropFirst(5)))
            case 0x42, 0x43:
                guard b.count == 20, b[5] >> 4 < 4 else { throw CodecError.malformed("Challenge notification") }
                let id = read32(b, 1), value = Data(b[6...19])
                self = opcode == 0x42 ? .serverHash(clientID: id, channelKeyIndex: b[5], value: value)
                    : .serverChallenge(clientID: id, channelKeyIndex: b[5], value: value)
            default: throw CodecError.unsupported("Control opcode")
            }
        }
    }

    public static func openChannel(clientID: UInt32, channel: UInt8, initialSequence: UInt8,
                                   receiveCredits: UInt8 = 100) throws -> Data {
        guard channel < 4, initialSequence < 16, receiveCredits > 0 else {
            throw CodecError.malformed("Channel-open fields")
        }
        return Data([1] + bytes32(clientID) + [channel, initialSequence, receiveCredits, 0])
    }

    public static func closeChannel(clientID: UInt32, channel: UInt8) throws -> Data {
        guard channel < 4 else { throw CodecError.malformed("Channel index") }
        return Data([2] + bytes32(clientID) + [channel, 0x40])
    }

    /// Encodes an already supplied challenge or proof. Computing either proof
    /// requires separately provisioned key material; no default exists here.
    public static func authenticationFrame(clientID: UInt32, channel: UInt8, isProof: Bool,
                                            challengeOrProof: Data) throws -> Data {
        guard channel < 4, challengeOrProof.count == 14 else { throw CodecError.malformed("Authentication fields") }
        return Data([isProof ? 4 : 3] + bytes32(clientID) + [channel << 4]) + challengeOrProof
    }

    public struct GattPacket: Equatable, Sendable {
        public let sequence: UInt8
        public let credits: UInt8
        public let payload: Data
        public var isControl: Bool { credits == 15 }

        public init(data: Data) throws {
            guard let first = data.first else { throw CodecError.malformed("Missing GATT control byte") }
            sequence = first & 15; credits = first >> 4; payload = Data(data.dropFirst())
            if isControl, payload.count != 2 { throw CodecError.malformed("GATT control PDU") }
        }

        public init(sequence: UInt8, credits: UInt8, payload: Data) throws {
            guard sequence < 16, credits < 16, credits != 15 || payload.count == 2 else {
                throw CodecError.malformed("GATT packet fields")
            }
            self.sequence = sequence; self.credits = credits; self.payload = payload
        }

        public var data: Data { Data([(credits << 4) | sequence]) + payload }
    }

    /// A deterministic credit ledger. Callers must send returned packets in
    /// order and discard the ledger if sending fails. No I/O happens here.
    public struct Credits: Sendable {
        public private(set) var sendSequence: UInt8
        public private(set) var expectedReceiveSequence: UInt8
        public private(set) var serverCredits = 0
        public private(set) var clientCredits: Int
        public let maximumClientCredits: Int
        public let replenishmentThreshold: Int

        public init(initialSequence: UInt8, maximumClientCredits: UInt8 = 100,
                    replenishmentThreshold: UInt8 = 50) throws {
            guard initialSequence < 16, maximumClientCredits > 0,
                  replenishmentThreshold <= maximumClientCredits else { throw CodecError.malformed("Credit configuration") }
            sendSequence = initialSequence; expectedReceiveSequence = initialSequence
            clientCredits = Int(maximumClientCredits); self.maximumClientCredits = Int(maximumClientCredits)
            self.replenishmentThreshold = Int(replenishmentThreshold)
        }

        public struct Incoming: Equatable, Sendable {
            public let payload: Data
            public let replies: [Data]
        }

        public mutating func receive(_ data: Data) throws -> Incoming {
            var next = self
            let result = try next.consume(data)
            self = next
            return result
        }

        private mutating func consume(_ data: Data) throws -> Incoming {
            let packet = try GattPacket(data: data)
            guard packet.sequence == expectedReceiveSequence else {
                throw CodecError.unexpectedSequence(expected: expectedReceiveSequence, received: packet.sequence)
            }
            var replies: [Data] = []
            if packet.isControl {
                let p = Array(packet.payload)
                switch p[0] {
                case 0x81: serverCredits += Int(p[1])
                case 0x83:
                    let discarded = min(serverCredits, Int(p[1]))
                    serverCredits -= discarded
                    replies.append(try controlPacket(opcode: 2, amount: UInt8(discarded)))
                default: throw CodecError.unsupported("GATT credit opcode")
                }
            } else {
                guard clientCredits > 0 else { throw CodecError.insufficientCredit }
                clientCredits -= 1; serverCredits += Int(packet.credits)
                if clientCredits < replenishmentThreshold {
                    let amount = maximumClientCredits - clientCredits
                    replies.append(try controlPacket(opcode: 1, amount: UInt8(amount)))
                    clientCredits += amount
                }
            }
            guard serverCredits <= 65535 else { throw CodecError.malformed("Credit overflow") }
            expectedReceiveSequence = (expectedReceiveSequence + 1) & 15
            return Incoming(payload: packet.isControl ? Data() : packet.payload, replies: replies)
        }

        public mutating func send(_ payload: Data) throws -> Data {
            guard serverCredits > 0 else { throw CodecError.insufficientCredit }
            let returned = min(14, maximumClientCredits - clientCredits)
            let packet = try GattPacket(sequence: sendSequence, credits: UInt8(returned), payload: payload).data
            serverCredits -= 1; clientCredits += returned; sendSequence = (sendSequence + 1) & 15
            return packet
        }

        public mutating func keepAlive() throws -> Data { try controlPacket(opcode: 1, amount: 0) }

        private mutating func controlPacket(opcode: UInt8, amount: UInt8) throws -> Data {
            let result = try GattPacket(sequence: sendSequence, credits: 15, payload: Data([opcode, amount])).data
            sendSequence = (sendSequence + 1) & 15
            return result
        }
    }

    public struct TransportFrame: Equatable, Sendable {
        public enum Kind: UInt8, Sendable { case control = 0, data = 1, continuation = 2 }
        public let kind: Kind
        public let final: Bool
        public let secure: Bool
        public let identifier: UInt8?
        public let opcode: UInt8?
        public let totalLength: Int?
        public let payload: Data

        public init(kind: Kind, final: Bool, secure: Bool = false, identifier: UInt8? = nil,
                    opcode: UInt8? = nil, totalLength: Int? = nil, payload: Data) throws {
            guard payload.count <= 16383 else { throw CodecError.malformed("Transport payload length") }
            if kind == .control {
                guard identifier != nil, opcode != nil, totalLength == nil else { throw CodecError.malformed("Transport control fields") }
            } else {
                guard !payload.isEmpty, identifier == nil, opcode == nil else { throw CodecError.malformed("Transport data fields") }
                if kind == .data && !final {
                    guard let totalLength, (1...256).contains(totalLength), totalLength > payload.count else {
                        throw CodecError.malformed("Fragmented transport length")
                    }
                } else if totalLength != nil { throw CodecError.malformed("Unexpected total length") }
            }
            self.kind = kind; self.final = final; self.secure = secure
            self.identifier = identifier; self.opcode = opcode; self.totalLength = totalLength; self.payload = payload
        }

        public var data: Data {
            let first = kind.rawValue << 6 | (final ? 0x20 : 0) | (secure ? 0x10 : 0)
            if kind == .control {
                return Data([first] + bytes16(payload.count) + [identifier!, opcode!]) + payload
            }
            let extra = totalLength.map(bytes16) ?? []
            return Data([first] + bytes16(payload.count + extra.count) + extra) + payload
        }
    }

    /// Accepts arbitrary ATT chunk boundaries and retains incomplete bytes.
    public struct TransportDecoder: Sendable {
        private var pending: [UInt8] = []
        public init() {}
        public var pendingByteCount: Int { pending.count }

        public mutating func append(_ data: Data) throws -> [TransportFrame] {
            var next = pending + Array(data)
            guard next.count <= 131072 else { throw CodecError.malformed("Transport buffer limit") }
            var result: [TransportFrame] = []
            while next.count >= 3 {
                guard next[0] & 15 == 0, let kind = TransportFrame.Kind(rawValue: next[0] >> 6) else {
                    throw CodecError.unsupported("Transport flags/type")
                }
                let length = Int(next[1]) << 8 | Int(next[2])
                guard length <= 16385 else { throw CodecError.malformed("Transport length limit") }
                let frameLength = 3 + length + (kind == .control ? 2 : 0)
                if next.count < frameLength { break }
                let final = next[0] & 0x20 != 0, secure = next[0] & 0x10 != 0
                let hasTotal = kind == .data && !final
                guard !hasTotal || length >= 3 else { throw CodecError.malformed("Missing transport total") }
                let start = kind == .control || hasTotal ? 5 : 3
                result.append(try TransportFrame(kind: kind, final: final, secure: secure,
                    identifier: kind == .control ? next[3] : nil, opcode: kind == .control ? next[4] : nil,
                    totalLength: hasTotal ? Int(next[3]) << 8 | Int(next[4]) : nil,
                    payload: Data(next[start..<frameLength])))
                next.removeFirst(frameLength)
            }
            pending = next
            return result
        }
    }

    public struct MessagePart: Equatable, Sendable {
        public enum Kind: UInt8, Sendable { case header = 0, data = 1, trailer = 2 }
        public enum MessageType: UInt8, Sendable { case request = 0, response = 1, event = 2 }
        public let kind: Kind
        public let messageType: MessageType
        public let endFragment: Bool
        public let endMessage: Bool
        public let identifier: UInt8
        public let serviceHandle: UInt8
        public let code: UInt8?
        public let payload: Data

        public init(data: Data) throws {
            let b = Array(data)
            guard b.count >= 3, b[0] & 3 == 0, let kind = Kind(rawValue: b[0] >> 6),
                  let type = MessageType(rawValue: (b[0] >> 4) & 3), kind == .data || b.count >= 4 else {
                throw CodecError.malformed("Service message part")
            }
            self.kind = kind; messageType = type; endFragment = b[0] & 4 != 0; endMessage = b[0] & 8 != 0
            guard !endMessage || endFragment else { throw CodecError.malformed("End-message without end-fragment") }
            identifier = b[1]; serviceHandle = b[2]; code = kind == .data ? nil : b[3]
            payload = Data(b.dropFirst(kind == .data ? 3 : 4))
        }
    }

    public struct ServiceMessage: Equatable, Sendable {
        public let messageType: MessagePart.MessageType
        public let identifier: UInt8
        public let serviceHandle: UInt8
        /// An opcode in requests/events; a status code in responses.
        public let code: UInt8
        public let payload: Data
        public var status: Status? { messageType == .response ? Status(code) : nil }
    }

    /// Reassembles transport fragments and service-message fragments separately.
    /// Control transport frames (MTU negotiation) must be handled by the caller.
    public struct MessageDecoder: Sendable {
        private var transportBytes = Data()
        private var transportTotal: Int?
        private var partial: ServiceMessage?
        private var previousPartKind: MessagePart.Kind?
        private var previousPartEnded = false
        public init() {}

        public mutating func receive(_ frame: TransportFrame) throws -> ServiceMessage? {
            var next = self
            let message = try next.consume(frame)
            self = next
            return message
        }

        private mutating func consume(_ frame: TransportFrame) throws -> ServiceMessage? {
            guard !frame.secure else { throw CodecError.unsupported("Secure transport payload") }
            guard frame.kind != .control else { throw CodecError.unsupported("Control frame is not a service message") }
            if frame.kind == .data {
                guard transportBytes.isEmpty else { throw CodecError.malformed("Nested transport message") }
                transportTotal = frame.totalLength
            } else if transportBytes.isEmpty { throw CodecError.malformed("Orphan transport continuation") }
            transportBytes.append(frame.payload)
            guard transportBytes.count <= 65535 else { throw CodecError.malformed("Message buffer limit") }
            if let transportTotal, transportBytes.count > transportTotal { throw CodecError.malformed("Transport total overflow") }
            guard frame.final else { return nil }
            if let transportTotal, transportBytes.count != transportTotal { throw CodecError.malformed("Transport total mismatch") }
            let part = try MessagePart(data: transportBytes)
            transportBytes.removeAll(keepingCapacity: true); transportTotal = nil
            if part.messageType == .event {
                guard part.kind == .header, part.endMessage, let code = part.code else { throw CodecError.unsupported("Fragmented event") }
                return ServiceMessage(messageType: .event, identifier: part.identifier, serviceHandle: part.serviceHandle, code: code, payload: part.payload)
            }
            if part.kind == .header {
                guard partial == nil, let code = part.code else { throw CodecError.malformed("Nested service header") }
                partial = ServiceMessage(messageType: part.messageType, identifier: part.identifier,
                    serviceHandle: part.serviceHandle, code: code, payload: part.payload)
            } else {
                guard let prior = partial, prior.identifier == part.identifier,
                      prior.serviceHandle == part.serviceHandle, prior.messageType == part.messageType else {
                    throw CodecError.malformed("Service fragment identity")
                }
                if part.kind == .trailer && !previousPartEnded { throw CodecError.malformed("Premature trailer") }
                if part.kind == .data && previousPartKind == .data && previousPartEnded {
                    throw CodecError.malformed("Data after end-fragment")
                }
                guard prior.payload.count + part.payload.count <= 65535 else { throw CodecError.malformed("Service payload limit") }
                partial = ServiceMessage(messageType: prior.messageType, identifier: prior.identifier,
                    serviceHandle: prior.serviceHandle, code: part.code ?? prior.code, payload: prior.payload + part.payload)
            }
            previousPartKind = part.kind; previousPartEnded = part.endFragment
            if part.endMessage {
                let result = partial; partial = nil; previousPartKind = nil; previousPartEnded = false
                return result
            }
            return nil
        }
    }

    public struct Service: Equatable, Sendable {
        public let id: UInt32
        public let handle: UInt8
        public let major: UInt8
        public let minor: UInt8
        public let status: UInt8
        public var isAvailable: Bool { status == 0xFF }
    }

    public static func services(from response: ServiceMessage) throws -> [Service] {
        try checkResponse(response, expectedHandle: 0)
        let b = Array(response.payload)
        guard b.count % 8 == 0 else { throw CodecError.malformed("Service discovery record length") }
        var result: [Service] = [], ids = Set<UInt32>(), handles = Set<UInt8>()
        for offset in stride(from: 0, to: b.count, by: 8) {
            let value = Service(id: read32(b, offset), handle: b[offset + 4], major: b[offset + 5], minor: b[offset + 6], status: b[offset + 7])
            guard ids.insert(value.id).inserted, !value.isAvailable || handles.insert(value.handle).inserted else {
                throw CodecError.malformed("Ambiguous service discovery")
            }
            result.append(value)
        }
        return result
    }

    /// A single, complete read-only service request, before transport/GATT wrapping.
    public static func discoveryRequest(identifier: UInt8) throws -> Data {
        try readRequest(identifier: identifier, handle: 0, opcode: 1)
    }

    public static func volumeReadRequest(identifier: UInt8, service: Service) throws -> Data {
        guard service.id == 0x0200000D, service.isAvailable, service.major == 1, (1...3).contains(service.minor) else {
            throw CodecError.unsupported("Volume service contract")
        }
        return try readRequest(identifier: identifier, handle: service.handle, opcode: 0)
    }

    public static func programReadRequest(identifier: UInt8, service: Service) throws -> Data {
        guard service.id == 0x0200000E, service.isAvailable, service.major == 2, service.minor <= 1 else {
            throw CodecError.unsupported("Program service contract")
        }
        return try readRequest(identifier: identifier, handle: service.handle, opcode: 0)
    }

    private static func readRequest(identifier: UInt8, handle: UInt8, opcode: UInt8) throws -> Data {
        guard identifier != 0, identifier & 1 == 1 else { throw CodecError.malformed("Request identifier must be odd and nonzero") }
        return Data([0x0C, identifier, handle, opcode])
    }

    public struct Volume: Equatable, Sendable {
        public let value: Int
        public let range: ClosedRange<Int>
    }

    public static func volume(from response: ServiceMessage, service: Service) throws -> Volume {
        _ = try volumeReadRequest(identifier: 1, service: service)
        try checkResponse(response, expectedHandle: service.handle)
        let b = response.payload.map { Int(Int8(bitPattern: $0)) }
        guard b.count == 3, b[1] <= b[2], (b[1]...b[2]).contains(b[0]) else { throw CodecError.malformed("Volume response") }
        return Volume(value: b[0], range: b[1]...b[2])
    }

    public static func program(from response: ServiceMessage, service: Service) throws -> UInt8 {
        _ = try programReadRequest(identifier: 1, service: service)
        try checkResponse(response, expectedHandle: service.handle)
        guard response.payload.count == 1 else { throw CodecError.malformed("Program response") }
        return response.payload.first!
    }

    private static func checkResponse(_ response: ServiceMessage, expectedHandle: UInt8) throws {
        guard response.messageType == .response, response.serviceHandle == expectedHandle else { throw CodecError.malformed("Response identity") }
        guard response.status?.isSuccess == true else { throw CodecError.responseStatus(response.code) }
    }

    public static func negotiationRequest(maximumMTU: Int = 65535) throws -> TransportFrame {
        guard (11...65535).contains(maximumMTU) else { throw CodecError.malformed("Transport MTU") }
        return try TransportFrame(kind: .control, final: true, identifier: 1, opcode: 1, payload: Data(bytes16(maximumMTU)))
    }

    public static func negotiatedTransportMTU(from frame: TransportFrame) throws -> Int {
        guard frame.kind == .control, frame.final, !frame.secure, frame.identifier == 1,
              frame.opcode == 2, frame.payload.count == 3 else { throw CodecError.malformed("MTU negotiation response") }
        let b = Array(frame.payload)
        guard Status(b[2]).isSuccess else { throw CodecError.responseStatus(b[2]) }
        let result = Int(b[0]) << 8 | Int(b[1])
        guard result >= 11 else { throw CodecError.malformed("Negotiated transport MTU") }
        return result
    }

    private static func bytes16(_ value: Int) -> [UInt8] { [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)] }
    private static func bytes32(_ value: UInt32) -> [UInt8] { [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) } }
    private static func read32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { ($0 << 8) | UInt32(bytes[offset + $1]) }
    }
}
