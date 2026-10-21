import Foundation
import Testing
@testable import CompanionCore

private let preferenceIdentity = OticonFittedConfiguration.Identity(
    modelUID: 8513, genericModelUID: 8460, hiidVersion: "4.5",
    releasePackageVersion: "5.0.29", runtimeMemoryMapVersion: "10.0.0")
private let preferenceService = DeviceBackup.Service(UTLProtocol.Service(
    id: 0x02000017, handle: 18, major: 2, minor: 1, status: 0xFF))

// Entirely synthetic CBOR. These fixtures contain no captured preferences,
// device identifiers, clinical data or vendor resources.
private func preferenceHead(_ major: UInt8, _ number: UInt64) -> Data {
    if number < 24 { return Data([major << 5 | UInt8(number)]) }
    if number <= 255 { return Data([major << 5 | 24, UInt8(number)]) }
    if number <= 65_535 { return Data([major << 5 | 25, UInt8(number >> 8), UInt8(number & 255)]) }
    return Data([major << 5 | 27] + (0..<8).reversed().map { UInt8(truncatingIfNeeded: number >> ($0 * 8)) })
}
private func preferenceNumber(_ number: UInt64) -> Data { preferenceHead(0, number) }
private func preferenceText(_ text: String) -> Data { preferenceHead(3, UInt64(text.utf8.count)) + Data(text.utf8) }
private func preferenceArray(_ elements: [Data]) -> Data {
    elements.reduce(preferenceHead(4, UInt64(elements.count)), +)
}
private func preferenceMap(_ pairs: [(Data, Data)]) -> Data {
    pairs.reduce(preferenceHead(5, UInt64(pairs.count))) { $0 + $1.0 + $1.1 }
}

private let preferenceTapLabels = [
    "single_tap_LCUC1", "single_tap_LCUC2", "single_tap_LCUC3", "single_tap_LCUC4", "single_tap_LCUC5", "single_tap_LCUC6",
    "double_tap_LCUC1", "double_tap_LCUC2", "double_tap_LCUC3", "double_tap_LCUC4", "double_tap_LCUC5", "double_tap_LCUC6"
]
private let preferenceIndicatorLabels = [
    "aud_startup", "aud_shutdown", "aud_program", "aud_wax_filter", "aud_service_mode", "aud_flight_mode",
    "aud_batt_final", "aud_batt_low", "aud_batt_warn_pack", "aud_batt_30_pct", "aud_batt_20_pct",
    "aud_vc_default", "aud_vc_limit", "aud_vc_change", "aud_mute", "aud_mobile", "aud_landline", "aud_btd800",
    "aud_tsg_vc_default", "aud_tsg_vc_limit", "aud_tsg_vc_change", "aud_accept_call", "aud_reject_end_call"
]
private let preferenceLevelLabels = ["voice_level", "tonal_level", "tonal_freq"]
private let preferenceTapNames = [
    "none", "program_up", "program_down", "volume_up", "volume_down", "mute", "flight_mode", "accept_call",
    "reject_call", "end_call", "shutdown", "terminate_auracast"
]
private let preferenceModeNames = ["disable_tonal", "enable_tonal", "disable_spoken", "enable_spoken"]
private let preferenceLevelNames = ["low", "medium", "high"]

