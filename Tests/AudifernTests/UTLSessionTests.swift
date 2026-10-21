import CompanionCore
import CryptoKit
import Foundation
import Testing
@testable import Audifern

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
    var currentStreamingSteps = [Int](repeating: 0, count: 8)
    var consumerOpen = false
    var pipelineOpen = false
    var transaction: Data?
    var serviceTrace: [(handle: UInt8, opcode: UInt8, payload: Data)] = []
    var failNextEqualizerRead = false
    var equalizerInfoOverride: Data?
    var failCancellation = false
    var advertiseSpeechBooster = false
    var advertiseBattery = false
    var advertiseIdentification = false
    var advertiseDiagnostics = false
    var advertiseFitting = false
    var expectedSessionType: UInt8 = 3
    var transactionTypes: [UInt8] = []
    var fittingRecord = Data()
    var rejectFittingRead = false
    var changeRepeatedFittingHeader = false
    var fittingHeaderReadCount = 0
    var advertiseEndUserSettings = false
    var endUserInventory = Data()
    var rejectEndUserID: UInt8?
    var suppressResponse: ((UInt8, UInt8, Data) -> Bool)?
    var discardCreditsAfterNextTransaction = false
    var batteryTrailingData = Data()
    var speechValues = [0, 1, -2]
    let speechMinimum = [-4, -3, -2]
    let speechMaximum = [3, 5, 2]

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
                var registry = Data([2, 0, 0, 16, 9, 2, 0, 0xFF, 2, 0, 0, 9, 8, 1, 1, 0xFF])
                if advertiseSpeechBooster { registry.append(contentsOf: [2, 0, 0, 19, 10, 1, 2, 0xFF]) }
                if advertiseBattery { registry.append(contentsOf: [1, 0, 0, 7, 7, 2, 0, 0xFF]) }
                if advertiseIdentification { registry.append(contentsOf: [2, 0, 0, 4, 11, 1, 2, 0xFF]) }
                if advertiseDiagnostics { registry.append(contentsOf: [2, 0, 0, 12, 12, 1, 0, 0xFF]) }
                if advertiseFitting { registry.append(contentsOf: [2, 0, 0, 6, 13, 1, 1, 0xFF]) }
                if advertiseEndUserSettings { registry.append(contentsOf: [2, 0, 0, 23, 14, 2, 1, 0xFF]) }
                payload = registry
            } else if request.serviceHandle == 8 {
                switch request.code {
                case 0:
                    #expect(request.payload.count == 17 && request.payload.first == expectedSessionType)
                    #expect(request.payload.last == 1)
                    consumerOpen = true
                case 1: consumerOpen = false; pipelineOpen = false; transaction = nil
                case 4: #expect(consumerOpen); pipelineOpen = true
                case 7:
                    #expect(consumerOpen && pipelineOpen && transaction == nil)
                    #expect(request.payload.count == 3)
                    #expect(request.payload.first == 5 || (expectedSessionType == 4 && request.payload.first == 2))
                    transactionTypes.append(request.payload.first!)
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
            } else if request.serviceHandle == 14 {
                #expect(expectedSessionType == 4)
                switch request.code {
                case 0: #expect(transactionTypes.last == 5 && request.payload.isEmpty); payload = endUserInventory
                case 1: #expect(transactionTypes.last == 5 && request.payload.isEmpty); payload = Data([0xA0])
                case 2:
                    #expect(transactionTypes.last == 2 && request.payload.count == 2)
                    if request.payload.last == rejectEndUserID { status = 0xD4; payload = Data() }
                    else { payload = Data([0x82]) + request.payload }
                default: Issue.record("Unexpected end-user-settings opcode"); payload = Data()
                }
            } else if request.serviceHandle == 13 {
                #expect(request.code == 0 && request.payload.count == 7)
                #expect(request.payload.prefix(3) == Data([1, 3, 0xF1]))
                #expect(expectedSessionType == 4 && transactionTypes.last == 2)
                if rejectFittingRead { status = 0xD4; payload = Data() }
                else {
                    let b = Array(request.payload), offset = Int(b[3]) << 8 | Int(b[4]), count = Int(b[5]) << 8 | Int(b[6])
                    guard count <= 950, offset + count <= fittingRecord.count else { throw OticonFittingRead.DecodeError.invalidReadRange }
                    var data = Data(fittingRecord[offset..<(offset + count)])
                    if offset == 0 {
                        fittingHeaderReadCount += 1
                        if changeRepeatedFittingHeader && fittingHeaderReadCount > 1 { data[15] ^= 1 }
                    }
                    payload = data
                }
            } else if request.serviceHandle == 7 {
                #expect(request.payload.isEmpty)
                if request.code == 1 {
                    payload = Data([0, 0, 0, 90, 0, 0, 0, 60, 0, 0, 3, 0xE8, 0, 0, 0x4E, 0x20])
                } else {
                    #expect(request.code == 2)
                    // Fixed big-endian scalars and MSB-packed flags, not CBOR.
                    payload = Data([0, 0, 0, 50, 0, 0, 0x2E, 0xE0, 0, 0, 3, 0xE8, 0x40])
                        + batteryTrailingData
                }
            } else if request.serviceHandle == 11 {
                #expect(request.code == 3 && request.payload.isEmpty)
                // Synthetic HIID4.6 map:1001=>bstr[4,6],2003=>bstrnumericserial.
                payload = Data([0xA2, 0x19, 0x03, 0xE9, 0x42, 4, 6,
                                0x19, 0x07, 0xD3, 0x44, 0x80, 0, 0, 0x2A])
            } else if request.serviceHandle == 12 {
                #expect(request.code == 0 && request.payload.isEmpty)
                payload = Data([0x12, 0x34, 0, 2])
            } else if request.serviceHandle == 10 {
                let opcode = request.code!
                if opcode == 6 {
                    speechValues = [0, 1, -2]; payload = Data()
                } else {
                    let index = Int(opcode / 2)
                    guard index < 3 else { throw OticonEqualizer.EQError.malformed }
                    if opcode & 1 == 0 {
                        payload = Data([speechValues[index], speechMinimum[index], speechMaximum[index]].map { UInt8(bitPattern: Int8($0)) })
                    } else {
                        guard request.payload.count == 1 else { throw OticonEqualizer.EQError.malformed }
                        let value = Int(Int8(bitPattern: request.payload.first!))
                        #expect((speechMinimum[index]...speechMaximum[index]).contains(value))
                        speechValues[index] = value; payload = Data()
                    }
                }
            } else if failNextEqualizerRead {
                failNextEqualizerRead = false
                status = 0xD4; payload = Data()
            } else if request.code == 2 {
                payload = equalizerInfoOverride ?? (Data([0xA1, 0x68]) + Data("stepsize".utf8) + Data([0xF9, 0x34, 0])) // 0.25
            } else if request.serviceHandle == 9 && [UInt8(1), 4].contains(request.code!) {
                guard case .array(let values) = try UTLCBOR.decodeSequence(request.payload).first else { throw OticonEqualizer.EQError.malformed }
                let steps = values.map { let value = $0.int!; return value > 127 ? value - 256 : value }
                if request.code == 4 { currentSteps = steps } else { currentStreamingSteps = steps }
                payload = Data()
            } else {
                payload = try UTLCBOR.unsignedVector(request.serviceHandle == 9 && request.code == 0 ? currentStreamingSteps : currentSteps)
                    + UTLCBOR.unsignedVector(.init(repeating: -127, count: 8))
                    + UTLCBOR.unsignedVector(.init(repeating: 127, count: 8))
            }
            if suppressResponse?(request.serviceHandle, request.code!, request.payload) == true { return }
            if request.serviceHandle == 13 && payload.count > 60 {
                // Independent peer implementation: response service fragments
                // at64bytes, ATT notifications at17bytes. This exercises the
                // actual production credit, transport and message assemblers.
                var offset = min(60, payload.count)
                var parts = [Data([offset == payload.count ? 0x1C : 0x14, request.identifier, request.serviceHandle, status]) + payload.prefix(offset)]
                while offset < payload.count {
                    let end = min(payload.count, offset + 61)
                    parts.append(Data([end == payload.count ? 0x5C : 0x50, request.identifier, request.serviceHandle]) + payload[offset..<end])
                    offset = end
                }
                for part in parts {
                    let wire = try UTLProtocol.TransportFrame(kind: .data, final: true, payload: part).data
                    for offset in stride(from: 0, to: wire.count, by: 17) {
                        try output(Data(wire[offset..<min(wire.count, offset + 17)]))
                    }
                }
            } else {
                try output(UTLProtocol.TransportFrame(kind: .data, final: true,
                    payload: Data([0x1C, request.identifier, request.serviceHandle, status]) + payload).data)
            }
            if request.serviceHandle == 8, request.code == 7, discardCreditsAfterNextTransaction {
                discardCreditsAfterNextTransaction = false
                try output(Data([0x83, 255]), control: true)
            }
        }
    }
    func output(_ payload: Data, control: Bool = false) throws {
        let data = try UTLProtocol.GattPacket(sequence: sequence, credits: control ? 15 : 0, payload: payload).data
        sequence = (sequence + 1) & 15
        session?.receiveOutput(data)
    }
}

