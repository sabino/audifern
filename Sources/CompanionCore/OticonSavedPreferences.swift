import Foundation

/// Reads three saved global EUS preference vectors for the researched profile.
/// All inputs must belong to the same validated private device backup.
public enum OticonSavedPreferences {
    public enum DecodeError: Error, Equatable {
        case unsupportedIdentity, unsupportedService, missingMetadata
        case missingGlobalRecord, scopeNotInInventory, malformedMap, duplicateKey
        case metadataMismatch(field: UInt64), invalidVector(field: UInt64)
    }

    public static let limits = "These are saved preferences for one aid. Feature availability and current activity require additional information. Situation and profile settings are not interpreted."

    public struct Choice: Equatable, Sendable {
        public let rawCode: UInt64
        /// Unknown stored codes retain their number with no invented meaning.
        public let identifier: String?
        public let label: String?
        public var isRecognized: Bool { identifier != nil }
    }

    public enum Gesture: String, CaseIterable, Equatable, Sendable {
        case singleTap = "single_tap", doubleTap = "double_tap"
        public var label: String { self == .singleTap ? "Single tap" : "Double tap" }
    }

    public enum UseCase: Int, CaseIterable, Equatable, Sendable {
        case normal = 1, incomingCall, ongoingCall, streaming, tinnitus, auracastStreaming
        public var label: String {
            switch self {
            case .normal: "Normal listening"
            case .incomingCall: "Incoming call"
            case .ongoingCall: "Ongoing call"
            case .streaming: "Streaming"
            case .tinnitus: "Tinnitus"
            case .auracastStreaming: "Auracast streaming"
            }
        }
    }

    public struct Tap: Equatable, Sendable {
        public let gesture: Gesture
        public let context: UseCase
        public let action: Choice
        public var identifier: String { "\(gesture.rawValue)_LCUC\(context.rawValue)" }
    }

    public enum IndicatorEvent: String, CaseIterable, Equatable, Sendable {
        case startup = "aud_startup", shutdown = "aud_shutdown", programChange = "aud_program"
        case waxFilter = "aud_wax_filter", serviceMode = "aud_service_mode", flightMode = "aud_flight_mode"
        case batteryFinalWarning = "aud_batt_final", batteryLowWarning = "aud_batt_low"
        case batteryStartupPackage = "aud_batt_warn_pack", battery30Percent = "aud_batt_30_pct"
        case battery20Percent = "aud_batt_20_pct", volumeDefault = "aud_vc_default"
        case volumeLimit = "aud_vc_limit", volumeChange = "aud_vc_change", mute = "aud_mute"
        case incomingMobileCall = "aud_mobile", incomingLandlineCall = "aud_landline"
        case incomingVoIPCall = "aud_btd800", tinnitusVolumeDefault = "aud_tsg_vc_default"
        case tinnitusVolumeLimit = "aud_tsg_vc_limit", tinnitusVolumeChange = "aud_tsg_vc_change"
        case acceptCall = "aud_accept_call", rejectOrEndCall = "aud_reject_end_call"

        public var label: String {
            switch self {
            case .startup: "Startup"
            case .shutdown: "Shutdown"
            case .programChange: "Program change"
            case .waxFilter: "Wax filter"
            case .serviceMode: "Service mode"
            case .flightMode: "Flight mode"
            case .batteryFinalWarning: "Final battery warning"
            case .batteryLowWarning: "Low battery warning"
            case .batteryStartupPackage: "Battery startup notification"
            case .battery30Percent: "Battery at 30%"
            case .battery20Percent: "Battery at 20%"
            case .volumeDefault: "Default volume"
            case .volumeLimit: "Volume limit"
            case .volumeChange: "Volume change"
            case .mute: "Mute"
            case .incomingMobileCall: "Incoming mobile call"
            case .incomingLandlineCall: "Incoming landline call"
            case .incomingVoIPCall: "Incoming VoIP call"
            case .tinnitusVolumeDefault: "Default tinnitus volume"
            case .tinnitusVolumeLimit: "Tinnitus volume limit"
            case .tinnitusVolumeChange: "Tinnitus volume change"
            case .acceptCall: "Accept call"
            case .rejectOrEndCall: "Reject or end call"
            }
        }
    }