private func preferenceDefinition(name: String, labels: [String], names: [String], scope: String = "global",
                                  enumeration: Data? = nil,
                                  extra: [(Data, Data)] = []) -> Data {
    preferenceMap([
        (preferenceText("name"), preferenceText(name)), (preferenceText("scope"), preferenceText(scope)),
        (preferenceText("labels"), preferenceArray(labels.map(preferenceText))),
        (preferenceText("emap"), enumeration ?? preferenceMap(names.enumerated().map {
            (preferenceNumber(UInt64($0.offset)), preferenceText($0.element))
        }))
    ] + extra)
}
private func preferenceMetadata(tapLabels: [String] = preferenceTapLabels, tapNames: [String] = preferenceTapNames,
                                tapScope: String = "global", tapName: String = "tap_mapping",
                                indicatorLabels: [String] = preferenceIndicatorLabels,
                                indicatorNames: [String] = preferenceModeNames,
                                levelLabels: [String] = preferenceLevelLabels, levelNames: [String] = preferenceLevelNames,
                                extra: [(Data, Data)] = []) -> Data {
    preferenceMap([
        (preferenceNumber(3), preferenceDefinition(name: tapName, labels: tapLabels, names: tapNames, scope: tapScope)),
        (preferenceNumber(5), preferenceDefinition(name: "audible_indicator_configuration", labels: indicatorLabels, names: indicatorNames)),
        (preferenceNumber(6), preferenceDefinition(name: "audible_indicators_settings", labels: levelLabels, names: levelNames))
    ] + extra)
}
private func preferenceRecord(actions: [UInt64] = [0, 7, 9, 3, 4, 11, 1, 8, 9, 5, 10, 11],
                              modes: [UInt64] = (0..<23).map { UInt64($0 % 4) }, levels: [UInt64] = [2, 0, 1],
                              extra: [(Data, Data)] = []) -> Data {
    preferenceMap([
        (preferenceNumber(3), preferenceArray(actions.map(preferenceNumber))),
        (preferenceNumber(5), preferenceArray(modes.map(preferenceNumber))),
        (preferenceNumber(6), preferenceArray(levels.map(preferenceNumber)))
    ] + extra)
}
private func preferenceInventory(global: Bool = true, situation: Bool = false, access: String = "RAM_NVRAM") -> Data {
    let names = (global ? ["global"] : []) + (situation ? ["situation"] : [])
    let scopes = names.map { name in preferenceMap([
        (preferenceText("name"), preferenceText(name)), (preferenceText("count"), preferenceNumber(1)),
        (preferenceText("access"), preferenceText(access))
    ]) }
    return preferenceMap([(preferenceText("scopes"), preferenceArray([preferenceArray(scopes)]))])
}
private func preferenceSettings(metadata: Data? = preferenceMetadata(), record: Data = preferenceRecord(),
                                inventory: Data = preferenceInventory(), scope: UInt8 = 0,
                                includeRecord: Bool = true,
                                extraRecords: [DeviceBackup.EndUserSettings.ScopeRecord] = []) throws -> DeviceBackup.EndUserSettings {
    let records = includeRecord ? [try DeviceBackup.EndUserSettings.ScopeRecord(scope: scope, id: 0, bytes: record)] : []
    return try DeviceBackup.EndUserSettings(inventory: inventory, metadata: metadata, records: records + extraRecords)
}
private func decodePreferences(_ settings: DeviceBackup.EndUserSettings) throws -> OticonSavedPreferences.Snapshot {
    try OticonSavedPreferences.decode(settings, identity: preferenceIdentity, services: [preferenceService])
}

@Test func savedPreferencesMapsSyntheticTapGesturesAndAllSixProvenContexts() throws {
    let result = try decodePreferences(preferenceSettings())
    #expect(result.taps.count == 12)
    #expect(result.taps.map(\.identifier) == preferenceTapLabels)
    #expect(result.taps.prefix(6).allSatisfy { $0.gesture == .singleTap })
    #expect(result.taps.suffix(6).allSatisfy { $0.gesture == .doubleTap })
    #expect(Array(result.taps.prefix(6).map(\.context)) == [.normal, .incomingCall, .ongoingCall, .streaming, .tinnitus, .auracastStreaming])
    #expect(result.taps.map { $0.action.rawCode } == [0, 7, 9, 3, 4, 11, 1, 8, 9, 5, 10, 11])
    #expect(result.taps[0].action.identifier == "none")
    #expect(result.taps[0].action.label == "No action")
    #expect(result.taps[1].action.identifier == "accept_call")
    #expect(result.taps[2].action.identifier == "end_call")
    #expect(result.taps[3].action.identifier == "volume_up")
    #expect(result.taps[5].action.identifier == "terminate_auracast")
    #expect(result.taps[11].action.identifier == "terminate_auracast")
}

