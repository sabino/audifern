import Foundation

/// Heuristics for discovery, never proof of manufacturer or protocol compatibility.
public enum HearingAidDiscovery {
    public static let legacyRemoteService = "56772EAF-2153-4F74-ACF3-4368D99FBF5A"
    public static let universalTransportService = "BA50125D-0806-42AB-8BF1-22E0B954A8FA"
    public static let connectedRetrievalServices = ["180F", "180A", "1844", "1854", "FDF0", legacyRemoteService, universalTransportService]

    public static func normalizedUUID(_ value: String) -> String {
        let upper = value.uppercased()
        let suffix = "-0000-1000-8000-00805F9B34FB"
        if upper.hasPrefix("0000"), upper.hasSuffix(suffix), upper.count == 36 {
            return String(upper.dropFirst(4).prefix(4))
        }
        return upper
    }

    public static func candidateReasons(name: String?, services: [String]) -> [String] {
        var reasons: [String] = []
        let lower = (name ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if ["oticon", "demant", "bernafon", "hearing aid", "aparelhos auditivos", "aparelho auditivo"].contains(where: lower.contains) {
            reasons.append("Hearing-device name")
        }
        let serviceSet = Set(services.map(normalizedUUID))
        if serviceSet.contains("FDF0") { reasons.append("ASHA service") }
        if serviceSet.contains("1854") { reasons.append("Hearing Access service") }
        if serviceSet.contains(legacyRemoteService) { reasons.append("Oticon remote service") }
        if serviceSet.contains(universalTransportService) { reasons.append("Oticon transport service") }
        return reasons
    }

    /// Bluetooth manufacturer-specific advertising begins with a little-endian company identifier.
    public static func manufacturerCompanyID(_ data: Data) -> UInt16? {
        guard data.count >= 2 else { return nil }
        let bytes = Array(data.prefix(2))
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }
}

public enum StandardGATT {
    public static let deviceInformationService = "180A"
    public static let batteryService = "180F"
    public static let batteryLevel = "2A19"
    public enum RevisionField: String, Sendable {
        case firmware = "2A26", hardware = "2A27", software = "2A28"
    }
    public static let deviceInformationNames: [String: String] = [
        "2A29": "Manufacturer", "2A24": "Model",
        "2A27": "Hardware revision", "2A26": "Firmware revision", "2A28": "Software revision"
    ]

    public static func isPermittedRead(service: String, characteristic: String) -> Bool {
        let service = HearingAidDiscovery.normalizedUUID(service)
        let characteristic = HearingAidDiscovery.normalizedUUID(characteristic)
        return (service == batteryService && characteristic == batteryLevel)
            || (service == deviceInformationService && deviceInformationNames[characteristic] != nil)
    }

    public static func batteryPercentage(_ data: Data) -> Int? {
        guard data.count == 1, let byte = data.first, byte <= 100 else { return nil }
        return Int(byte)
    }

    public static func revisionField(service: String, characteristic: String) -> RevisionField? {
        guard HearingAidDiscovery.normalizedUUID(service) == deviceInformationService else { return nil }
        return RevisionField(rawValue: HearingAidDiscovery.normalizedUUID(characteristic))
    }

    public static func informationString(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard !trimmed.isEmpty, !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return trimmed
    }

    public static func displayValue(service: String, characteristic: String, data: Data) -> String {
        if HearingAidDiscovery.normalizedUUID(service) == batteryService,
           HearingAidDiscovery.normalizedUUID(characteristic) == batteryLevel {
            return batteryPercentage(data).map { "\($0)%" } ?? "Invalid battery value (\(data.hexString))"
        }
        return informationString(data) ?? "Hex: \(data.hexString)"
    }
}

public extension Data {
    var hexString: String { map { String(format: "%02X", $0) }.joined() }
}
