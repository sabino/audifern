import CompanionCore
import CryptoKit
import Foundation
import Testing
@testable import OpenCompanion

/// Synthetic peer only. Its key is a test fixture, unrelated to vendor material.
@MainActor private final class SyntheticUTLPeer {
    weak var session: UTLSession?
    let key = Data(repeating: 7, count: 16)
    let serverChallenge = Data(repeating: 9, count: 14)
    var sequence: UInt8 = 0
    var controlOpcodes: [UInt8] = []
    var serviceOpcodes: [UInt8] = []
    var validServerHash = true
    var verifiedClientProof = false
    var clientChallenge = Data()
    var transportDecoder = UTLProtocol.TransportDecoder()
    var outgoingSequences: [UInt8] = []
    var holdNextInput = false
    var releaseAcknowledgement: CheckedContinuation<Void, Never>?
    var currentSteps = [Int](repeating: 0, count: 8)
    var consumerOpen = false
    var pipelineOpen = false
    var transaction: Data?
    var serviceTrace: [(handle: UInt8, opcode: UInt8, payload: Data)] = []
    var failNextEqualizerRead = false
    var failCancellation = false

    func write(_ characteristic: String, _ data: Data) async throws {
        guard let session else { throw UTLSession.SessionError.disconnected }
        if characteristic == UTLProtocol.control {
            let bytes = Array(data)
            controlOpcodes.append(bytes[0])
            if bytes[0] == 1 { try output(Data([0x81, 100]), control: true) }
            if bytes[0] == 3 {
                clientChallenge = Data(bytes.suffix(14))
                let hash = validServerHash ? Data(SHA256.hash(data: serverChallenge + clientChallenge + key).prefix(14)) : Data(repeating: 0, count: 14)
                let identity = Data(bytes[1...5])
                session.receiveControl(Data([0x42]) + identity + hash)
                session.receiveControl(Data([0x43]) + identity + serverChallenge)
            }
            if bytes[0] == 4 {
                verifiedClientProof = Data(bytes.suffix(14)) == Data(SHA256.hash(data: clientChallenge + serverChallenge + key).prefix(14))
            }
            return
        }
        let packet = try UTLProtocol.GattPacket(data: data)
        outgoingSequences.append(packet.sequence)
        if packet.isControl { return }
        if holdNextInput, packet.payload.count >= 7, packet.payload[5] == 9, packet.payload[6] == 4 {
            holdNextInput = false
            // Queue a required credit-discard reply while this packet is still
            // awaiting its acknowledgement. It must precede the next chunk.
            try output(Data([0x83, 0]), control: true)
            await withCheckedContinuation { releaseAcknowledgement = $0 }
        }
        guard let frame = try transportDecoder.append(packet.payload).first else { return }
        if frame.kind == .control {
            try output(UTLProtocol.TransportFrame(kind: .control, final: true, identifier: 1, opcode: 2, payload: Data([1, 0, 0x40])).data)
        } else {
            let request = try UTLProtocol.MessagePart(data: frame.payload)
            serviceTrace.append((request.serviceHandle, request.code!, request.payload))
            if request.serviceHandle != 8 { serviceOpcodes.append(request.code!) }
            let payload: Data
            var status: UInt8 = 0x40
            if request.serviceHandle == 0 {
                payload = Data([2, 0, 0, 16, 9, 2, 0, 0xFF, 2, 0, 0, 9, 8, 1, 1, 0xFF])
            } else if request.serviceHandle == 8 {
                switch request.code {
                case 0:
                    #expect(request.payload.count == 17 && request.payload.first == 3)
                    #expect(request.payload.last == 1)
                    consumerOpen = true
                case 1: consumerOpen = false; pipelineOpen = false; transaction = nil
                case 4: #expect(consumerOpen); pipelineOpen = true
                case 7:
                    #expect(consumerOpen && pipelineOpen && transaction == nil)
                    #expect(request.payload.count == 3 && request.payload.first == 5)
                    transaction = Data(request.payload.suffix(2))
                case 8:
                    #expect(transaction == request.payload)
                    transaction = nil
                case 9:
                    #expect(transaction == request.payload)
                    if failCancellation { status = 0xDE } else { transaction = nil }
                default: Issue.record("Unexpected session command")
                }
                payload = Data()
            } else if !consumerOpen || !pipelineOpen || transaction == nil {
                status = 0xD9; payload = Data()
            } else if failNextEqualizerRead {
                failNextEqualizerRead = false
                status = 0xD4; payload = Data()
            } else if request.code == 2 {
                payload = Data([0xA1, 0x68]) + Data("stepsize".utf8) + Data([0xF9, 0x34, 0]) // 0.25
            } else if request.code == 4 {
                guard case .array(let values) = try UTLCBOR.decodeSequence(request.payload).first else { throw OticonEqualizer.EQError.malformed }
                currentSteps = values.map { let value = $0.int!; return value > 127 ? value - 256 : value }
                payload = Data()
            } else {
                payload = try UTLCBOR.unsignedVector(currentSteps)
                    + UTLCBOR.unsignedVector(.init(repeating: -127, count: 8))
                    + UTLCBOR.unsignedVector(.init(repeating: 127, count: 8))
            }
            try output(UTLProtocol.TransportFrame(kind: .data, final: true,
                payload: Data([0x1C, request.identifier, request.serviceHandle, status]) + payload).data)
        }
    }
    func output(_ payload: Data, control: Bool = false) throws {
        let data = try UTLProtocol.GattPacket(sequence: sequence, credits: control ? 15 : 0, payload: payload).data
        sequence = (sequence + 1) & 15
        session?.receiveOutput(data)
    }
}