private func syntheticFittingRecord() -> Data {
    let body = Data((0..<2040).map { UInt8(truncatingIfNeeded: $0) })
    let crc = OticonFittingRead.checksum(body)
    return Data([0, 0, 4, 0, 7, 0xF8, UInt8(crc >> 8), UInt8(crc & 0xFF)])
        + Data(repeating: 0, count: 8) + body
}

private func syntheticEUSInventory(access: String = "NVRAM") -> Data {
    func text(_ string: String) -> Data { Data([0x60 + UInt8(string.utf8.count)]) + Data(string.utf8) }
    func scope(_ name: String, _ count: UInt8) -> Data {
        var data = Data([0xA3]); data.append(text("name")); data.append(text(name))
        data.append(text("count")); data.append(count)
        data.append(text("access")); data.append(text(access)); return data
    }
    return Data([0xA1]) + text("scopes") + Data([0x81, 0x82]) + scope("global", 1) + scope("situation", 2)
}

@MainActor private func expectAcquisitionTimeout(_ operation: @MainActor () async throws -> Void) async {
    do {
        try await operation()
        Issue.record("Expected the acquisition deadline to expire")
    } catch UTLSession.SessionError.timeout {
        // The acquisition budget, rather than a peer rejection, ended the read.
    } catch {
        Issue.record("Unexpected acquisition error: \(error)")
    }
}

