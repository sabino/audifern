import Foundation
import Testing
@testable import CompanionCore

private func hiidMap(major: UInt8 = 4, minor: UInt8 = 6, entries: [(UInt16, Data)]) -> Data {
    var data = Data([0xA1 + UInt8(entries.count), 0x19, 0x03, 0xE9, 0x42, major, minor])
    for (key, value) in entries {
        data += Data([0x19, UInt8(key >> 8), UInt8(truncatingIfNeeded: key)])
        data += value.count < 24 ? Data([0x40 + UInt8(value.count)]) : Data([0x58, UInt8(value.count)])
        data += value
    }
    return data
}

private func disSlot(_ text: String) -> Data {
    let bytes = Data(text.utf8)
    return bytes + Data(repeating: 0, count: 18 - bytes.count)
}

@Test func hiidMetadataKeepsSoftwareFirmwareHardwareAndComponentVersionsDistinct() throws {
    let payload = hiidMap(entries: [
        (2009, disSlot("Synthetic maker") + disSlot("Aid model") + disSlot("HW-3") + Data([1])),
        (2007, disSlot("FW-7.1.0")), (2019, disSlot("SW-2.8.4")),
        (1012, Data([1, 2, 3, 4, 5, 6])), (2020, Data([7, 8, 9, 10, 11, 12]))
    ])
    let metadata = try OticonIdentification.decodeHiid(payload).metadata
    #expect(metadata.hiidVersion == "4.6")
    #expect(metadata.manufacturer == "Synthetic maker" && metadata.model == "Aid model")
    #expect(metadata.hardwareRevision == "HW-3")
    #expect(metadata.firmwareRevision == "FW-7.1.0")
    #expect(metadata.softwareRevision == "SW-2.8.4")
    #expect(metadata.runtimeMemoryMapVersion == "1.2.3")
    #expect(metadata.releasePackageVersion == "4.5.6")
    #expect(metadata.primaryAppVersion == "7.8.9")
    #expect(metadata.maintenanceAppVersion == "10.11.12")
    #expect(metadata.invalidFields.isEmpty)
}

@Test func hiidMetadataUsesVersionSpecificPlatformOffsets() throws {
    for (major, minor) in [(UInt8(3), UInt8(4)), (3, 5), (3, 7), (4, 3), (4, 5), (4, 6)] {
        let platform = (major == 3 ? Data([91, 92, 93]) : Data()) + Data([1, 2, 3, 4, 5, 6])
        let metadata = try OticonIdentification.decodeHiid(hiidMap(major: major, minor: minor,
            entries: [(1012, platform), (2007, disSlot("Firmware")), (2019, disSlot("Software"))])).metadata
        #expect(metadata.runtimeMemoryMapVersion == "1.2.3")
        #expect(metadata.releasePackageVersion == "4.5.6")
        #expect(metadata.firmwareRevision == "Firmware")
        #expect(metadata.softwareRevision == "Software")
    }
}

@Test func hiidMetadataAllowsMissingFieldsAndReportsOnlyMalformedFieldLabels() throws {
    let empty = try OticonIdentification.decodeHiid(hiidMap(entries: [])).metadata
    #expect(empty.softwareRevision == nil && empty.firmwareRevision == nil)
    #expect(empty.invalidFields.isEmpty)
    let partial = try OticonIdentification.decodeHiid(hiidMap(entries: [
        (2019, Data([1, 2])), (2020, Data([1, 2, 3])), (2007, disSlot("Firmware"))])).metadata
    #expect(partial.softwareRevision == nil && partial.firmwareRevision == "Firmware")
    #expect(partial.primaryAppVersion == "1.2.3" && partial.maintenanceAppVersion == nil)
    #expect(Set(partial.invalidFields) == ["Software revision", "Maintenance application version"])
}

@Test func hiidMetadataStopsAtNULAndRejectsInvalidOrControlText() throws {
    let terminated = Data("Software\0".utf8) + Data(repeating: 0xFF, count: 9)
    let metadata = try OticonIdentification.decodeHiid(hiidMap(entries: [
        (2019, terminated), (2007, Data([0xFF]) + Data(repeating: 0, count: 17)),
        (2009, disSlot("Maker") + disSlot("Model") + disSlot("a\u{01}b"))
    ])).metadata
    #expect(metadata.softwareRevision == "Software")
    #expect(metadata.firmwareRevision == nil && metadata.hardwareRevision == nil)
    #expect(Set(metadata.invalidFields) == ["Firmware revision", "Hardware revision"])
}

@Test func revisionIdentifiersStayBoundToDeviceInformationAndNeverAlias() {
    #expect(StandardGATT.revisionField(service: "180A", characteristic: "2A26") == .firmware)
    #expect(StandardGATT.revisionField(service: "180A", characteristic: "2A27") == .hardware)
    #expect(StandardGATT.revisionField(service: "0000180A-0000-1000-8000-00805F9B34FB",
                                       characteristic: "00002A28-0000-1000-8000-00805F9B34FB") == .software)
    #expect(StandardGATT.revisionField(service: "180F", characteristic: "2A28") == nil)
    #expect(StandardGATT.revisionField(service: "180A", characteristic: "2A25") == nil)
}

@Test func crashDumpInfoDecodesOnlyCountersForTheKnownConsumerService() throws {
    let service = UTLProtocol.Service(id: OticonDiagnostics.coreDumpServiceID, handle: 12, major: 1, minor: 0, status: 255)
    let info = try OticonDiagnostics.coreDumpInfo(Data([0x12, 0x34, 0, 2]), service: service)
    #expect(info.lastDumpCounter == 0x1234 && info.storedCrashDumps == 2)
    for payload in [Data(), Data([1, 2, 3]), Data([1, 2, 3, 4, 5])] {
        #expect(throws: OticonDiagnostics.DecodeError.malformed) { try OticonDiagnostics.coreDumpInfo(payload, service: service) }
    }
    for other in [UTLProtocol.Service(id: 0, handle: 12, major: 1, minor: 0, status: 255),
                  .init(id: service.id, handle: 12, major: 1, minor: 1, status: 255),
                  .init(id: service.id, handle: 12, major: 1, minor: 0, status: 0)] {
        #expect(!OticonDiagnostics.supportsCoreDumpInfo(other))
        #expect(throws: OticonDiagnostics.DecodeError.unsupportedVersion) { try OticonDiagnostics.coreDumpInfo(Data([0, 0, 0, 0]), service: other) }
    }
}