@Test func savedPreferencesMapsIndicatorModesAndKeepsLevelCategories() throws {
    let result = try decodePreferences(preferenceSettings())
    #expect(result.audibleIndicators.count == 23)
    #expect(result.audibleIndicators.map { $0.event.rawValue } == preferenceIndicatorLabels)
    #expect(result.audibleIndicators.prefix(4).map { $0.mode.identifier } == ["disable_tonal", "enable_tonal", "disable_spoken", "enable_spoken"])
    #expect(result.audibleIndicators[0].mode.label == "Tone off")
    #expect(result.audibleIndicators[2].mode.label == "Spoken off")
    #expect(result.indicatorSettings.map(\.kind) == [.voiceLevel, .tonalLevel, .tonalFrequency])
    #expect(result.indicatorSettings.map { $0.value.identifier } == ["high", "low", "medium"])
    #expect(result.indicatorSettings.map { $0.value.rawCode } == [2, 0, 1])
}

@Test func savedPreferencesPreservesUnknownCodesWithoutDefaultsOrTruncation() throws {
    var actions = [UInt64](repeating: 0, count: 12)
    actions[0] = UInt64.max
    actions[1] = 11 // Defined only for the Auracast use case.
    let result = try decodePreferences(preferenceSettings(record: preferenceRecord(
        actions: actions, modes: [UInt64](repeating: 500, count: 23), levels: [3, 65_536, UInt64.max])))
    #expect(result.taps[0].action.rawCode == UInt64.max)
    #expect(!result.taps[0].action.isRecognized)
    #expect(result.taps[0].action.identifier == nil)
    #expect(result.taps[0].action.label == nil)
    #expect(result.taps[1].action.rawCode == 11)
    #expect(!result.taps[1].action.isRecognized)
    #expect(result.audibleIndicators.allSatisfy { $0.mode.rawCode == 500 && !$0.mode.isRecognized && $0.mode.label == nil })
    #expect(result.indicatorSettings.map { $0.value.rawCode } == [3, 65_536, UInt64.max])
    #expect(result.indicatorSettings.allSatisfy { !$0.value.isRecognized && $0.value.identifier == nil && $0.value.label == nil })
}

@Test func savedPreferencesRequiresExactIdentityAndAvailableAdvertisedEUS21() throws {
    let settings = try preferenceSettings()
    let badIdentity = OticonFittedConfiguration.Identity(modelUID: 8513, genericModelUID: 8460,
        hiidVersion: "4.5", releasePackageVersion: "5.0.30", runtimeMemoryMapVersion: "10.0.0")
    #expect(throws: OticonSavedPreferences.DecodeError.unsupportedIdentity) {
        try OticonSavedPreferences.decode(settings, identity: badIdentity, services: [preferenceService])
    }
    let invalidServices: [[DeviceBackup.Service]] = [[], [preferenceService, preferenceService],
        [DeviceBackup.Service(.init(id: 0x02000017, handle: 18, major: 2, minor: 0, status: 0xFF))],
        [DeviceBackup.Service(.init(id: 0x02000017, handle: 18, major: 3, minor: 1, status: 0xFF))],
        [DeviceBackup.Service(.init(id: 0x02000017, handle: 18, major: 2, minor: 1, status: 0))],
        [DeviceBackup.Service(.init(id: 0x02000018, handle: 18, major: 2, minor: 1, status: 0xFF))]
    ]
    for services in invalidServices {
        #expect(throws: OticonSavedPreferences.DecodeError.unsupportedService) {
            try OticonSavedPreferences.decode(settings, identity: preferenceIdentity, services: services)
        }
    }
}

