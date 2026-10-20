import CompanionCore
import Foundation

/// A narrow inspection allowlist. Vendor entries come from the installed Companion SDK's remote-control mapping.
enum ReadOnlyInspection {
    static let vendorCharacteristicNames: [String: String] = [
        "D28617FE-0AD5-40C5-A04A-BC89051FF755": "Ear",
        "1454E9D6-F658-4190-8589-22AA9E3021EB": "Main volume",
        "58BBCCC5-5A57-4E00-98D5-18C6A0408DFD": "Volume ranges",
        "535442F7-0FF7-4FEC-9780-742F3EB00EDA": "Active program",
        "DCBE7A3E-A742-4527-AEB5-CD8DEE63167F": "Available programs"
    ]

    static func name(service: String, characteristic: String) -> String? {
        let service = HearingAidDiscovery.normalizedUUID(service)
        let characteristic = HearingAidDiscovery.normalizedUUID(characteristic)
        if service == StandardGATT.deviceInformationService { return StandardGATT.deviceInformationNames[characteristic] }
        if service == StandardGATT.batteryService, characteristic == StandardGATT.batteryLevel { return "Battery level" }
        if service == HearingAidDiscovery.legacyRemoteService { return vendorCharacteristicNames[characteristic] }
        if service == "1844", characteristic == "2B7D" { return "Volume state" }
        if service == "1844", characteristic == "2B7F" { return "Volume flags" }
        if service == "1854", characteristic == "2BDA" { return "Hearing aid features" }
        if service == "1854", characteristic == "2BDC" { return "Active preset" }
        if service == "1850", characteristic == "2BCA" { return "Sink audio locations" }
        if service == HearingAidDiscovery.universalTransportService, characteristic == "E6C02A45-A0E5-41F2-9CD1-C1FAB9EC0C3E" { return "Transport information" }
        return nil
    }

    static func displayValue(service: String, characteristic: String, data: Data) -> String {
        if StandardGATT.isPermittedRead(service: service, characteristic: characteristic) {
            return StandardGATT.displayValue(service: service, characteristic: characteristic, data: data)
        }
        let service = HearingAidDiscovery.normalizedUUID(service)
        let characteristic = HearingAidDiscovery.normalizedUUID(characteristic)
        if service == OticonRemoteProtocol.service {
            switch characteristic {
            case OticonRemoteProtocol.mainVolume:
                if let volume = OticonRemoteProtocol.Volume(data: data) { return "Level \(volume.level) · \(volume.muted ? "muted" : "unmuted")" }
            case OticonRemoteProtocol.volumeRanges:
                if let ranges = OticonRemoteProtocol.VolumeRanges(data: data) { return "Microphone \(ranges.main.lowerBound)…\(ranges.main.upperBound) · Streaming \(ranges.streaming.lowerBound)…\(ranges.streaming.upperBound) · Tinnitus \(ranges.tinnitus.lowerBound)…\(ranges.tinnitus.upperBound)" }
            case OticonRemoteProtocol.availablePrograms:
                if let programs = OticonRemoteProtocol.programIDs(bitmap: data) { return "Program IDs: \(programs.map(String.init).joined(separator: ", "))" }
            case OticonRemoteProtocol.activeProgram:
                if data.count == 1, let program = data.first { return "Program \(program)" }
            case OticonRemoteProtocol.ear:
                if data.count == 1, let ear = data.first { return "Side \(ear) (raw SDK value)" }
            default: break
            }
        }
        if service == "1844", characteristic == "2B7D", let state = BluetoothVolumeState(data: data) {
            return "Streaming volume \(state.volume)/255 · \(state.muted ? "muted" : "unmuted") · Counter \(state.changeCounter)"
        }
        if service == "1850", characteristic == "2BCA", data.count == 4 {
            let bits = data.enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << (8 * $1.offset)) }
            if bits == 1 { return "Front left (0x00000001)" }
            if bits == 2 { return "Front right (0x00000002)" }
        }
        return "Hex: \(data.hexString)"
    }

    static func shouldNotify(service: String, characteristic: String) -> Bool {
        let service = HearingAidDiscovery.normalizedUUID(service)
        let characteristic = HearingAidDiscovery.normalizedUUID(characteristic)
        if service == StandardGATT.batteryService, characteristic == StandardGATT.batteryLevel { return true }
        if service == OticonRemoteProtocol.service {
            return [OticonRemoteProtocol.mainVolume, OticonRemoteProtocol.activeProgram, OticonRemoteProtocol.volumeRanges].contains(characteristic)
        }
        return (service == "1844" && characteristic == "2B7D") || (service == "1854" && characteristic == "2BDC")
    }
}