@MainActor @Test func expiredBackupDeadlineStartsNoNewTransaction() async throws {
    let peer = SyntheticUTLPeer()
    peer.advertiseFitting = true; peer.advertiseEndUserSettings = true; peer.expectedSessionType = 4
    peer.fittingRecord = syntheticFittingRecord(); peer.endUserInventory = syntheticEUSInventory()
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key, purpose: .readOnlyBackup)
    let count = peer.serviceTrace.count
    await expectAcquisitionTimeout {
        _ = try await session.readFittingSystemRecord(hiidVersion: "4.5", deadline: .distantPast)
    }
    await expectAcquisitionTimeout { _ = try await session.readEndUserSettings(deadline: .distantPast) }
    #expect(peer.serviceTrace.count == count && peer.transactionTypes.isEmpty)
    await session.stop()
    #expect(!peer.consumerOpen && peer.controlOpcodes.last == 2)
}

@MainActor @Test func fittingResponseDeadlineStillCancelsAndClosesTheOwnedSession() async throws {
    let peer = SyntheticUTLPeer(); peer.advertiseFitting = true; peer.expectedSessionType = 4
    peer.fittingRecord = syntheticFittingRecord()
    peer.suppressResponse = { handle, _, _ in handle == 13 }
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key, purpose: .readOnlyBackup)
    let deadline = Date().addingTimeInterval(0.3)
    await expectAcquisitionTimeout { _ = try await session.readFittingSystemRecord(hiidVersion: "4.5", deadline: deadline) }
    #expect(Date() >= deadline)
    #expect(peer.transactionTypes == [2] && peer.transaction == nil)
    #expect(peer.serviceTrace.suffix(3).map { "\($0.handle)/\($0.opcode)" } == ["8/7", "13/0", "8/9"])
    await session.stop()
    #expect(!peer.consumerOpen && peer.controlOpcodes.last == 2)
    #expect(peer.serviceTrace.last?.handle == 8 && peer.serviceTrace.last?.opcode == 1)
}

