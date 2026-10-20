@testable import CompanionCore
import Foundation
import Testing
@testable import Audifern

private func syntheticRevisionMetadata() throws -> OticonIdentification.Metadata {
    let text = Data("HIID-SW".utf8) + Data(repeating: 0, count: 11)
    return try OticonIdentification.decodeHiid(Data([0xA2, 0x19, 3, 0xE9, 0x42, 4, 6,
                                                     0x19, 7, 0xE3, 0x52]) + text).metadata
}

@Test func deviceRevisionStateKeepsFirmwareSoftwareAndHardwareSeparate() {
    var aid = AidConnection(id: UUID(), name: "Synthetic aid", phase: .connected)
    let firmwareRead = aid.receiveRevision(service: "180A", characteristic: "2A26", data: Data("FW-7".utf8))
    #expect(firmwareRead)
    #expect(aid.softwareRevision == nil && aid.hardwareRevision == nil)
    let softwareRead = aid.receiveRevision(service: "180A", characteristic: "2A28", data: Data("SW-2".utf8))
    let hardwareRead = aid.receiveRevision(service: "180A", characteristic: "2A27", data: Data("HW-1".utf8))
    #expect(softwareRead && hardwareRead)
    #expect(aid.firmware == "FW-7" && aid.softwareRevision == "SW-2" && aid.hardwareRevision == "HW-1")
    let wrongService = aid.receiveRevision(service: "180F", characteristic: "2A28", data: Data("Wrong service".utf8))
    #expect(!wrongService)
    #expect(aid.softwareRevision == "SW-2")
    let malformedRead = aid.receiveRevision(service: "180A", characteristic: "2A28", data: Data([0xFF]))
    #expect(malformedRead)
    #expect(aid.softwareRevision == nil && aid.firmware == "FW-7" && aid.hardwareRevision == "HW-1")
}

@Test func deviceMetadataFallbackHasExplicitSourceAndStaysWithItsAid() throws {
    var left = AidConnection(id: UUID(), name: "Synthetic left", phase: .connected)
    let right = AidConnection(id: UUID(), name: "Synthetic right", phase: .connected)
    left.deviceMetadata = try syntheticRevisionMetadata()
    #expect(left.softwareRevision == "HIID-SW" && left.softwareRevisionSource == "HIID (2019)")
    #expect(left.firmware == nil && right.softwareRevision == nil && right.deviceMetadata == nil)
    _ = left.receiveRevision(service: "180A", characteristic: "2A28", data: Data("DIS-SW".utf8))
    #expect(left.softwareRevision == "DIS-SW" && left.softwareRevisionSource == "Device Information (2A28)")
}

@Test func disconnectClearsDeviceMetadataHealthAndCurrentServiceRegistry() throws {
    var aid = AidConnection(id: UUID(), name: "Synthetic aid", phase: .connected)
    aid.deviceMetadata = try syntheticRevisionMetadata()
    aid.standardHardwareRevision = "HW"
    aid.deviceMetadataStatus = "Read"
    aid.advancedServices = [.init(id: OticonIdentification.serviceID, handle: 11, major: 1, minor: 2, status: 255)]
    aid.batteryHealth = .init(lifespan: 90, lifespanThreshold: 60, slowAverageCurrentDraw: 1_000, fullChargeCapacity: 20_000)
    aid.coreDumpInfo = try OticonDiagnostics.coreDumpInfo(Data([0, 1, 0, 0]),
        service: .init(id: OticonDiagnostics.coreDumpServiceID, handle: 12, major: 1, minor: 0, status: 255))
    aid.clearLiveValues()
    #expect(aid.deviceMetadata == nil && aid.deviceMetadataStatus == nil)
    #expect(aid.softwareRevision == nil && aid.hardwareRevision == nil && aid.softwareRevisionSource == nil)
    #expect(aid.batteryHealth == nil && aid.coreDumpInfo == nil && aid.advancedServices.isEmpty)
}

@Test func advertisedRevisionDistinguishesPresentUnreadFromAbsent() {
    var aid = AidConnection(id: UUID(), name: "Synthetic aid", phase: .connected)
    aid.services = [.init(id: "dis", uuid: "180A", isPrimary: true, characteristics: [
        .init(id: "software", uuid: "2A28", properties: "read", value: nil, isNotifying: false)])]
    #expect(aid.advertisesDeviceInformationCharacteristic("2A28") && aid.softwareRevision == nil)
    #expect(!aid.advertisesDeviceInformationCharacteristic("2A27"))
    aid.services[0] = .init(id: "other", uuid: "180F", isPrimary: true, characteristics: aid.services[0].characteristics)
    #expect(!aid.advertisesDeviceInformationCharacteristic("2A28"))
}