    public struct AudibleIndicator: Equatable, Sendable {
        public let event: IndicatorEvent
        public let mode: Choice
    }

    public enum IndicatorSettingKind: String, CaseIterable, Equatable, Sendable {
        case voiceLevel = "voice_level", tonalLevel = "tonal_level", tonalFrequency = "tonal_freq"
        public var label: String {
            switch self {
            case .voiceLevel: "Spoken notification level"
            case .tonalLevel: "Tone level"
            case .tonalFrequency: "Tone frequency"
            }
        }
    }

    public struct IndicatorSetting: Equatable, Sendable {
        public let kind: IndicatorSettingKind
        /// Low/medium/high are categories; no dB level or frequency is inferred.
        public let value: Choice
    }

    public struct Snapshot: Equatable, Sendable {
        /// Exact vector order: six single-tap contexts, then six double-tap contexts.
        public let taps: [Tap]
        public let audibleIndicators: [AudibleIndicator]
        public let indicatorSettings: [IndicatorSetting]
    }

    /// Requires EUS 2.1, matching metadata and an inventory-declared global 0/0
    /// record. Missing entries are errors; no default actions are substituted.
    /// Other stored fields and scopes remain preserved in the original archive.
    public static func decode(_ settings: DeviceBackup.EndUserSettings,
                              identity: OticonFittedConfiguration.Identity,
                              services: [DeviceBackup.Service]) throws -> Snapshot {
        guard identity.isSupported else { throw DecodeError.unsupportedIdentity }
        let advertised = services.filter { $0.id == OticonEndUserSettings.serviceID }
        guard advertised.count == 1, let service = advertised.first, service.available,
              service.major == 2, service.minor == 1 else { throw DecodeError.unsupportedService }
        let inventory = try OticonEndUserSettings.decodeInventory(settings.inventory)
        guard inventory.reads.contains(where: { $0.scope == 0 && $0.id == 0 && $0.scopeName == "global" }) else {
            throw DecodeError.scopeNotInInventory
        }
        let records = settings.records.filter { $0.scope == 0 && $0.id == 0 }
        guard records.count == 1, let record = records.first else { throw DecodeError.missingGlobalRecord }
        guard let metadata = settings.metadata else { throw DecodeError.missingMetadata }
        let definitions = try unsignedMap(OticonEndUserSettings.decodeValue(metadata))
        let values = try unsignedMap(OticonEndUserSettings.decodeValue(record.bytes))

        let contexts = UseCase.allCases
        let gestures = Gesture.allCases
        let tapLabels = gestures.flatMap { gesture in contexts.map { "\(gesture.rawValue)_LCUC\($0.rawValue)" } }
        try validate(definitions[3], field: 3, name: "tap_mapping", labels: tapLabels, enumeration: tapNames)
        try validate(definitions[5], field: 5, name: "audible_indicator_configuration",
                     labels: IndicatorEvent.allCases.map(\.rawValue), enumeration: modeNames)
        try validate(definitions[6], field: 6, name: "audible_indicators_settings",
                     labels: IndicatorSettingKind.allCases.map(\.rawValue), enumeration: levelNames)

        let actions = try vector(values[3], field: 3, count: tapLabels.count)
        let modes = try vector(values[5], field: 5, count: IndicatorEvent.allCases.count)
        let levels = try vector(values[6], field: 6, count: IndicatorSettingKind.allCases.count)
        var taps: [Tap] = []
        for gesture in gestures {
            for context in contexts {
                let code = actions[taps.count]
                // The transformer only assigns terminate_auracast to LCUC6.
                let recognized = code != 11 || context == .auracastStreaming
                taps.append(Tap(gesture: gesture, context: context,
                                action: choice(code, names: recognized ? tapNames : [:], labels: tapLabelsByCode)))
            }
        }
        return Snapshot(taps: taps,
                        audibleIndicators: zip(IndicatorEvent.allCases, modes).map {
                            AudibleIndicator(event: $0.0, mode: choice($0.1, names: modeNames, labels: modeLabels))
                        },
                        indicatorSettings: zip(IndicatorSettingKind.allCases, levels).map {
                            IndicatorSetting(kind: $0.0, value: choice($0.1, names: levelNames, labels: levelLabels))
                        })
    }