@MainActor @Test func fittingDeadlineBoundsTheWriteAcknowledgementWait() async throws {
    let peer = SyntheticUTLPeer(); peer.advertiseFitting = true; peer.expectedSessionType = 4
    peer.fittingRecord = syntheticFittingRecord()
    var delayedAcknowledgement = false
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in
        try await peer.write(uuid, data)
        if uuid != UTLProtocol.control, peer.serviceTrace.last?.handle == 13, !delayedAcknowledgement {
            delayedAcknowledgement = true
            // The response is already buffered, but its ATT write acknowledgement
            // arrives after expiry. A buffered response must not bypass the budget.
            try await Task.sleep(for: .milliseconds(650))
        }
    }
    peer.session = session
    try await session.start(key: peer.key, purpose: .readOnlyBackup)
    let deadline = Date().addingTimeInterval(0.3)
    await expectAcquisitionTimeout { _ = try await session.readFittingSystemRecord(hiidVersion: "4.5", deadline: deadline) }
    #expect(delayedAcknowledgement && Date() >= deadline)
    #expect(peer.fittingHeaderReadCount == 1 && peer.transactionTypes == [2] && peer.transaction == nil)
    #expect(peer.serviceTrace.last?.handle == 8 && peer.serviceTrace.last?.opcode == 9)
    await session.stop()
    #expect(!peer.consumerOpen && peer.controlOpcodes.last == 2)
}

@MainActor @Test func fittingDeadlineBoundsTheCreditWaitAndAllowsLaterCleanup() async throws {
    let peer = SyntheticUTLPeer(); peer.advertiseFitting = true; peer.expectedSessionType = 4
    peer.fittingRecord = syntheticFittingRecord()
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key, purpose: .readOnlyBackup)
    peer.discardCreditsAfterNextTransaction = true
    let deadline = Date().addingTimeInterval(0.3)
    let restoreCredits = Task {
        try await Task.sleep(for: .milliseconds(500))
        try peer.output(Data([0x81, 100]), control: true)
    }
    await expectAcquisitionTimeout { _ = try await session.readFittingSystemRecord(hiidVersion: "4.5", deadline: deadline) }
    try await restoreCredits.value
    #expect(Date() >= deadline)
    #expect(peer.transactionTypes == [2] && peer.transaction == nil)
    #expect(!peer.serviceTrace.contains { $0.handle == 13 })
    #expect(peer.serviceTrace.suffix(2).map(\.opcode) == [7, 9])
    await session.stop()
    #expect(!peer.consumerOpen && peer.controlOpcodes.last == 2)
}

@MainActor @Test func endUserDeadlineKeepsCompletedScopesAndStopsFurtherReads() async throws {
    let peer = SyntheticUTLPeer(); peer.advertiseEndUserSettings = true; peer.expectedSessionType = 4
    peer.endUserInventory = syntheticEUSInventory()
    peer.suppressResponse = { handle, opcode, payload in handle == 14 && opcode == 2 && payload == Data([1, 0]) }
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key, purpose: .readOnlyBackup)
    let deadline = Date().addingTimeInterval(1)
    let result = try await session.readEndUserSettings(deadline: deadline)
    #expect(Date() >= deadline)
    #expect(result.partial && result.data.inventory == peer.endUserInventory && result.data.metadata == Data([0xA0]))
    #expect(result.data.records.map { [$0.scope, $0.id] } == [[0, 0]])
    #expect(peer.serviceTrace.filter { $0.handle == 14 && $0.opcode == 2 }.map(\.payload) == [Data([0, 0]), Data([1, 0])])
    #expect(peer.transactionTypes == [5, 5, 2, 2] && peer.transaction == nil)
    #expect(peer.serviceTrace.last?.handle == 8 && peer.serviceTrace.last?.opcode == 9)
    await session.stop()
    #expect(!peer.consumerOpen && peer.controlOpcodes.last == 2)
}

