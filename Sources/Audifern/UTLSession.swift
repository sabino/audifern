import CompanionCore
import CryptoKit
import Foundation

/// An owned nonexclusive channel. Consumer mode exposes the established sound
/// controls; explicit backup mode only exposes getters and the bounded HIID1009
/// read. Neither mode enters controlled fitting or a memory-write transaction.
@MainActor
final class UTLSession {
    enum Purpose { case consumer, readOnlyBackup }
    private(set) var purpose = Purpose.consumer
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
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Audifern/utl-auth.json")
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
    private let batteryUpdate: @MainActor (OticonBattery.State) -> Void
    private let acquisitionNow: @MainActor () -> Date
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
    private(set) var identificationPayload: Data?
    private(set) var equalizerMetadata: UTLAdvanced.EqualizerMetadata?
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
         batteryUpdate: @escaping @MainActor (OticonBattery.State) -> Void = { _ in },
         acquisitionNow: @escaping @MainActor () -> Date = { Date() },
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
        self.batteryUpdate = batteryUpdate
        self.acquisitionNow = acquisitionNow
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

    func start(key: Data, purpose: Purpose = .consumer) async throws {
        guard key.count == 16 else { throw SessionError.authentication }
        self.purpose = purpose
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
        identificationPayload = nil
        equalizerMetadata = nil
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
        identificationPayload = nil
        equalizerMetadata = nil
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
                    else if let service = services.first(where: OticonBattery.supports) {
                        do { if let state = try OticonBattery.eventState(message, service: service) { batteryUpdate(state) } }
                        catch { diagnostic("Battery event ignored: invalid versioned telemetry payload (\(message.payload.count) bytes).") }
                    }
                    // Events never trigger a setting write or binaural synchronization.
                }
            }
        } catch { failure = error; isReady = false }
    }

    func equalizer(microphone: Bool, stepDB: Double, deadline: Date? = nil) async throws -> OticonEqualizer.State {
        let service = try equalizerService(microphone: microphone)
        let response = try await consumerRequest(handle: service.handle, opcode: microphone ? 3 : 0, deadline: deadline)
        let label = microphone ? "Microphone EQ" : "Streaming EQ"
        diagnostic("\(label) response: bytes=\(response.payload.count), \(UTLAdvanced.equalizerPayloadSummary(response.payload)), hexPrefix=\(response.payload.prefix(256).hexString)")
        do {
            let sdkRange: ClosedRange<Double>? = service.major == 1 ? (microphone ? -6.0...6.0 : -12.0...6.0) : nil
            return try UTLAdvanced.equalizerState(response.payload, stepDB: stepDB, sdkConsumerRangeDB: sdkRange,
                                                 frequenciesHz: equalizerMetadata?.frequenciesHz)
        } catch { throw UTLAdvanced.ParseError("\(label) \(service.major).\(service.minor): \(error.localizedDescription)") }
    }
    func equalizerStep(deadline: Date? = nil) async throws -> Double {
        equalizerMetadata = nil
        let service = try equalizerService(microphone: false)
        let response = try await consumerRequest(handle: service.handle, opcode: 2, deadline: deadline)
        diagnostic("EQ info response: bytes=\(response.payload.count), \(UTLAdvanced.equalizerPayloadSummary(response.payload)), hexPrefix=\(response.payload.prefix(256).hexString)")
        do {
            let metadata = try UTLAdvanced.equalizerMetadata(response.payload, legacyConsumerScale: service.major == 1)
            equalizerMetadata = metadata
            return metadata.stepDB
        }
        catch { throw UTLAdvanced.ParseError("EQ info \(service.major).\(service.minor): \(error.localizedDescription)") }
    }
    func setEqualizer(microphone: Bool, steps: [Int], expected: OticonEqualizer.State) async throws -> OticonEqualizer.State {
        guard purpose == .consumer else { throw SessionError.unavailable("Sound writes are unavailable in a read-only backup session.") }
        try expected.validate(steps)
        let service = try equalizerService(microphone: microphone)
        _ = try await consumerRequest(handle: service.handle, opcode: microphone ? 4 : 1, payload: UTLCBOR.unsignedVector(steps))
        let state = try await equalizer(microphone: microphone, stepDB: expected.stepDB)
        guard state.rawSteps == steps else { throw SessionError.unavailable("EQ request accepted, but hearing aid reports a different value.") }
        return state
    }

    var supportsSpeechBooster: Bool {
        services.contains(where: OticonSpeechBooster.supports)
            && !services.contains { $0.isAvailable && $0.id == 0x0200001B && $0.major >= 3 }
    }
    var supportsBatteryTelemetry: Bool { services.contains(where: OticonBattery.supports) }
    var supportsIdentification: Bool { services.contains(where: OticonIdentification.supports) }
    var supportsCoreDumpInfo: Bool { services.contains(where: OticonDiagnostics.supportsCoreDumpInfo) }
    var supportsProgramInformation: Bool { services.contains(where: OticonConsumerPrograms.supports) }
    func programInformation() async throws -> [ConsumerProgramSnapshot.Program] {
        guard let service = services.first(where: OticonConsumerPrograms.supports) else {
            throw SessionError.unavailable("No supported consumer program-information service was advertised.")
        }
        let response = try await consumerRequest(handle: service.handle, opcode: OticonConsumerPrograms.programInformationOpcode)
        do { return try OticonConsumerPrograms.programInformation(response.payload, service: service) }
        catch { throw UTLAdvanced.ParseError("Consumer program information could not be decoded (\(response.payload.count) bytes).") }
    }
    func consumerActiveProgram() async throws -> Int {
        guard let service = services.first(where: OticonConsumerPrograms.supports) else {
            throw SessionError.unavailable("No supported consumer program-information service was advertised.")
        }
        let response = try await consumerRequest(handle: service.handle, opcode: OticonConsumerPrograms.activeProgramOpcode)
        do { return try OticonConsumerPrograms.activeProgram(response.payload, service: service) }
        catch { throw UTLAdvanced.ParseError("Consumer active program could not be decoded (\(response.payload.count) bytes).") }
    }
    func coreDumpInfo() async throws -> OticonDiagnostics.CoreDumpInfo {
        guard let service = services.first(where: OticonDiagnostics.supportsCoreDumpInfo) else {
            throw SessionError.unavailable("No supported crash-dump information service was advertised.")
        }
        let response = try await consumerRequest(handle: service.handle, opcode: OticonDiagnostics.coreDumpInfoOpcode)
        do { return try OticonDiagnostics.coreDumpInfo(response.payload, service: service) }
        catch { throw UTLAdvanced.ParseError("Crash-dump counters could not be decoded (\(response.payload.count) bytes).") }
    }
    func identification() async throws -> OticonIdentification.Identity {
        identificationPayload = nil
        guard let service = services.first(where: OticonIdentification.supports) else {
            throw SessionError.unavailable("No supported hearing aid identification service was advertised.")
        }
        let response = try await consumerRequest(handle: service.handle, opcode: OticonIdentification.hiidInfoOpcode)
        do {
            let identity = try OticonIdentification.decodeHiid(response.payload)
            identificationPayload = response.payload
            // The HIID map can contain identifying and fitting information.
            // Never include its bytes or the serial number in session events.
            diagnostic("Hearing aid identification read (HIID \(identity.hiidMajor).\(identity.hiidMinor)).")
            return identity
        } catch {
            throw UTLAdvanced.ParseError("Hearing aid identification could not be decoded (\(response.payload.count) bytes).")
        }
    }
    func batteryTelemetry() async throws -> OticonBattery.State {
        guard let service = services.first(where: OticonBattery.supports) else {
            throw SessionError.unavailable("No supported battery telemetry service was advertised.")
        }
        let response = try await consumerRequest(handle: service.handle, opcode: OticonBattery.fastInfoOpcode)
        diagnostic("Battery telemetry response: bytes=\(response.payload.count), hexPrefix=\(response.payload.prefix(64).hexString)")
        do { return try OticonBattery.fastState(response.payload, service: service) }
        catch { throw UTLAdvanced.ParseError("Battery \(service.major).\(service.minor) telemetry could not be decoded (\(response.payload.count) bytes).") }
    }
    func batteryHealth() async throws -> OticonBattery.Health {
        guard let service = services.first(where: OticonBattery.supports) else {
            throw SessionError.unavailable("No supported battery health service was advertised.")
        }
        let response = try await consumerRequest(handle: service.handle, opcode: OticonBattery.slowInfoOpcode)
        do { return try OticonBattery.slowHealth(response.payload, service: service) }
        catch { throw UTLAdvanced.ParseError("Battery health could not be decoded (\(response.payload.count) bytes).") }
    }
    func speechBooster() async throws -> OticonSpeechBooster.State {
        guard supportsSpeechBooster, let service = services.first(where: OticonSpeechBooster.supports) else {
            throw SessionError.unavailable("This aid does not advertise the supported consumer Speech Booster path.")
        }
        let responses = try await consumerRequests([UInt8(0), 2, 4].map { (service.handle, $0, Data()) })
        return try OticonSpeechBooster.State(noiseReduction: responses[0].payload,
                                            directionality: responses[1].payload, targetLoss: responses[2].payload)
    }
    func setSpeechBooster(enabled: Bool) async throws -> OticonSpeechBooster.State {
        guard purpose == .consumer else { throw SessionError.unavailable("Sound writes are unavailable in a read-only backup session.") }
        guard supportsSpeechBooster, let service = services.first(where: OticonSpeechBooster.supports) else {
            throw SessionError.unavailable("Speech Booster must be loaded for this aid first.")
        }
        let current = try await speechBooster()
        if enabled {
            _ = try await consumerRequests(current.enableCommands.map { (service.handle, $0.opcode, $0.payload) })
        } else {
            // This opcode resets only MCESystemControl's consumer adjustments;
            // it is unrelated to session.soft_reset / firmware reset commands.
            _ = try await consumerRequests([(service.handle, 6, Data())])
        }
        let confirmed = try await speechBooster()
        guard confirmed.isEnabled == enabled else { throw SessionError.unavailable("Speech Booster request accepted, but current adjustments do not match.") }
        return confirmed
    }

    /// Reads only the verified HIID4.5 fitting-system record. No caller can
    /// supply a memory address, write opcode or arbitrary record key here.
    /// Independent read transactions plus a repeated header and CRC guard
    /// against a changed or torn record; rejection is never retried in a more
    /// privileged mode. An optional absolute deadline covers acquisition waits;
    /// owned cancellation and session closure retain their cleanup budget.
    func readFittingSystemRecord(hiidVersion: String, deadline: Date? = nil) async throws -> Data {
        guard purpose == .readOnlyBackup, isReady,
              let service = services.first(where: { OticonFittingRead.supports(service: $0, hiidVersion: hiidVersion) }) else {
            throw SessionError.unavailable("A supported read-only fitting-record contract is unavailable.")
        }
        func read(offset: Int, length: Int) async throws -> Data {
            let response = try await consumerRequests([(service.handle, OticonFittingRead.readOpcode,
                OticonFittingRead.readRequest(offset: offset, length: length))],
                transactionType: UTLReadOnlySession.readNVRAMTransaction, deadline: deadline)[0]
            return try OticonFittingRead.decodeReadResponse(response.payload, expectedLength: length)
        }
        let originalHeader = try await read(offset: 0, length: OticonFittingRead.headerSize)
        let header = try OticonFittingRead.Header(data: originalHeader)
        var payload = Data()
        for chunk in try OticonFittingRead.payloadChunks(size: header.size) {
            payload.append(try await read(offset: chunk.offset, length: chunk.length))
        }
        let repeatedHeader = try await read(offset: 0, length: OticonFittingRead.headerSize)
        try checkDeadline(deadline)
        let record = try OticonFittingRead.validateRecord(header: originalHeader, payload: payload, repeatedHeader: repeatedHeader)
        try checkDeadline(deadline)
        return record
    }

    struct EndUserSettingsRead {
        let data: DeviceBackup.EndUserSettings
        let partial: Bool
    }
    /// Scope IDs come only from the validated device inventory. Completed
    /// getters are retained if a later scope rejects the read; no fallback
    /// session or RAM/write operation is attempted. Deadline expiry after the
    /// inventory was captured returns the completed data with partial coverage.
    func readEndUserSettings(deadline: Date? = nil) async throws -> EndUserSettingsRead {
        guard purpose == .readOnlyBackup, isReady,
              let service = services.first(where: OticonEndUserSettings.supports) else {
            throw SessionError.unavailable("A supported read-only end-user-settings contract is unavailable.")
        }
        let inventoryResponse = try await consumerRequest(handle: service.handle,
            opcode: OticonEndUserSettings.inventoryOpcode, deadline: deadline)
        let rawInventory = try OticonEndUserSettings.validateResponse(inventoryResponse.payload)
        guard let inventory = try? OticonEndUserSettings.decodeInventory(rawInventory) else {
            return try .init(data: .init(inventory: rawInventory, records: []), partial: true)
        }
        var metadata: Data?, records: [DeviceBackup.EndUserSettings.ScopeRecord] = [], partial = !inventory.isComplete
        do {
            metadata = try OticonEndUserSettings.validateResponse(
                try await consumerRequest(handle: service.handle,
                    opcode: OticonEndUserSettings.metadataOpcode, deadline: deadline).payload)
        } catch { partial = true }
        var total = 0
        for read in inventory.reads {
            do {
                try Task.checkCancellation()
                let response = try await consumerRequests([(service.handle, OticonEndUserSettings.readOpcode,
                    OticonEndUserSettings.readRequest(read))],
                    transactionType: UTLReadOnlySession.readNVRAMTransaction, deadline: deadline)[0]
                guard response.payload.count <= 196_608 - total else { partial = true; break }
                records.append(try .init(scope: read.scope, id: read.id, bytes: response.payload))
                total += response.payload.count
            } catch { partial = true; break }
        }
        return try .init(data: .init(inventory: inventory.raw, metadata: metadata, records: records), partial: partial)
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
        let token = UInt32.random(in: 1...UInt32.max)
        let payload = try purpose == .readOnlyBackup
            ? UTLReadOnlySession.openPayload(service: service, privateToken: token, timeSince2020: UInt32(seconds), version: version)
            : UTLConsumerSession.openPayload(service: service, privateToken: token, timeSince2020: UInt32(seconds), version: version)
        progress(purpose == .readOnlyBackup ? "Opening read-only backup session" : "Opening nonexclusive consumer session")
        consumerOpenAttempted = true
        _ = try await request(handle: service.handle, opcode: 0, payload: payload)
        _ = try await request(handle: service.handle, opcode: 4)
        progress("Consumer transaction pipeline opened")
    }
    private func consumerRequest(handle: UInt8, opcode: UInt8, payload: Data = Data(),
                                 deadline: Date? = nil) async throws -> UTLProtocol.ServiceMessage {
        try await consumerRequests([(handle, opcode, payload)], deadline: deadline)[0]
    }
    private func consumerRequests(_ operations: [(handle: UInt8, opcode: UInt8, payload: Data)],
                                  transactionType: UInt8 = UTLConsumerSession.commandTransactionType,
                                  deadline: Date? = nil) async throws -> [UTLProtocol.ServiceMessage] {
        try checkDeadline(deadline)
        guard let sessionService, consumerOpenAttempted, !commandBusy, !commandPoisoned else {
            throw SessionError.unavailable("Consumer command session is unavailable or busy.")
        }
        commandBusy = true
        defer { commandBusy = false }
        guard transactionType == UTLConsumerSession.commandTransactionType
                || (purpose == .readOnlyBackup && transactionType == UTLReadOnlySession.readNVRAMTransaction) else {
            throw SessionError.unavailable("This channel does not allow the requested transaction type.")
        }
        transactionID = transactionID &+ 1
        if transactionID == 0 { transactionID = 1 }
        let id = transactionID
        // Mark before awaiting ACK so ambiguous starts are cancelled on cleanup.
        activeTransaction = id
        do {
            _ = try await request(handle: sessionService.handle, opcode: 7,
                                  payload: Data([transactionType, UInt8(truncatingIfNeeded: id >> 8), UInt8(truncatingIfNeeded: id)]),
                                  deadline: deadline)
            var responses: [UTLProtocol.ServiceMessage] = []
            for operation in operations {
                progress(String(format: "Consumer command %02X on service handle %u", operation.opcode, operation.handle))
                responses.append(try await request(handle: operation.handle, opcode: operation.opcode,
                    payload: operation.payload, deadline: deadline))
            }
            _ = try await request(handle: sessionService.handle, opcode: 8,
                                  payload: UTLConsumerSession.transactionPayload(id: id, starting: false), deadline: deadline)
            activeTransaction = nil
            return responses
        } catch {
            do {
                // Expiry stops acquisition, not the owned cancellation. Its
                // ordinary bounded waits must still be available after expiry.
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
    private func request(handle: UInt8, opcode: UInt8, payload: Data = Data(),
                         deadline: Date? = nil) async throws -> UTLProtocol.ServiceMessage {
        try checkDeadline(deadline)
        let identifier = requestIdentifier
        requestIdentifier = requestIdentifier &+ 2
        if requestIdentifier == 0 { requestIdentifier = 1 }
        let body = Data([0x0C, identifier, handle, opcode]) + payload
        guard body.count + 3 <= transportMTU else { throw SessionError.unavailable("Request exceeds negotiated transport MTU.") }
        try await send(UTLProtocol.TransportFrame(kind: .data, final: true, payload: body).data, deadline: deadline)
        try await waitUntil(deadline: deadline) { self.messages.contains { $0.identifier == identifier && $0.serviceHandle == handle } }
        guard let index = messages.firstIndex(where: { $0.identifier == identifier && $0.serviceHandle == handle }) else { throw SessionError.timeout }
        let response = messages.remove(at: index)
        guard response.status?.isSuccess == true else { throw UTLProtocol.CodecError.responseStatus(response.code) }
        return response
    }
    private func send(_ data: Data, deadline: Date? = nil) async throws {
        for offset in stride(from: 0, to: data.count, by: payloadMTU) {
            try await waitUntil(deadline: deadline) { self.credits.serverCredits > 0 }
            let chunk = Data(data[offset..<min(data.count, offset + payloadMTU)])
            let packet = try credits.send(chunk)
            let ticket = enqueue(packet)
            try await waitUntil(deadline: deadline) { ticket.result != nil }
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
    private func checkDeadline(_ deadline: Date?) throws {
        if let deadline, !(acquisitionNow() < deadline) { throw SessionError.timeout }
    }
    private func waitUntil(deadline: Date? = nil, _ condition: () -> Bool) async throws {
        // Keep the transport backstop on real time even when a synthetic peer
        // advances the acquisition clock at an exact protocol boundary.
        let waitDeadline = Date().addingTimeInterval(8)
        while true {
            if let failure { throw failure }
            // Check before the condition: a response or ACK buffered after the
            // acquisition deadline must not turn an expired read into success.
            try checkDeadline(deadline)
            guard Date() < waitDeadline else { throw SessionError.timeout }
            if condition() { return }
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
