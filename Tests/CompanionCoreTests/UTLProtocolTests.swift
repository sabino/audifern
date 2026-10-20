import XCTest
@testable import CompanionCore

/// Byte fixtures are synthetic protocol examples, not captured user data.
final class UTLProtocolTests: XCTestCase {
    typealias U = UTLProtocol

    func testGattInformationUsesNetworkByteOrder() throws {
        let info = try U.GattInformation(data: Data([1, 1, 1, 0, 0, 244, 5, 3, 128, 128, 128, 0]))
        XCTAssertEqual(info.adaptationMTU, 244)
        XCTAssertEqual(info.freeConnections, 5)
        XCTAssertEqual(info.maximumChannels, 3)
        XCTAssertEqual(info.channels.map(\.state), [.closed, .closed, .closed, .none])
        XCTAssertEqual(try info.negotiatedAdaptationMTU(physicalATTMTU: 247), 240)
        XCTAssertThrowsError(try info.negotiatedAdaptationMTU(physicalATTMTU: 20))
        XCTAssertThrowsError(try U.GattInformation(data: Data(repeating: 0, count: 11)))
    }

    func testControlFramesUseBigEndianClientIdentity() throws {
        XCTAssertEqual(try U.openChannel(clientID: 0x12345678, channel: 2, initialSequence: 15),
                       Data([1, 0x12, 0x34, 0x56, 0x78, 2, 15, 100, 0]))
        XCTAssertEqual(try U.closeChannel(clientID: 0x12345678, channel: 2),
                       Data([2, 0x12, 0x34, 0x56, 0x78, 2, 0x40]))
        XCTAssertThrowsError(try U.openChannel(clientID: 1, channel: 4, initialSequence: 0))
        XCTAssertThrowsError(try U.openChannel(clientID: 1, channel: 0, initialSequence: 16))
        XCTAssertEqual(try U.ControlNotification(data: Data([0x41, 0x12, 0x34, 0x56, 0x78])),
                       .closing(clientID: 0x12345678, extra: Data()))
    }

    func testAuthenticationCodecRequiresExplicitFourteenByteProof() throws {
        let challenge = Data(repeating: 7, count: 14)
        XCTAssertEqual(try U.authenticationFrame(clientID: 1, channel: 3, isProof: false, challengeOrProof: challenge),
                       Data([3, 0, 0, 0, 1, 0x30]) + challenge)
        let decoded = try U.ControlNotification(data: Data([0x43, 0, 0, 0, 1, 0x30]) + challenge)
        XCTAssertEqual(decoded, .serverChallenge(clientID: 1, channelKeyIndex: 0x30, value: challenge))
        XCTAssertThrowsError(try U.authenticationFrame(clientID: 1, channel: 0, isProof: true, challengeOrProof: Data()))
        XCTAssertThrowsError(try U.ControlNotification(data: Data([0x42, 0, 0, 0, 1, 0])))
    }

    func testCreditsWrapAndCannotSendBeforePeerGrant() throws {
        var ledger = try U.Credits(initialSequence: 15)
        XCTAssertThrowsError(try ledger.send(Data([1])))
        XCTAssertEqual(ledger.sendSequence, 15)
        _ = try ledger.receive(Data([0xFF, 0x81, 2]))
        XCTAssertEqual(ledger.expectedReceiveSequence, 0)
        XCTAssertEqual(try ledger.send(Data([0xAA])), Data([0x0F, 0xAA]))
        let incoming = try ledger.receive(Data([0x20, 0xBB]))
        XCTAssertEqual(incoming.payload, Data([0xBB]))
        XCTAssertEqual(ledger.clientCredits, 99)
        XCTAssertEqual(try ledger.send(Data([0xCC])), Data([0x10, 0xCC]))
        XCTAssertEqual(ledger.clientCredits, 100)
        XCTAssertEqual(ledger.serverCredits, 2)
    }

    func testInvalidCreditSequenceDoesNotMutateLedger() throws {
        var ledger = try U.Credits(initialSequence: 4)
        XCTAssertThrowsError(try ledger.receive(Data([0xF5, 0x81, 7])))
        XCTAssertEqual(ledger.serverCredits, 0)
        XCTAssertEqual(ledger.expectedReceiveSequence, 4)
        XCTAssertThrowsError(try ledger.receive(Data([0xF4, 0x99, 7])))
        XCTAssertEqual(ledger.expectedReceiveSequence, 4)
        _ = try ledger.receive(Data([0xF4, 0x81, 7]))
        XCTAssertEqual(ledger.serverCredits, 7)
    }

    func testReceiveCreditsAndDiscardControlsDoNotRequireSendCredits() throws {
        var ledger = try U.Credits(initialSequence: 3, maximumClientCredits: 2, replenishmentThreshold: 2)
        let data = try ledger.receive(Data([3, 0xAA]))
        XCTAssertEqual(data.replies, [Data([0xF3, 1, 1])])
        XCTAssertEqual(ledger.clientCredits, 2)
        XCTAssertEqual(ledger.serverCredits, 0)
        _ = try ledger.receive(Data([0xF4, 0x81, 3]))
        let discarded = try ledger.receive(Data([0xF5, 0x83, 7]))
        XCTAssertEqual(discarded.replies, [Data([0xF4, 2, 3])])
        XCTAssertEqual(ledger.serverCredits, 0)
        XCTAssertEqual(try ledger.keepAlive(), Data([0xF5, 1, 0]))
    }