@MainActor @Test func endUserMetadataDeadlineKeepsInventoryWithoutStartingScopeReads() async throws {
    let peer = SyntheticUTLPeer(); peer.advertiseEndUserSettings = true; peer.expectedSessionType = 4
    peer.endUserInventory = syntheticEUSInventory()
    peer.suppressResponse = { handle, opcode, _ in handle == 14 && opcode == 1 }
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key, purpose: .readOnlyBackup)
    let result = try await session.readEndUserSettings(deadline: Date().addingTimeInterval(0.5))
    #expect(result.partial && result.data.inventory == peer.endUserInventory)
    #expect(result.data.metadata == nil && result.data.records.isEmpty)
    #expect(peer.serviceTrace.filter { $0.handle == 14 }.map(\.opcode) == [0, 1])
    #expect(peer.transactionTypes == [5, 5] && peer.transaction == nil)
    await session.stop()
    #expect(!peer.consumerOpen && peer.controlOpcodes.last == 2)
}

@MainActor @Test func endUserBackupReadsOnlyAdvertisedPersistedIDsAndPreservesPartialResults() async throws {
    let peer = SyntheticUTLPeer(); peer.advertiseEndUserSettings = true; peer.expectedSessionType = 4
    peer.endUserInventory = syntheticEUSInventory(); peer.rejectEndUserID = 1
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key, purpose: .readOnlyBackup)
    let result = try await session.readEndUserSettings()
    #expect(result.partial && !result.data.isComplete)
    #expect(result.data.records.count == 2)
    #expect(result.data.records.map { [$0.scope, $0.id] } == [[0, 0], [1, 0]])
    #expect(peer.transactionTypes == [5, 5, 2, 2, 2])
    #expect(peer.serviceTrace.filter { $0.handle == 14 && $0.opcode == 2 }.map(\.payload) == [Data([0, 0]), Data([1, 0]), Data([1, 1])])
    #expect(peer.transaction == nil)
    await session.stop()
}

@MainActor @Test func unknownEndUserAccessMetadataIsPreservedWithoutGuessingAReadPlan() async throws {
    let peer = SyntheticUTLPeer(); peer.advertiseEndUserSettings = true; peer.expectedSessionType = 4
    peer.endUserInventory = syntheticEUSInventory(access: "FUTURE")
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key, purpose: .readOnlyBackup)
    let result = try await session.readEndUserSettings()
    #expect(result.partial && result.data.records.isEmpty && result.data.inventory == peer.endUserInventory)
    #expect(peer.serviceTrace.filter { $0.handle == 14 }.map(\.opcode) == [0])
    await session.stop()
}

@MainActor @Test func fittingBackupUsesReadOnlySessionAndOnlyReadNVRAMTransactionsThroughFragments() async throws {
    let peer = SyntheticUTLPeer(); peer.advertiseFitting = true; peer.expectedSessionType = 4
    peer.fittingRecord = syntheticFittingRecord()
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key, purpose: .readOnlyBackup)
    let record = try await session.readFittingSystemRecord(hiidVersion: "4.5")
    #expect(record == peer.fittingRecord)
    #expect(peer.transactionTypes == [2, 2, 2, 2, 2]) // header +3bodychunks + repeatedheader
    #expect(peer.fittingHeaderReadCount == 2)
    #expect(peer.serviceTrace.filter { $0.handle == 13 }.allSatisfy { $0.opcode == 0 })
    let traceCount = peer.serviceTrace.count
    await #expect(throws: (any Error).self) { try await session.setSpeechBooster(enabled: true) }
    let eq = try OticonEqualizer.State(rawSteps: .init(repeating: 0, count: 8),
        minimumSteps: .init(repeating: -1, count: 8), maximumSteps: .init(repeating: 1, count: 8), stepDB: 0.25)
    await #expect(throws: (any Error).self) { try await session.setEqualizer(microphone: true, steps: .init(repeating: 1, count: 8), expected: eq) }
    #expect(peer.serviceTrace.count == traceCount)
    await session.stop()
    #expect(!peer.consumerOpen && peer.transaction == nil && peer.controlOpcodes.last == 2)
}

