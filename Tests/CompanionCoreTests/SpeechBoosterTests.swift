import Foundation
import Testing
@testable import CompanionCore

@Test func speechBoosterUsesAllReportedMaximaAndSignedValues() throws {
    let mixed = try OticonSpeechBooster.State(noiseReduction: Data([1, 0xFC, 3]),
        directionality: Data([5, 0xFD, 5]), targetLoss: Data([0xFE, 0xFE, 2]))
    #expect(!mixed.isEnabled)
    #expect(mixed.noiseReduction.range == -4...3)
    #expect(mixed.enableCommands.map(\.opcode) == [1, 3, 5])
    #expect(mixed.enableCommands.map(\.payload) == [Data([3]), Data([5]), Data([2])])
    let enabled = try OticonSpeechBooster.State(noiseReduction: Data([3, 0xFC, 3]),
        directionality: Data([5, 0xFD, 5]), targetLoss: Data([2, 0xFE, 2]))
    #expect(enabled.isEnabled)
}

@Test func speechBoosterRejectsMalformedOrUnsupportedContracts() throws {
    #expect(throws: (any Error).self) { try OticonSpeechBooster.Adjustment(Data([2, 0, 1])) }
    #expect(throws: (any Error).self) { try OticonSpeechBooster.Adjustment(Data([0, 1, 0])) }
    #expect(throws: (any Error).self) { try OticonSpeechBooster.Adjustment(Data([0, 1])) }
    func service(_ major: UInt8, _ minor: UInt8) -> UTLProtocol.Service {
        .init(id: OticonSpeechBooster.serviceID, handle: 10, major: major, minor: minor, status: 255)
    }
    #expect(OticonSpeechBooster.supports(service(1, 1)))
    #expect(OticonSpeechBooster.supports(service(1, 2)))
    #expect(!OticonSpeechBooster.supports(service(1, 0)))
    #expect(!OticonSpeechBooster.supports(service(2, 0)))
}

@Test func legacySpeechBoosterPreservesOtherCharacteristicFields() throws {
    for length in [7, 8, 9] {
        let current = Data(Array(0..<length).map(UInt8.init))
        let enabled = try OticonSpeechBooster.legacyPayload(current: current, enabled: true)
        #expect(OticonSpeechBooster.legacyEnabled(enabled) == true)
        #expect(enabled.prefix(2) == current.prefix(2))
        if length > 7 { #expect(enabled.last == current.last) }
        let disabled = try OticonSpeechBooster.legacyPayload(current: enabled, enabled: false)
        #expect(OticonSpeechBooster.legacyEnabled(disabled) == false)
        #expect(disabled.prefix(2) == current.prefix(2))
        if length > 7 { #expect(disabled.last == current.last) }
    }
    #expect(OticonSpeechBooster.legacyEnabled(Data(repeating: 0, count: 6)) == nil)
    #expect(throws: (any Error).self) { try OticonSpeechBooster.legacyPayload(current: Data(repeating: 0, count: 6), enabled: true) }
}