    private typealias Value = OticonEndUserSettings.Value

    private static func unsignedMap(_ value: Value) throws -> [UInt64: Value] {
        guard case .map(let pairs) = value else { throw DecodeError.malformedMap }
        var result: [UInt64: Value] = [:]
        for (key, value) in pairs {
            guard case .unsigned(let number) = key else { throw DecodeError.malformedMap }
            guard case .none = result[number] else { throw DecodeError.duplicateKey }
            result[number] = value
        }
        return result
    }

    private static func textMap(_ value: Value) throws -> [String: Value] {
        guard case .map(let pairs) = value else { throw DecodeError.malformedMap }
        var result: [String: Value] = [:]
        for (key, value) in pairs {
            guard case .text(let name) = key else { throw DecodeError.malformedMap }
            guard case .none = result[name] else { throw DecodeError.duplicateKey }
            result[name] = value
        }
        return result
    }

    private static func validate(_ value: Value?, field: UInt64, name: String,
                                 labels: [String], enumeration: [UInt64: String]) throws {
        guard let value else { throw DecodeError.metadataMismatch(field: field) }
        let map = try textMap(value)
        guard case .text(let actualName)? = map["name"], actualName == name,
              case .text("global")? = map["scope"],
              case .array(let rawLabels)? = map["labels"], rawLabels.count == labels.count,
              let rawEnumeration = map["emap"] else { throw DecodeError.metadataMismatch(field: field) }
        for (raw, expected) in zip(rawLabels, labels) {
            guard case .text(let actual) = raw, actual == expected else { throw DecodeError.metadataMismatch(field: field) }
        }
        // The matching metadata uses unsigned CBOR keys in emap. JSON exports
        // can render those keys as strings; they are not text on the wire.
        let names = try unsignedMap(rawEnumeration)
        guard names.count == enumeration.count else { throw DecodeError.metadataMismatch(field: field) }
        for (code, expected) in enumeration {
            guard case .text(let actual)? = names[code], actual == expected else {
                throw DecodeError.metadataMismatch(field: field)
            }
        }
    }

    private static func vector(_ value: Value?, field: UInt64, count: Int) throws -> [UInt64] {
        guard case .array(let values)? = value, values.count == count else { throw DecodeError.invalidVector(field: field) }
        return try values.map {
            guard case .unsigned(let code) = $0 else { throw DecodeError.invalidVector(field: field) }
            return code
        }
    }

    private static func choice(_ code: UInt64, names: [UInt64: String], labels: [UInt64: String]) -> Choice {
        let name = names[code]
        return Choice(rawCode: code, identifier: name, label: name == nil ? nil : labels[code])
    }

    private static let tapNames: [UInt64: String] = [
        0: "none", 1: "program_up", 2: "program_down", 3: "volume_up", 4: "volume_down", 5: "mute",
        6: "flight_mode", 7: "accept_call", 8: "reject_call", 9: "end_call", 10: "shutdown", 11: "terminate_auracast"
    ]
    private static let tapLabelsByCode: [UInt64: String] = [
        0: "No action", 1: "Next program", 2: "Previous program", 3: "Volume up", 4: "Volume down", 5: "Mute",
        6: "Flight mode", 7: "Accept call", 8: "Reject call", 9: "End call", 10: "Shut down", 11: "End Auracast stream"
    ]
    private static let modeNames: [UInt64: String] = [
        0: "disable_tonal", 1: "enable_tonal", 2: "disable_spoken", 3: "enable_spoken"
    ]
    private static let modeLabels: [UInt64: String] = [0: "Tone off", 1: "Tone on", 2: "Spoken off", 3: "Spoken on"]
    private static let levelNames: [UInt64: String] = [0: "low", 1: "medium", 2: "high"]
    private static let levelLabels: [UInt64: String] = [0: "Low", 1: "Medium", 2: "High"]
}
