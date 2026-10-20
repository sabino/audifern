import Foundation
import Testing
@testable import CompanionCore

@Test func legacyEQPreservesTinnitusAndUsesSignedSteps() throws {
    let tinnitus = Data([1, 2, 3, 4, 5, 6, 7, 8])
    let original = tinnitus + Data(repeating: 0, count: 8)
    let state = try OticonEqualizer.legacyStreamingState(original)
    let steps = try state.steps(forThreeBandDB: [-6, 0, 3])
    #expect(steps == [-32, 0, 0, 0, 16, 16, 16, 16])
    let payload = try OticonEqualizer.legacyStreamingPayload(current: original, steps: steps)
    #expect(payload.prefix(8) == tinnitus)
    #expect(payload.suffix(8) == Data([224, 0, 0, 0, 16, 16, 16, 16]))
    let decoded = try OticonEqualizer.legacyStreamingState(payload)
    #expect(abs(decoded.threeBandDB[0] + 6.0206) < 0.001)
    #expect(!decoded.rangesReportedByDevice)
}

@Test func threeBandEQUsesIntersectionOfEveryConstituentRange() throws {
    let state = try OticonEqualizer.State(rawSteps: [0, 0, 0, 0, 0, 0, 0, 0],
        minimumSteps: [-20, -10, -8, -6, -5, -4, -3, -2], maximumSteps: [20, 10, 8, 6, 5, 4, 3, 2], stepDB: 0.5)
    #expect(state.threeBandRangesDB == [-10.0...10.0, -3.0...3.0, -1.0...1.0])
    #expect(throws: OticonEqualizer.EQError.outOfRange) { try state.steps(forThreeBandDB: [0, 4, 0]) }
    #expect(throws: OticonEqualizer.EQError.outOfRange) { try state.validate([0, 0, 0, 0, 0, 0, 0, 3]) }
    #expect(throws: OticonEqualizer.EQError.malformed) { try state.steps(forThreeBandDB: [0, .nan, 0]) }
}

@Test func malformedAndUnsupportedLegacyEQCannotBeWritten() throws {
    #expect(throws: OticonEqualizer.EQError.unsupported) { try OticonEqualizer.legacyStreamingState(Data(repeating: 0, count: 8)) }
    let original = Data(repeating: 0, count: 16)
    #expect(throws: OticonEqualizer.EQError.outOfRange) { try OticonEqualizer.legacyStreamingPayload(current: original, steps: .init(repeating: 127, count: 8)) }
}

@Test func programMetadataIsUTF8LengthDelimitedAndNotAProgramSwitch() throws {
    let name = Data("Geral – música".utf8)
    let program = try OticonProgramInfo.Program(data: Data([1, UInt8(name.count)]) + name + Data([3]), id: 0)
    #expect(program.label == "Geral – música")
    #expect(program.tinnitus && program.boostable)
    #expect(OticonProgramInfo.selector != OticonRemoteProtocol.activeProgram)
    #expect(throws: OticonEqualizer.EQError.malformed) { try OticonProgramInfo.Program(data: Data([0, 25, 1]), id: 0) }
    #expect(throws: OticonEqualizer.EQError.malformed) { try OticonProgramInfo.Program(data: Data([0, 1, 0xFF, 0]), id: 0) }
}

@Test func CBORVectorsSupportSignedAndUnsignedByteRepresentations() throws {
    let levels = [-32, 0, 0, 0, 16, 16, 16, 16]
    let encoded = try UTLCBOR.unsignedVector(levels)
    let minimum = try UTLCBOR.unsignedVector(.init(repeating: -40, count: 8))
    let maximum = try UTLCBOR.unsignedVector(.init(repeating: 30, count: 8))
    let decoded = try UTLAdvanced.equalizerState(encoded + minimum + maximum, stepDB: 0.25)
    #expect(decoded.rawSteps == levels)
    #expect(decoded.minimumSteps == .init(repeating: -40, count: 8))
    #expect(decoded.rangesReportedByDevice)
    #expect(throws: (any Error).self) { try UTLAdvanced.equalizerState(encoded + minimum, stepDB: 0.25) }
}

