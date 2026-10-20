import Foundation
import Testing
@testable import CompanionCore

@Test func hearingDiscoveryRecognizesPublishedServiceForms() {
    #expect(HearingAidDiscovery.candidateReasons(name: nil, services: ["0000fdf0-0000-1000-8000-00805f9b34fb"]) == ["ASHA service"])
    #expect(HearingAidDiscovery.candidateReasons(name: nil, services: ["1854"]) == ["Hearing Access service"])
    #expect(HearingAidDiscovery.normalizedUUID("12345678-0000-1000-8000-00805F9B34FB") == "12345678-0000-1000-8000-00805F9B34FB")
}

@Test func discoveryHintsAreConservative() {
    #expect(!HearingAidDiscovery.candidateReasons(name: "Oticon Intent", services: []).isEmpty)
    #expect(!HearingAidDiscovery.candidateReasons(name: "Aparelhos Auditivos", services: []).isEmpty)
    #expect(HearingAidDiscovery.candidateReasons(name: "Bluetooth Speaker", services: ["180A", "180F"]).isEmpty)
    #expect(HearingAidDiscovery.candidateReasons(name: nil, services: []).isEmpty)
}

@Test func companyIdentifierUsesBluetoothLittleEndian() {
    #expect(HearingAidDiscovery.manufacturerCompanyID(Data([0x4C, 0x00, 0x01])) == 0x004C)
    #expect(HearingAidDiscovery.manufacturerCompanyID(Data([0x01])) == nil)
}

@Test func standardBatteryRejectsMalformedAndOutOfRangeValues() {
    #expect(StandardGATT.batteryPercentage(Data([0])) == 0)
    #expect(StandardGATT.batteryPercentage(Data([100])) == 100)
    #expect(StandardGATT.batteryPercentage(Data([101])) == nil)
    #expect(StandardGATT.batteryPercentage(Data()) == nil)
    #expect(StandardGATT.batteryPercentage(Data([50, 60])) == nil)
}

@Test func onlyDocumentedStandardCharacteristicsAreRead() {
    #expect(StandardGATT.isPermittedRead(service: "180A", characteristic: "2A29"))
    #expect(StandardGATT.isPermittedRead(service: "180F", characteristic: "2A19"))
    #expect(!StandardGATT.isPermittedRead(service: "1234", characteristic: "2A19"))
    #expect(!StandardGATT.isPermittedRead(service: "1854", characteristic: "2B82"))
    #expect(!StandardGATT.isPermittedRead(service: "180A", characteristic: "FFFF"))
}

@Test func textDecodingPreservesContentAndRejectsInvalidPayloads() {
    #expect(StandardGATT.informationString(Data(" Oticon\0".utf8)) == "Oticon")
    #expect(StandardGATT.informationString(Data([0xFF, 0xFE])) == nil)
    #expect(StandardGATT.informationString(Data("a\0b".utf8)) == nil)
    #expect(StandardGATT.displayValue(service: "180F", characteristic: "2A19", data: Data([90])) == "90%")
}