@Test func savedPreferencesRequiresInventoryDeclaredGlobalZeroAndMetadata() throws {
    #expect(throws: OticonSavedPreferences.DecodeError.missingGlobalRecord) {
        try decodePreferences(preferenceSettings(includeRecord: false))
    }
    #expect(throws: OticonSavedPreferences.DecodeError.scopeNotInInventory) {
        try decodePreferences(preferenceSettings(inventory: preferenceInventory(global: false, situation: true), scope: 1))
    }
    #expect(throws: OticonSavedPreferences.DecodeError.scopeNotInInventory) {
        try decodePreferences(preferenceSettings(inventory: preferenceInventory(access: "RAM"), includeRecord: false))
    }
    #expect(throws: OticonSavedPreferences.DecodeError.missingMetadata) {
        try decodePreferences(preferenceSettings(metadata: nil))
    }
}

@Test func savedPreferencesRefusesMetadataScopeNameOrderAndEnumDisagreement() throws {
    var swappedLabels = preferenceTapLabels
    swappedLabels.swapAt(0, 1)
    var remappedNames = preferenceTapNames
    remappedNames.swapAt(0, 5)
    for metadata in [preferenceMetadata(tapScope: "situation"), preferenceMetadata(tapName: "tap_config"),
                     preferenceMetadata(tapLabels: swappedLabels), preferenceMetadata(tapLabels: Array(preferenceTapLabels.dropLast())),
                     preferenceMetadata(tapNames: remappedNames), preferenceMetadata(tapNames: preferenceTapNames + ["future_action"])] {
        #expect(throws: OticonSavedPreferences.DecodeError.metadataMismatch(field: 3)) {
            try decodePreferences(preferenceSettings(metadata: metadata))
        }
    }
    #expect(throws: OticonSavedPreferences.DecodeError.metadataMismatch(field: 5)) {
        try decodePreferences(preferenceSettings(metadata: preferenceMetadata(indicatorLabels: Array(preferenceIndicatorLabels.reversed()))))
    }
    #expect(throws: OticonSavedPreferences.DecodeError.metadataMismatch(field: 5)) {
        try decodePreferences(preferenceSettings(metadata: preferenceMetadata(indicatorNames: Array(preferenceModeNames.reversed()))))
    }
    #expect(throws: OticonSavedPreferences.DecodeError.metadataMismatch(field: 6)) {
        try decodePreferences(preferenceSettings(metadata: preferenceMetadata(levelLabels: ["tonal_freq", "voice_level", "tonal_level"])))
    }
    #expect(throws: OticonSavedPreferences.DecodeError.metadataMismatch(field: 6)) {
        try decodePreferences(preferenceSettings(metadata: preferenceMetadata(levelNames: ["high", "medium", "low"])))
    }
}

@Test func savedPreferencesRefusesShortLongMissingAndNonUnsignedVectors() throws {
    for actions in [[UInt64](repeating: 0, count: 11), [UInt64](repeating: 0, count: 13)] {
        #expect(throws: OticonSavedPreferences.DecodeError.invalidVector(field: 3)) {
            try decodePreferences(preferenceSettings(record: preferenceRecord(actions: actions)))
        }
    }
    #expect(throws: OticonSavedPreferences.DecodeError.invalidVector(field: 5)) {
        try decodePreferences(preferenceSettings(record: preferenceRecord(modes: [])))
    }
    #expect(throws: OticonSavedPreferences.DecodeError.invalidVector(field: 6)) {
        try decodePreferences(preferenceSettings(record: preferenceRecord(levels: [0, 1])))
    }
    #expect(throws: OticonSavedPreferences.DecodeError.invalidVector(field: 3)) {
        try decodePreferences(preferenceSettings(record: preferenceMap([])))
    }
    for bad in [preferenceText("0"), Data([0x20]), Data([0xF6])] {
        let record = preferenceMap([(preferenceNumber(3), preferenceArray([bad] + [Data](repeating: preferenceNumber(0), count: 11)))])
        #expect(throws: OticonSavedPreferences.DecodeError.invalidVector(field: 3)) {
            try decodePreferences(preferenceSettings(record: record))
        }
    }
}