@MainActor @Test func fittingReadRejectionCancelsWithoutEscalatingOrWritingMemory() async throws {
    let peer = SyntheticUTLPeer(); peer.advertiseFitting = true; peer.expectedSessionType = 4; peer.rejectFittingRead = true
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key, purpose: .readOnlyBackup)
    await #expect(throws: UTLProtocol.CodecError.responseStatus(0xD4)) { try await session.readFittingSystemRecord(hiidVersion: "4.5") }
    #expect(peer.transactionTypes == [2] && peer.transaction == nil)
    #expect(peer.serviceTrace.suffix(3).map(\.opcode) == [7, 0, 9])
    #expect(peer.serviceTrace.filter { $0.handle == 8 && $0.opcode == 0 }.count == 1)
    await session.stop()
}

@MainActor @Test func fittingReadRefusesAChangedReservedHeaderAndUnknownHIID() async throws {
    let peer = SyntheticUTLPeer(); peer.advertiseFitting = true; peer.expectedSessionType = 4
    peer.fittingRecord = syntheticFittingRecord(); peer.changeRepeatedFittingHeader = true
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key, purpose: .readOnlyBackup)
    let traceCount = peer.serviceTrace.count
    await #expect(throws: (any Error).self) { try await session.readFittingSystemRecord(hiidVersion: "4.6") }
    #expect(peer.serviceTrace.count == traceCount)
    await #expect(throws: OticonFittingRead.DecodeError.headerChanged) { try await session.readFittingSystemRecord(hiidVersion: "4.5") }
    await session.stop()
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

@MainActor @Test func reportedEQFrequenciesStayWithTheirSessionAndBothConsumerSources() async throws {
    let peer = SyntheticUTLPeer()
    let frequencies = [250, 500, 1000, 2000, 3000, 4000, 6000, 8000]
    var payload = Data([0xA2, 0x68]) + Data("stepsize".utf8) + Data([0xF9, 0x34, 0, 0x65]) + Data("freqs".utf8) + Data([0x88])
    for hz in frequencies { payload += Data([0x19, UInt8(hz >> 8), UInt8(hz & 255)]) }
    peer.equalizerInfoOverride = payload
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 3, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key)
    let step = try await session.equalizerStep()
    for source in [true, false] {
        let state = try await session.equalizer(microphone: source, stepDB: step)
        #expect(state.frequenciesHz == frequencies.map(Double.init))
    }
    #expect(peer.serviceTrace.filter { $0.handle == 9 }.map(\.opcode) == [2, 3, 0])
    await session.stop()
    #expect(session.equalizerMetadata == nil)
}

@MainActor @Test func eightChannelWritesConfirmExactReadbackAndKeepTheOtherConsumerSource() async throws {
    let peer = SyntheticUTLPeer()
    peer.currentSteps = [-9, 2, 11, 5, -1, 8, 7, -6]
    peer.currentStreamingSteps = [4, -2, 1, 0, -3, 5, -8, 6]
    let originalMicrophone = peer.currentSteps, originalStreaming = peer.currentStreamingSteps
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 3, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key)
    let step = try await session.equalizerStep()
    let microphone = try await session.equalizer(microphone: true, stepDB: step)
    var desired = microphone.channelDB
    desired[3] += step
    let result = try await session.setEqualizer(microphone: true,
        steps: microphone.steps(forChannelDB: desired), expected: microphone)
    var expectedMicrophone = originalMicrophone
    expectedMicrophone[3] += 1
    #expect(result.rawSteps == expectedMicrophone && peer.currentSteps == expectedMicrophone)
    #expect(peer.currentStreamingSteps == originalStreaming)
    let streaming = try await session.equalizer(microphone: false, stepDB: step)
    desired = streaming.channelDB; desired[6] -= step
    let streamed = try await session.setEqualizer(microphone: false,
        steps: streaming.steps(forChannelDB: desired), expected: streaming)
    var expectedStreaming = originalStreaming
    expectedStreaming[6] -= 1
    #expect(streamed.rawSteps == expectedStreaming && peer.currentStreamingSteps == expectedStreaming)
    #expect(peer.currentSteps == expectedMicrophone)
    #expect(peer.serviceTrace.filter { $0.handle == 9 && $0.opcode == 4 }.count == 1)
    #expect(peer.serviceTrace.filter { $0.handle == 9 && $0.opcode == 1 }.count == 1)
    await session.stop()
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

