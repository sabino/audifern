import Foundation
import Testing
@testable import CompanionCore

// Synthetic CBOR only. No device inventory, fitting values or vendor resources.
private func eusText(_ text: String) -> Data {
    let bytes = Data(text.utf8)
    precondition(bytes.count < 24)
    return Data([0x60 | UInt8(bytes.count)]) + bytes
}
private func eusUnsigned(_ number: Int) -> Data {
    if number < 24 { return Data([UInt8(number)]) }
    if number <= 255 { return Data([0x18, UInt8(number)]) }
    return Data([0x19, UInt8(number >> 8), UInt8(number & 0xFF)])
}
private func eusScope(_ name: String, count: Data, access: String = "NVRAM") -> Data {
    Data([0xA3]) + eusText("name") + eusText(name) + eusText("count") + count
        + eusText("access") + eusText(access)
}
private func eusInventory(_ scopes: [Data]) -> Data {
    precondition(scopes.count < 24)
    return Data([0xA1]) + eusText("scopes") + Data([0x81, 0x80 | UInt8(scopes.count)])
        + scopes.reduce(Data(), +)
}

@Test func endUserSettingsRequireExactAdvertisedContract() {
    #expect(OticonEndUserSettings.supports(service: .init(id: 0x02000017, handle: 8, major: 2, minor: 1, status: 0xFF)))
    for service in [UTLProtocol.Service(id: 0x02000006, handle: 8, major: 2, minor: 1, status: 0xFF),
                    .init(id: 0x02000017, handle: 8, major: 1, minor: 1, status: 0xFF),
                    .init(id: 0x02000017, handle: 8, major: 2, minor: 0, status: 0xFF),
                    .init(id: 0x02000017, handle: 8, major: 2, minor: 2, status: 0xFF),
                    .init(id: 0x02000017, handle: 8, major: 3, minor: 0, status: 0xFF),
                    .init(id: 0x02000017, handle: 8, major: 2, minor: 1, status: 0)] {
        #expect(!OticonEndUserSettings.supports(service: service))
    }
    #expect(OticonEndUserSettings.inventoryOpcode == 0)
    #expect(OticonEndUserSettings.metadataOpcode == 1)
    #expect(OticonEndUserSettings.readOpcode == 2)
}

@Test func endUserSettingsPlanUsesOnlyAdvertisedCountsAndWireScopeIDs() throws {
    let raw = eusInventory([
        eusScope("global", count: eusUnsigned(1), access: "RAM_NVRAM"),
        eusScope("situation", count: eusUnsigned(2)),
        eusScope("profile", count: eusText("1"))
    ])
    let inventory = try OticonEndUserSettings.decodeInventory(raw)
    #expect(inventory.raw == raw)
    #expect(inventory.scopes.map(\.name) == ["global", "situation", "profile"])
    #expect(inventory.scopes.map(\.count) == [1, 2, 1])
    #expect(inventory.reads.map { OticonEndUserSettings.readRequest($0) }
            == [Data([0, 0]), Data([1, 0]), Data([1, 1]), Data([2, 0])])
    #expect(inventory.reads.map(\.scopeName) == ["global", "situation", "situation", "profile"])
    #expect(inventory.unknownScopes.isEmpty && inventory.unreadScopes.isEmpty && inventory.isComplete)
}

@Test func endUserSettingsPreserveUnknownAndRAMOnlyScopesWithoutGuessedReads() throws {
    let raw = eusInventory([
        eusScope("global", count: eusUnsigned(1)),
        eusScope("future", count: eusUnsigned(3)),
        eusScope("profile", count: eusUnsigned(2), access: "RAM")
    ])
    let inventory = try OticonEndUserSettings.decodeInventory(raw)
    #expect(inventory.raw == raw)
    #expect(inventory.unknownScopes == ["future"])
    #expect(inventory.unreadScopes == ["future", "profile"])
    #expect(inventory.scopes[1].wireID == nil)
    #expect(inventory.reads.map { OticonEndUserSettings.readRequest($0) } == [Data([0, 0])])
    #expect(!inventory.isComplete)
    #expect(try OticonEndUserSettings.decodeInventory(eusInventory([])).reads.isEmpty)
}

@Test func endUserSettingsUseFirstScopeGroupAndMarkAdditionalGroupsOpaque() throws {
    let first = eusScope("global", count: eusUnsigned(1))
    let second = eusScope("future", count: eusUnsigned(1))
    let raw = Data([0xA1]) + eusText("scopes") + Data([0x82, 0x81]) + first + Data([0x81]) + second
    let inventory = try OticonEndUserSettings.decodeInventory(raw)
    #expect(inventory.scopes.map(\.name) == ["global"])
    #expect(inventory.reads.count == 1)
    #expect(inventory.hasAdditionalScopeGroups && !inventory.isComplete)
    #expect(inventory.raw == raw)
}