@Test func savedPreferencesRejectsDuplicateMetadataAndRecordKeys() throws {
    let repeatedDefinition = preferenceDefinition(name: "tap_mapping", labels: preferenceTapLabels, names: preferenceTapNames)
    #expect(throws: OticonSavedPreferences.DecodeError.duplicateKey) {
        try decodePreferences(preferenceSettings(metadata: preferenceMetadata(extra: [(preferenceNumber(3), repeatedDefinition)])))
    }
    let badDefinition = preferenceDefinition(name: "tap_mapping", labels: preferenceTapLabels, names: preferenceTapNames,
                                           extra: [(preferenceText("scope"), preferenceText("global"))])
    #expect(throws: OticonSavedPreferences.DecodeError.duplicateKey) {
        try decodePreferences(preferenceSettings(metadata: preferenceMap([(preferenceNumber(3), badDefinition)])))
    }
    #expect(throws: OticonSavedPreferences.DecodeError.duplicateKey) {
        try decodePreferences(preferenceSettings(record: preferenceRecord(extra: [(preferenceNumber(3), preferenceArray([]))])))
    }
    #expect(throws: OticonSavedPreferences.DecodeError.malformedMap) {
        try decodePreferences(preferenceSettings(record: preferenceMap([(preferenceText("3"), preferenceArray([]))])))
    }
}

@Test func savedPreferencesRequiresUnsignedCBORMetadataEnumKeysAndRejectsDuplicates() throws {
    // Enum keys are native CBOR integers, even when a JSON export displays
    // object keys as decimal strings. All preference values remain synthetic.
    let valid = try decodePreferences(preferenceSettings())
    #expect(valid.taps[1].action.identifier == "accept_call")
    #expect(valid.audibleIndicators[1].mode.identifier == "enable_tonal")
    #expect(valid.indicatorSettings[0].value.identifier == "high")
    let textKeys = preferenceMap(preferenceTapNames.enumerated().map {
        (preferenceText(String($0.offset)), preferenceText($0.element))
    })
    let duplicateNumeric = preferenceMap([(preferenceNumber(0), preferenceText("none")),
                                         (preferenceNumber(0), preferenceText("mute"))])
    for (enumeration, expectedError) in [(textKeys, OticonSavedPreferences.DecodeError.malformedMap),
                                          (duplicateNumeric, .duplicateKey)] {
        let definition = preferenceDefinition(name: "tap_mapping", labels: preferenceTapLabels,
                                             names: preferenceTapNames, enumeration: enumeration)
        #expect(throws: expectedError) {
            try decodePreferences(preferenceSettings(metadata: preferenceMap([(preferenceNumber(3), definition)])))
        }
    }
}

@Test func savedPreferencesNeverReinterpretsDefaultProfileOrSituationRecords() throws {
    let profileMetadata = preferenceMap([(preferenceText("name"), preferenceText("default_profile")),
                                         (preferenceText("scope"), preferenceText("global"))])
    let situation = try DeviceBackup.EndUserSettings.ScopeRecord(scope: 1, id: 0, bytes: preferenceMap([
        (preferenceNumber(11), preferenceNumber(9)),
        (preferenceNumber(3), preferenceArray([preferenceNumber(255)]))
    ]))
    let settings = try preferenceSettings(
        metadata: preferenceMetadata(extra: [(preferenceNumber(11), profileMetadata)]),
        record: preferenceRecord(extra: [(preferenceNumber(11), preferenceText("opaque synthetic field"))]),
        inventory: preferenceInventory(situation: true), extraRecords: [situation])
    let result = try decodePreferences(settings)
    let expected = try decodePreferences(preferenceSettings())
    #expect(result == expected)
    #expect(settings.records.count == 2)
    #expect(settings.records[1] == situation)
}