@MainActor @Test func speechBoosterBatchesReportedMaximaAndConfirmsEnableAndDisable() async throws {
    let peer = SyntheticUTLPeer(); peer.advertiseSpeechBooster = true
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key)
    #expect(session.supportsSpeechBooster)
    #expect(try await session.setSpeechBooster(enabled: true).isEnabled)
    #expect(peer.speechValues == peer.speechMaximum)
    let trace = peer.serviceTrace.map { "\($0.handle)/\($0.opcode)" }
    #expect(trace.suffix(15) == ["8/7", "10/0", "10/2", "10/4", "8/8", "8/7", "10/1", "10/3", "10/5", "8/8", "8/7", "10/0", "10/2", "10/4", "8/8"])
    #expect(try await session.setSpeechBooster(enabled: false).isEnabled == false)
    #expect(peer.serviceTrace.contains { $0.handle == 10 && $0.opcode == 6 && $0.payload.isEmpty })
    #expect(!peer.serviceTrace.contains { $0.handle == 8 && $0.opcode >= 10 }) // no device reset/fitting state
}

@MainActor @Test func batteryTelemetryReadUsesConsumerEnvelopeAndFixedWidthDecoder() async throws {
    let peer = SyntheticUTLPeer(); peer.advertiseBattery = true
    peer.batteryTrailingData = Data([0x12, 0x34, 0x56])
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key)
    let telemetry = try await session.batteryTelemetry()
    #expect(telemetry.percentage == 50)
    #expect(telemetry.estimatedTimeLeftSeconds == 43_200)
    #expect(peer.serviceTrace.map { "\($0.handle)/\($0.opcode)" }.suffix(3) == ["8/7", "7/2", "8/8"])
}

@MainActor @Test func hearingAidIdentificationUsesReadOnlyCommandAndDoesNotLogSerialOrRawMap() async throws {
    let peer = SyntheticUTLPeer(); peer.advertiseIdentification = true
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    var diagnostics: [String] = []
    let session = try UTLSession(info: info, physicalATTMTU: 247, diagnostic: { diagnostics.append($0) }) {
        uuid, data in try await peer.write(uuid, data)
    }
    peer.session = session
    try await session.start(key: peer.key)
    #expect(session.supportsIdentification)
    let identity = try await session.identification()
    let retained = try #require(session.identificationPayload)
    #expect(try OticonIdentification.decodeHiid(retained) == identity)
    #expect(identity.serialNumber == "00000042")
    #expect(peer.serviceTrace.map { "\($0.handle)/\($0.opcode)" }.suffix(3) == ["8/7", "11/3", "8/8"])
    #expect(diagnostics == ["Hearing aid identification read (HIID 4.6)."])
    #expect(!diagnostics.joined().contains("00000042"))
    #expect(!diagnostics.joined().contains("A21903E9"))
    await session.stop()
    #expect(session.identificationPayload == nil)
}

@MainActor @Test func deviceMetadataQueriesUseOnlyTheirReadOpcodesAndConsumerTransactions() async throws {
    let peer = SyntheticUTLPeer()
    peer.advertiseIdentification = true; peer.advertiseBattery = true; peer.advertiseDiagnostics = true
    let info = try UTLProtocol.GattInformation(data: Data([1, 0, 1, 0, 0, 244, 1, 1, 0x80, 0x80, 0x80, 0x80]))
    let session = try UTLSession(info: info, physicalATTMTU: 247) { uuid, data in try await peer.write(uuid, data) }
    peer.session = session
    try await session.start(key: peer.key)
    _ = try await session.identification()
    let health = try await session.batteryHealth()
    let dumps = try await session.coreDumpInfo()
    #expect(health.lifespan == 90 && health.lifespanThreshold == 60)
    #expect(health.slowAverageCurrentDraw == 1_000 && health.fullChargeCapacity == 20_000)
    #expect(dumps.lastDumpCounter == 0x1234 && dumps.storedCrashDumps == 2)
    #expect(peer.serviceTrace.map { "\($0.handle)/\($0.opcode)" }.suffix(9)
        == ["8/7", "11/3", "8/8", "8/7", "7/1", "8/8", "8/7", "12/0", "8/8"])
    #expect(peer.serviceTrace.filter { ![UInt8(0), 8].contains($0.handle) }.allSatisfy { $0.payload.isEmpty })
}