@Test func endUserSettingsBoundCountsAndValidateAccessAndUniqueness() throws {
    let maximum = try OticonEndUserSettings.decodeInventory(eusInventory([eusScope("profile", count: eusUnsigned(128))]))
    #expect(maximum.reads.count == 128)
    #expect(OticonEndUserSettings.readRequest(maximum.reads[127]) == Data([2, 127]))
    for counts in [[eusScope("global", count: eusUnsigned(129))],
                   [eusScope("global", count: eusUnsigned(64)), eusScope("profile", count: eusUnsigned(65))],
                   [eusScope("profile", count: eusUnsigned(256))],
                   [eusScope("profile", count: Data([0x20]))],
                   [eusScope("profile", count: eusText(" 1"))],
                   [eusScope("profile", count: eusText("256"))]] {
        #expect(throws: OticonEndUserSettings.DecodeError.countLimit) { try OticonEndUserSettings.decodeInventory(eusInventory(counts)) }
    }
    #expect(throws: OticonEndUserSettings.DecodeError.invalidAccess) {
        try OticonEndUserSettings.decodeInventory(eusInventory([eusScope("global", count: eusUnsigned(1), access: "write")]))
    }
    #expect(throws: OticonEndUserSettings.DecodeError.duplicateScope) {
        try OticonEndUserSettings.decodeInventory(eusInventory([
            eusScope("global", count: eusUnsigned(1)), eusScope("global", count: eusUnsigned(1))]))
    }
}

@Test func endUserSettingsInventoryRejectsMissingFieldsAndAmbiguousKeys() throws {
    let wrongRoot = Data([0x80])
    let missing = Data([0xA0])
    let noGroups = Data([0xA1]) + eusText("scopes") + Data([0x80])
    let flatGroups = Data([0xA1]) + eusText("scopes") + Data([0x81]) + eusScope("global", count: eusUnsigned(1))
    let duplicateKey = Data([0xA2]) + eusText("scopes") + Data([0x81, 0x80])
        + eusText("scopes") + Data([0x81, 0x80])
    let badScope = eusInventory([Data([0xA1]) + eusText("name") + eusText("global")])
    for data in [wrongRoot, missing, noGroups, flatGroups, duplicateKey, badScope] {
        #expect(throws: OticonEndUserSettings.DecodeError.invalidInventory) { try OticonEndUserSettings.decodeInventory(data) }
    }
}

@Test func endUserSettingsResponseValidationRetainsOpaqueCBORWithoutCRCEnvelope() throws {
    let raw = Data([0xA2, 0x01, 0xF5, 0x02, 0x44, 0, 0xFF, 0x7F, 0x80])
    #expect(try OticonEndUserSettings.validateResponse(raw) == raw)
    let indefinite = Data([0xBF, 0x61, 0x78, 0x9F, 0x01, 0xF9, 0x3C, 0x00, 0xFF, 0xFF])
    #expect(try OticonEndUserSettings.validateResponse(indefinite) == indefinite)
    let tagged = Data([0xD9, 0xD9, 0xF7, 0xA0])
    #expect(try OticonEndUserSettings.validateResponse(tagged) == tagged)
    let strings = Data([0x82, 0x5F, 0x41, 1, 0x41, 2, 0xFF, 0x7F, 0x61, 0x61, 0x61, 0x62, 0xFF])
    #expect(try OticonEndUserSettings.validateResponse(strings) == strings)
    let maximum = Data([0x59, 0xFF, 0xFC]) + Data(repeating: 0xAA, count: 65_532)
    #expect(try OticonEndUserSettings.validateResponse(maximum) == maximum)
    let inventory = eusInventory([eusScope("global", count: eusUnsigned(1))])
    let slice = (Data([0xFF]) + inventory).dropFirst()
    #expect(try OticonEndUserSettings.decodeInventory(slice).reads.count == 1)
}

@Test func endUserSettingsCBORRejectsTruncationTrailingDataAndResourceAbuse() throws {
    let valid = eusInventory([eusScope("global", count: eusUnsigned(1))])
    let tooDeep = Data(repeating: 0x81, count: 18) + Data([0])
    let invalidCases: [Data] = [Data(), valid + Data([0]), Data(valid.dropLast()), Data([0xFF]),
                    Data([0x1C]), Data([0x9A, 0xFF, 0xFF, 0xFF, 0xFF]), tooDeep,
                    Data([0x9F, 0]), Data([0xBF, 0, 0xFF]), Data([0x7F, 0x61, 0xFF, 0xFF]),
                    Data([0x5F, 0x5F, 0xFF, 0xFF]), Data([0xF8, 0x1F])]
    for invalid in invalidCases {
        #expect(throws: OticonEndUserSettings.DecodeError.malformedCBOR) { try OticonEndUserSettings.validateResponse(invalid) }
    }
    #expect(throws: OticonEndUserSettings.DecodeError.responseTooLarge) {
        try OticonEndUserSettings.validateResponse(Data(repeating: 0, count: 65_536))
    }
}