@MainActor @Test func advancedChannelAuthenticatesAndReadsWithoutSettingWrites() async throws {
    let peer = SyntheticUTLPeer()
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 3, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key)
    #expect(session.isReady)
    #expect(peer.verifiedClientProof)
    #expect(peer.controlOpcodes == [1, 3, 4])
    let step = try await session.equalizerStep()
    #expect(step == 0.25)
    let state = try await session.equalizer(microphone: true, stepDB: step)
    #expect(state.rawSteps == .init(repeating: 0, count: 8))
    #expect(state.minimumSteps == .init(repeating: -127, count: 8))
    #expect(peer.serviceOpcodes == [1, 2, 3]) // discovery, info, microphone read
    #expect(peer.serviceTrace.map { "\($0.handle)/\($0.opcode)" } == ["0/1", "8/0", "8/4", "8/7", "9/2", "8/8", "8/7", "9/3", "8/8"])
}

@MainActor @Test func invalidServerProofStopsBeforeClientProofOrServiceRequests() async throws {
    let peer = SyntheticUTLPeer(); peer.validServerHash = false
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    await #expect(throws: (any Error).self) { try await session.start(key: peer.key) }
    #expect(!session.isReady)
    #expect(peer.controlOpcodes == [1, 3])
    #expect(peer.serviceOpcodes.isEmpty)
}

@MainActor @Test func advancedChannelNeverDisplacesAnOccupiedChannel() throws {
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x40, 0x80, 0x80, 0x80]))
    #expect(throws: (any Error).self) { try UTLSession(info: info, physicalATTMTU: 247) { _, _ in Issue.record("Must not write") } }
}

@MainActor @Test func queuedCreditReplyCannotBeOvertakenByTheNextFragment() async throws {
    let peer = SyntheticUTLPeer()
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    // Twenty-byte adaptation payload forces the consumer EQ request to split.
    let session = try UTLSession(info: info, physicalATTMTU: 24) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key)
    let expected = try OticonEqualizer.State(rawSteps: .init(repeating: 0, count: 8),
        minimumSteps: .init(repeating: -127, count: 8), maximumSteps: .init(repeating: 127, count: 8), stepDB: 0.25)
    peer.holdNextInput = true
    let operation = Task { try await session.setEqualizer(microphone: true, steps: .init(repeating: 127, count: 8), expected: expected) }
    let deadline = Date().addingTimeInterval(2)
    while peer.releaseAcknowledgement == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
    guard let release = peer.releaseAcknowledgement else { operation.cancel(); Issue.record("Fragment was never sent"); return }
    // Let the response-triggered scheduling opportunity occur before ACK.
    await Task.yield()
    release.resume(); peer.releaseAcknowledgement = nil
    let result = try await operation.value
    #expect(result.rawSteps == .init(repeating: 127, count: 8))
    #expect(peer.outgoingSequences.count >= 6)
    #expect(peer.outgoingSequences.enumerated().allSatisfy { $0.element == UInt8($0.offset & 15) })
    #expect(peer.serviceOpcodes == [1, 4, 3])
}

@MainActor @Test func lostOpenAcknowledgementStillCleansUpOnlyThisClientChannel() async throws {
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    var writes: [Data] = []
    let session = try UTLSession(info: info, physicalATTMTU: 247) { characteristic, data in
        #expect(characteristic == UTLProtocol.control)
        writes.append(data)
        if data.first == 1 { throw UTLSession.SessionError.timeout }
    }
    await #expect(throws: (any Error).self) { try await session.start(key: Data(repeating: 7, count: 16)) }
    await session.stop()
    #expect(writes.map { $0.first! } == [1, 2])
    #expect(writes[0][1...5] == writes[1][1...5]) // same client ID and chosen channel
}

@MainActor @Test func failedConsumerReadCancelsCommandTransactionBeforeAnotherRead() async throws {
    let peer = SyntheticUTLPeer()
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key)
    peer.failNextEqualizerRead = true
    await #expect(throws: (any Error).self) { try await session.equalizerStep() }
    #expect(peer.transaction == nil)
    #expect(try await session.equalizerStep() == 0.25)
    #expect(peer.serviceTrace.map { "\($0.handle)/\($0.opcode)" }.suffix(6) == ["8/7", "9/2", "8/9", "8/7", "9/2", "8/8"])
    await session.stop()
    #expect(!peer.consumerOpen && !peer.pipelineOpen)
    #expect(peer.controlOpcodes.last == 2)
}

@MainActor @Test func failedCancellationPoisonsTheConsumerSessionUntilOwnedCleanup() async throws {
    let peer = SyntheticUTLPeer()
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key)
    peer.failNextEqualizerRead = true; peer.failCancellation = true
    await #expect(throws: (any Error).self) { try await session.equalizerStep() }
    #expect(!session.isReady && peer.transaction != nil)
    let count = peer.serviceTrace.count
    await #expect(throws: (any Error).self) { try await session.equalizerStep() }
    #expect(peer.serviceTrace.count == count)
    await session.stop()
    #expect(!peer.consumerOpen && peer.transaction == nil)
    #expect(peer.serviceTrace.map { "\($0.handle)/\($0.opcode)" }.suffix(2) == ["8/9", "8/1"])
}