    func testTransportDecoderSurvivesEverySingleSplitBoundary() throws {
        let control = try U.negotiationRequest(maximumMTU: 1024)
        XCTAssertEqual(control.data, Data([0x20, 0, 2, 1, 1, 4, 0]))
        let request = try U.discoveryRequest(identifier: 1)
        let frame = try U.TransportFrame(kind: .data, final: true, payload: request)
        let wire = control.data + frame.data
        for split in 0...wire.count {
            var decoder = U.TransportDecoder()
            let a = try decoder.append(Data(wire.prefix(split)))
            let b = try decoder.append(Data(wire.dropFirst(split)))
            XCTAssertEqual(a + b, [control, frame], "split \(split)")
            XCTAssertEqual(decoder.pendingByteCount, 0)
        }
    }

    func testControlTransportLengthExcludesIdentityAndOpcode() throws {
        var decoder = U.TransportDecoder()
        XCTAssertEqual(try decoder.append(Data([0x20, 0, 3, 1, 2, 0, 64])), [])
        XCTAssertEqual(decoder.pendingByteCount, 7)
        let frames = try decoder.append(Data([0x40]))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(try U.negotiatedTransportMTU(from: XCTUnwrap(frames.first)), 64)
        let accepted = try U.TransportFrame(kind: .control, final: true, identifier: 1, opcode: 2, payload: Data([0, 64, 0x41]))
        XCTAssertThrowsError(try U.negotiatedTransportMTU(from: accepted))
    }

    func testTransportFragmentationKeepsServiceHeaderAndSignedPayload() throws {
        let raw = Data([0x1C, 1, 7, 0x40, 0xFD, 0xF8, 4])
        let first = try U.TransportFrame(kind: .data, final: false, totalLength: raw.count, payload: Data(raw.prefix(3)))
        let last = try U.TransportFrame(kind: .continuation, final: true, payload: Data(raw.dropFirst(3)))
        var decoder = U.MessageDecoder()
        XCTAssertNil(try decoder.receive(first))
        let message = try XCTUnwrap(decoder.receive(last))
        XCTAssertEqual(message.identifier, 1)
        XCTAssertEqual(message.serviceHandle, 7)
        XCTAssertEqual(message.payload, Data([0xFD, 0xF8, 4]))
        XCTAssertEqual(message.status, U.Status(0x40))
        var orphan = U.MessageDecoder()
        XCTAssertThrowsError(try orphan.receive(last))
    }

    func testServiceFragmentsAndInterleavedEventPreserveIdentity() throws {
        var decoder = U.MessageDecoder()
        XCTAssertNil(try decoder.receive(frame([0x14, 1, 7, 0x40, 0xFD])))
        let event = try XCTUnwrap(decoder.receive(frame([0x2C, 0, 7, 0, 5])))
        XCTAssertEqual(event.messageType, .event)
        XCTAssertThrowsError(try decoder.receive(frame([0x5C, 3, 7, 0xF8, 4])))
        let finished = try XCTUnwrap(decoder.receive(frame([0x5C, 1, 7, 0xF8, 4])))
        XCTAssertEqual(finished.payload, Data([0xFD, 0xF8, 4]))
    }

    func testDiscoveryUsesBigEndianIDsAndRuntimeAvailability() throws {
        let response = try message([0x1C, 1, 0, 0x40, 2, 0, 0, 13, 7, 1, 3, 255,
                                    2, 0, 0, 14, 9, 2, 1, 0])
        let services = try U.services(from: response)
        XCTAssertEqual(services.map(\.id), [0x0200000D, 0x0200000E])
        XCTAssertTrue(services[0].isAvailable)
        XCTAssertFalse(services[1].isAvailable)
        XCTAssertEqual(try U.volumeReadRequest(identifier: 3, service: services[0]), Data([0x0C, 3, 7, 0]))
        XCTAssertThrowsError(try U.programReadRequest(identifier: 5, service: services[1]))
    }

    func testVolumeRequiresSuccessAndValidReportedRange() throws {
        let service = try XCTUnwrap(U.services(from: message([0x1C, 1, 0, 0x40, 2, 0, 0, 13, 7, 1, 3, 255])).first)
        let value = try U.volume(from: message([0x1C, 3, 7, 0x40, 0xFD, 0xF8, 4]), service: service)
        XCTAssertEqual(value.value, -3)
        XCTAssertEqual(value.range, -8...4)
        XCTAssertThrowsError(try U.volume(from: message([0x1C, 3, 7, 0x41, 0xFD, 0xF8, 4]), service: service))
        XCTAssertThrowsError(try U.volume(from: message([0x1C, 3, 7, 0x40, 5, 0xF8, 4]), service: service))
        XCTAssertThrowsError(try U.volume(from: message([0x1C, 3, 8, 0x40, 0xFD, 0xF8, 4]), service: service))
    }

    func testMalformedPartsAndTransportNeverBecomeState() throws {
        for raw in [[UInt8](), [0x1C, 1, 7], [0x18, 1, 7, 0x40], [0x3C, 1, 7, 0x40]] {
            XCTAssertThrowsError(try U.MessagePart(data: Data(raw)))
        }
        var transport = U.TransportDecoder()
        XCTAssertThrowsError(try transport.append(Data([0xC0, 0, 1, 0])))
        XCTAssertEqual(transport.pendingByteCount, 0)
        var messages = U.MessageDecoder()
        let secure = try U.TransportFrame(kind: .data, final: true, secure: true, payload: Data([0x1C, 1, 7, 0x40]))
        XCTAssertThrowsError(try messages.receive(secure))
    }

    private func frame(_ bytes: [UInt8]) throws -> U.TransportFrame {
        try U.TransportFrame(kind: .data, final: true, payload: Data(bytes))
    }

    private func message(_ bytes: [UInt8]) throws -> U.ServiceMessage {
        var decoder = U.MessageDecoder()
        return try XCTUnwrap(decoder.receive(frame(bytes)))
    }
}
