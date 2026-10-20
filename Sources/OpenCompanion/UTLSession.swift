import CompanionCore
import CryptoKit
import Foundation

/// A deliberately narrow application channel: discovery and consumer EQ only.
/// It uses nonexclusive consumer sessions and COMMAND transactions only.
@MainActor
final class UTLSession {
    enum SessionError: LocalizedError {
        case unavailable(String), timeout, disconnected, authentication
        var errorDescription: String? {
            switch self {
            case .unavailable(let message): return message
            case .timeout: return "Advanced channel timed out."
            case .disconnected: return "Advanced channel disconnected."
            case .authentication: return "Advanced channel authentication failed."
            }
        }
    }
    static var defaultKeyURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Open Companion/utl-auth.json")
    }
    static func describe(_ error: any Error) -> String {
        if let error = error as? UTLProtocol.CodecError {
            switch error {
            case .responseStatus(let status):
                if status == 0xD9 { return "Consumer command transaction was not found (0xD9)." }
                return String(format: "Device response status 0x%02X.", status)
            case .malformed(let detail): return "Invalid advanced response: \(detail)."
            case .unsupported(let detail): return "Unsupported advanced format: \(detail)."
            case .unexpectedSequence(let expected, let received): return "Advanced packet sequence mismatch (\(expected), \(received))."
            case .insufficientCredit: return "Advanced transport has no sending credits."
            }
        }
        return error.localizedDescription
    }

    let channel: UInt8
    let clientID: UInt32
    private let write: @MainActor (String, Data) async throws -> Void
    private let progress: @MainActor (String) -> Void
    private let diagnostic: @MainActor (String) -> Void
    private let payloadMTU: Int
    private var credits: UTLProtocol.Credits
    private var transportDecoder = UTLProtocol.TransportDecoder()
    private var messageDecoder = UTLProtocol.MessageDecoder()
    private var frames: [UTLProtocol.TransportFrame] = []
    private var messages: [UTLProtocol.ServiceMessage] = []
    private var hash: Data?
    private var challenge: Data?
    private var failure: (any Error)?
    private var requestIdentifier: UInt8 = 1
    private var transportMTU = 64
    private(set) var services: [UTLProtocol.Service] = []
    private(set) var isReady = false
    private var openAttempted = false
    private var consumerOpenAttempted = false
    private var sessionService: UTLProtocol.Service?
    private var transactionID: UInt16 = 0
    private var activeTransaction: UInt16?
    private var commandBusy = false
    private var commandPoisoned = false
    private final class PacketTicket {
        let data: Data
        var result: Result<Void, any Error>?
        init(_ data: Data) { self.data = data }
    }
    private var outgoing: [PacketTicket] = []
    private var draining = false

    init(info: UTLProtocol.GattInformation, physicalATTMTU: Int, progress: @escaping @MainActor (String) -> Void = { _ in },
         diagnostic: @escaping @MainActor (String) -> Void = { _ in },
         write: @escaping @MainActor (String, Data) async throws -> Void) throws {
        guard info.freeConnections > 0,
              let channelIndex = info.channels.prefix(Int(info.maximumChannels)).firstIndex(where: { $0.state == .closed }) else {
            throw SessionError.unavailable("No free advanced channel. Existing channels will not be displaced.")
        }
        channel = UInt8(channelIndex)
        clientID = UInt32(truncatingIfNeeded: ProcessInfo.processInfo.processIdentifier)
        payloadMTU = try info.negotiatedAdaptationMTU(physicalATTMTU: physicalATTMTU)
        credits = try UTLProtocol.Credits(initialSequence: 0)
        self.write = write
        self.progress = progress
        self.diagnostic = diagnostic
    }

    static func loadKey(_ url: URL) throws -> Data {
        struct Configuration: Decodable { let key: String }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let permissions = attributes[.posixPermissions] as? NSNumber, permissions.intValue & 0o077 != 0 {
            throw SessionError.unavailable("Advanced key file must be private (chmod 600).")
        }
        let configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
        let hex = Array(configuration.key.utf8)
        guard hex.count == 32 else { throw SessionError.unavailable("Advanced key file is invalid.") }
        var data = Data()
        for offset in stride(from: 0, to: hex.count, by: 2) {
            guard let value = UInt8(String(bytes: hex[offset..<(offset + 2)], encoding: .utf8)!, radix: 16) else {
                throw SessionError.unavailable("Advanced key file is invalid.")
            }
            data.append(value)
        }
        return data
    }

    func start(key: Data) async throws {
        guard key.count == 16 else { throw SessionError.authentication }
        progress("Opening advanced channel")
        let open = try UTLProtocol.openChannel(clientID: clientID, channel: channel, initialSequence: 0)
        // A lost ATT acknowledgement does not prove that the peer missed open.
        // Cleanup is still scoped to this process client ID and chosen channel.
        openAttempted = true
        try await write(UTLProtocol.control, open)
        let clientChallenge = Data((0..<14).map { _ in UInt8.random(in: 1...255) })
        try await write(UTLProtocol.control, UTLProtocol.authenticationFrame(clientID: clientID, channel: channel, isProof: false, challengeOrProof: clientChallenge))
        try await waitUntil { self.hash != nil && self.challenge != nil }
        guard let hash, let challenge else { throw SessionError.authentication }
        let expectedHash = Data(SHA256.hash(data: challenge + clientChallenge + key).prefix(14))
        // Fixed-length accumulated comparison avoids exposing partial proof matches.
        let difference = zip(hash, expectedHash).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) }
        guard hash.count == expectedHash.count, difference == 0 else { throw SessionError.authentication }
        let proof = Data(SHA256.hash(data: clientChallenge + challenge + key).prefix(14))
        try await write(UTLProtocol.control, UTLProtocol.authenticationFrame(clientID: clientID, channel: channel, isProof: true, challengeOrProof: proof))
        progress("Advanced channel authenticated")
        try await send(UTLProtocol.negotiationRequest(maximumMTU: 256).data)
        try await waitUntil { !self.frames.isEmpty }
        transportMTU = try UTLProtocol.negotiatedTransportMTU(from: frames.removeFirst())
        let response = try await request(handle: 0, opcode: 1)
        services = try UTLProtocol.services(from: response)
        progress("Service registry read: " + services.filter(\.isAvailable).map { String(format: "%08X/%u.%u", $0.id, $0.major, $0.minor) }.joined(separator: ","))
        try await openConsumerSession()
        isReady = true
    }

    func stop() async {
        isReady = false
        if consumerOpenAttempted, let sessionService {
            if let activeTransaction {
                _ = try? await request(handle: sessionService.handle, opcode: 9,
                                       payload: UTLConsumerSession.transactionPayload(id: activeTransaction, starting: false))
                self.activeTransaction = nil
            }
            _ = try? await request(handle: sessionService.handle, opcode: 1)
            consumerOpenAttempted = false
        }
        if openAttempted { try? await write(UTLProtocol.control, UTLProtocol.closeChannel(clientID: clientID, channel: channel)) }
        openAttempted = false
        failure = SessionError.disconnected
    }
    func disconnected() {
        failure = SessionError.disconnected; isReady = false; openAttempted = false
        consumerOpenAttempted = false; activeTransaction = nil
    }

    func receiveControl(_ data: Data) {
        do {
            switch try UTLProtocol.ControlNotification(data: data) {
            case .serverHash(let id, let channelKey, let value):
                if id == clientID, channelKey == channel << 4 { hash = value }
            case .serverChallenge(let id, let channelKey, let value):
                if id == clientID, channelKey == channel << 4 { challenge = value }
            case .closed(let id, let closedChannel, _):
                if id == clientID, closedChannel == channel { disconnected() }
            case .closing(let id, _):
                if id == clientID {
                    enqueue(try credits.keepAlive())
                }
            default: break
            }
        } catch { failure = error; isReady = false }
    }

    func receiveOutput(_ data: Data) {
        do {
            let incoming = try credits.receive(data)
            // Credits has already allocated these packets' sequence numbers.
            // Enqueue before any await; one FIFO drainer preserves that order.
            for reply in incoming.replies { enqueue(reply) }
            for frame in try transportDecoder.append(incoming.payload) {
                if frame.kind == .control { frames.append(frame) }
                else if let message = try messageDecoder.receive(frame) {
                    if message.messageType == .response { messages.append(message) }
                    // Events never trigger a setting write or binaural synchronization.
                }
            }
        } catch { failure = error; isReady = false }
    }

    func equalizer(microphone: Bool, stepDB: Double) async throws -> OticonEqualizer.State {
        let service = try equalizerService(microphone: microphone)
        let response = try await consumerRequest(handle: service.handle, opcode: microphone ? 3 : 0)
        let label = microphone ? "Microphone EQ" : "Streaming EQ"
        diagnostic("\(label) response: bytes=\(response.payload.count), \(UTLAdvanced.equalizerPayloadSummary(response.payload)), hexPrefix=\(response.payload.prefix(256).hexString)")
        do {
            let sdkRange: ClosedRange<Double>? = service.major == 1 ? (microphone ? -6.0...6.0 : -12.0...6.0) : nil
            return try UTLAdvanced.equalizerState(response.payload, stepDB: stepDB, sdkConsumerRangeDB: sdkRange)
        } catch { throw UTLAdvanced.ParseError("\(label) \(service.major).\(service.minor): \(error.localizedDescription)") }
    }
    func equalizerStep() async throws -> Double {
        let service = try equalizerService(microphone: false)
        let response = try await consumerRequest(handle: service.handle, opcode: 2)
        diagnostic("EQ info response: bytes=\(response.payload.count), \(UTLAdvanced.equalizerPayloadSummary(response.payload)), hexPrefix=\(response.payload.prefix(256).hexString)")
        do { return try UTLAdvanced.equalizerInfo(response.payload) }
        catch { throw UTLAdvanced.ParseError("EQ info \(service.major).\(service.minor): \(error.localizedDescription)") }
    }
    func setEqualizer(microphone: Bool, steps: [Int], expected: OticonEqualizer.State) async throws -> OticonEqualizer.State {
        try expected.validate(steps)
        let service = try equalizerService(microphone: microphone)
        _ = try await consumerRequest(handle: service.handle, opcode: microphone ? 4 : 1, payload: UTLCBOR.unsignedVector(steps))
        let state = try await equalizer(microphone: microphone, stepDB: expected.stepDB)
        guard state.rawSteps == steps else { throw SessionError.unavailable("EQ request accepted, but hearing aid reports a different value.") }
        return state
    }

    private func equalizerService(microphone: Bool) throws -> UTLProtocol.Service {
        guard let service = services.first(where: { UTLAdvanced.supportsEqualizer($0, microphone: microphone) }) else {
            throw SessionError.unavailable("This aid did not advertise a supported \(microphone ? "microphone" : "streaming") EQ contract.")
        }
        return service
    }
    private func openConsumerSession() async throws {
        guard let service = services.first(where: UTLConsumerSession.supports) else {
            throw SessionError.unavailable("No supported consumer session contract was advertised.")
        }
        sessionService = service
        let epoch = Date(timeIntervalSince1970: 1_577_836_800)
        let seconds = Date().timeIntervalSince(epoch)
        guard seconds >= 0, seconds <= Double(UInt32.max) else { throw SessionError.unavailable("System date cannot be represented in a consumer session.") }
        let components = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0").split(separator: ".").compactMap { UInt16($0) }
        let version: (UInt16, UInt16, UInt16) = (components.first ?? 0, components.count > 1 ? components[1] : 2, components.count > 2 ? components[2] : 0)
        let payload = try UTLConsumerSession.openPayload(service: service,
            privateToken: UInt32.random(in: 1...UInt32.max), timeSince2020: UInt32(seconds), version: version)
        progress("Opening nonexclusive consumer session")
        consumerOpenAttempted = true
        _ = try await request(handle: service.handle, opcode: 0, payload: payload)
        _ = try await request(handle: service.handle, opcode: 4)
        progress("Consumer transaction pipeline opened")
    }
    private func consumerRequest(handle: UInt8, opcode: UInt8, payload: Data = Data()) async throws -> UTLProtocol.ServiceMessage {
        guard let sessionService, consumerOpenAttempted, !commandBusy, !commandPoisoned else {
            throw SessionError.unavailable("Consumer command session is unavailable or busy.")
        }
        commandBusy = true
        defer { commandBusy = false }
        transactionID = transactionID &+ 1
        if transactionID == 0 { transactionID = 1 }
        let id = transactionID
        // Mark before awaiting ACK so ambiguous starts are cancelled on cleanup.
        activeTransaction = id
        do {
            _ = try await request(handle: sessionService.handle, opcode: 7,
                                  payload: UTLConsumerSession.transactionPayload(id: id, starting: true))
            progress(String(format: "Consumer command %02X on service handle %u", opcode, handle))
            let response = try await request(handle: handle, opcode: opcode, payload: payload)
            _ = try await request(handle: sessionService.handle, opcode: 8,
                                  payload: UTLConsumerSession.transactionPayload(id: id, starting: false))
            activeTransaction = nil
            return response
        } catch {
            do {
                _ = try await request(handle: sessionService.handle, opcode: 9,
                                      payload: UTLConsumerSession.transactionPayload(id: id, starting: false))
                activeTransaction = nil
            } catch {
                // Keep the ID for stop() to attempt owned cleanup. A failed
                // cancellation must never allow reuse of an unknown transaction.
                commandPoisoned = true
                isReady = false
            }
            throw error
        }
    }
    private func request(handle: UInt8, opcode: UInt8, payload: Data = Data()) async throws -> UTLProtocol.ServiceMessage {
        let identifier = requestIdentifier
        requestIdentifier = requestIdentifier &+ 2
        if requestIdentifier == 0 { requestIdentifier = 1 }
        let body = Data([0x0C, identifier, handle, opcode]) + payload
        guard body.count + 3 <= transportMTU else { throw SessionError.unavailable("Request exceeds negotiated transport MTU.") }
        try await send(UTLProtocol.TransportFrame(kind: .data, final: true, payload: body).data)
        try await waitUntil { self.messages.contains { $0.identifier == identifier && $0.serviceHandle == handle } }
        guard let index = messages.firstIndex(where: { $0.identifier == identifier && $0.serviceHandle == handle }) else { throw SessionError.timeout }
        let response = messages.remove(at: index)
        guard response.status?.isSuccess == true else { throw UTLProtocol.CodecError.responseStatus(response.code) }
        return response
    }
    private func send(_ data: Data) async throws {
        for offset in stride(from: 0, to: data.count, by: payloadMTU) {
            try await waitUntil { self.credits.serverCredits > 0 }
            let chunk = Data(data[offset..<min(data.count, offset + payloadMTU)])
            let packet = try credits.send(chunk)
            let ticket = enqueue(packet)
            try await waitUntil { ticket.result != nil }
            try ticket.result!.get()
        }
    }
    @discardableResult private func enqueue(_ data: Data) -> PacketTicket {
        let ticket = PacketTicket(data)
        outgoing.append(ticket)
        if !draining {
            draining = true
            Task { await self.drain() }
        }
        return ticket
    }
    private func drain() async {
        defer { draining = false }
        while !outgoing.isEmpty {
            let ticket = outgoing.removeFirst()
            if let failure { ticket.result = .failure(failure); continue }
            do {
                try await write(UTLProtocol.inputs[Int(channel)], ticket.data)
                ticket.result = .success(())
            } catch {
                ticket.result = .failure(error)
                failure = error; isReady = false
            }
        }
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !condition() {
            if let failure { throw failure }
            try Task.checkCancellation()
            guard Date() < deadline else { throw SessionError.timeout }
            try await Task.sleep(for: .milliseconds(20))
        }
        if let failure { throw failure }
    }
}
