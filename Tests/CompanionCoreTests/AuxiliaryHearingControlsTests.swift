import Foundation
import Testing
@testable import CompanionCore

private func auxiliaryAid(_ level: Int8, muted: Bool, range: ClosedRange<Int> = -4...3,
                          eligible: Bool? = true) -> AuxiliaryHearingControls.Aid {
    .init(current: OticonRemoteProtocol.Volume(data: Data([UInt8(bitPattern: level), muted ? 0 : 1]))!,
          range: range, programEligible: eligible)
}

@Test func auxiliaryStepsAndMutePreserveEachEarsOtherFieldAndLevelOffset() {
    let aids = [auxiliaryAid(-2, muted: true), auxiliaryAid(1, muted: false)]
    #expect(AuxiliaryHearingControls.payloads(for: aids, change: .adjust(1)) == [Data([0xFF, 0]), Data([2, 1])])
    #expect(AuxiliaryHearingControls.payloads(for: aids, change: .muted(false)) == [Data([0xFE, 1]), Data([1, 1])])
    #expect(AuxiliaryHearingControls.payloads(for: aids, change: .muted(true)) == [Data([0xFE, 0]), Data([1, 0])])
}

@Test func auxiliaryPlanRejectsTheEntireGroupBeforeAnyWriteIfOneEarFailsPreflight() {
    let valid = auxiliaryAid(-1, muted: false)
    #expect(AuxiliaryHearingControls.payloads(for: [valid, auxiliaryAid(3, muted: true)], change: .adjust(1)) == nil)
    for eligible in [Optional<Bool>.none, false] {
        #expect(AuxiliaryHearingControls.payloads(for: [valid, auxiliaryAid(0, muted: true, eligible: eligible)], change: .muted(false)) == nil)
    }
    #expect(AuxiliaryHearingControls.payloads(for: [], change: .adjust(1)) == nil)
    #expect(AuxiliaryHearingControls.payloads(for: [valid, valid, valid], change: .adjust(1)) == nil)
    #expect(AuxiliaryHearingControls.payloads(for: [valid], change: .adjust(2)) == nil)
    #expect(AuxiliaryHearingControls.payloads(for: [auxiliaryAid(-5, muted: false)], change: .muted(true)) == nil)
    #expect(AuxiliaryHearingControls.payloads(for: [auxiliaryAid(0, muted: false, range: -129...3)], change: .adjust(1)) == nil)
}

@Test func onlyActualMappedStreamingCategoriesQualifyAndTinnitusTakesPrecedence() {
    for category in [UInt8(10), 11, 201, 255] {
        #expect(AuxiliaryHearingControls.supportsStreaming(category: category, tinnitus: false))
        #expect(!AuxiliaryHearingControls.supportsStreaming(category: category, tinnitus: true))
    }
    for category in [UInt8(0), 1, 6, 7, 8, 9, 200, 254] {
        #expect(!AuxiliaryHearingControls.supportsStreaming(category: category, tinnitus: false))
    }
}

@Test func auxiliaryAddressesAreIndependentOfMicrophoneAndStandardBluetoothVolume() {
    #expect(AuxiliaryHearingControls.Source.tinnitus.characteristic == "E5892EBE-97D0-4F97-8F8E-CB85D16A4CC1")
    #expect(AuxiliaryHearingControls.Source.streaming.characteristic == "50632720-4C0F-4BC4-960A-2404BDFDFBCA")
    #expect(AuxiliaryHearingControls.Source.tinnitus.characteristic != OticonRemoteProtocol.mainVolume)
    #expect(AuxiliaryHearingControls.Source.streaming.characteristic != OticonRemoteProtocol.mainVolume)
}