@Test func CBORInfoStepIsParsedAndInvalidEncodingsAreRejected() throws {
    // {"stepsize": 0.25}, CBOR double precision.
    let bytes = Data([0xA1, 0x68]) + Data("stepsize".utf8) + Data([0xFB, 0x3F, 0xD0, 0, 0, 0, 0, 0, 0])
    #expect(try UTLAdvanced.equalizerInfo(bytes) == 0.25)
    #expect(throws: OticonEqualizer.EQError.malformed) { try UTLCBOR.decodeSequence(Data([0x83, 1])) }
    #expect(throws: OticonEqualizer.EQError.malformed) { try UTLCBOR.decodeSequence(Data([0x63, 0xFF, 0xFF, 0xFF])) }
    #expect(throws: OticonEqualizer.EQError.unsupported) { try UTLCBOR.decodeSequence(Data([0x9F, 0xFF])) }
    let duplicateMap = Data([0xA2, 0x61, 0x61, 1, 0x61, 0x61, 2])
    #expect(throws: OticonEqualizer.EQError.malformed) { try UTLCBOR.decodeSequence(duplicateMap) }
}

@Test func equalizerSupportIsVersionBounded() throws {
    func service(_ major: UInt8, _ minor: UInt8) -> UTLProtocol.Service {
        .init(id: UTLAdvanced.equalizerServiceID, handle: 9, major: major, minor: minor, status: 0xFF)
    }
    #expect(!UTLAdvanced.supportsEqualizer(service(1, 0), microphone: true))
    #expect(UTLAdvanced.supportsEqualizer(service(1, 0), microphone: false))
    #expect(UTLAdvanced.supportsEqualizer(service(1, 1), microphone: true))
    #expect(UTLAdvanced.supportsEqualizer(service(2, 0), microphone: true))
    #expect(!UTLAdvanced.supportsEqualizer(service(2, 1), microphone: true))
    let request = try UTLAdvanced.request(identifier: 3, service: service(2, 0), opcode: 3)
    #expect(request == Data([0x0C, 3, 9, 3]))
}

@Test func consumerSessionEnvelopeUsesInteractiveAndCommandNotMemoryTransactions() throws {
    let session = UTLProtocol.Service(id: UTLConsumerSession.serviceID, handle: 8, major: 1, minor: 1, status: 0xFF)
    let payload = try UTLConsumerSession.openPayload(service: session, privateToken: 0x11223344,
        timeSince2020: 0x55667788, version: (0, 2, 0))
    #expect(payload == Data([3, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 3, 0, 0, 0, 2, 0, 0, 1]))
    #expect(UTLConsumerSession.transactionPayload(id: 0x1234, starting: true) == Data([5, 0x12, 0x34]))
    #expect(UTLConsumerSession.transactionPayload(id: 0x1234, starting: false) == Data([0x12, 0x34]))
    let unknown = UTLProtocol.Service(id: UTLConsumerSession.serviceID, handle: 8, major: 2, minor: 0, status: 0xFF)
    #expect(!UTLConsumerSession.supports(unknown))
    #expect(throws: (any Error).self) { try UTLConsumerSession.openPayload(service: unknown, privateToken: 1, timeSince2020: 2, version: (0, 2, 0)) }
}

@Test func equalizerV1ConsumerReadsAcceptScalarAndEmptyUnusedBounds() throws {
    let levels = try UTLCBOR.unsignedVector(.init(repeating: 32, count: 8))
    let scalarRanges = Data([0x81, 0, 0x81, 0])
    let emptyRanges = Data([0x80, 0x80])
    for ranges in [scalarRanges, emptyRanges] {
        let state = try UTLAdvanced.equalizerState(levels + ranges, stepDB: OticonEqualizer.defaultStepDB, sdkConsumerRangeDB: -6...6)
        #expect(state.rawSteps == .init(repeating: 32, count: 8))
        #expect(state.minimumSteps == .init(repeating: -32, count: 8))
        #expect(state.maximumSteps == .init(repeating: 32, count: 8))
        #expect(!state.rangesReportedByDevice)
        #expect(throws: (any Error).self) { try UTLAdvanced.equalizerState(levels + ranges, stepDB: OticonEqualizer.defaultStepDB) }
    }
    let invalidLevels = Data([0x87, 0, 0, 0, 0, 0, 0, 0]) + emptyRanges
    #expect(throws: (any Error).self) { try UTLAdvanced.equalizerState(invalidLevels, stepDB: OticonEqualizer.defaultStepDB, sdkConsumerRangeDB: -6...6) }
    #expect(UTLAdvanced.equalizerPayloadSummary(levels + emptyRanges).contains("array[8]{32,32,32,32,32,32,32,32}"))
}
