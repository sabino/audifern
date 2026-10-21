import Foundation

/// Select the researched decoder from identity captured with the same raw
/// record. The model UIDs are an interoperability lookup for the exact reported
/// product, never an identity inferred from the user's planning selection.
public enum SavedFitting {
    public enum ReadError: Error { case unavailable, unsupportedIdentity }
    public static func supports(_ identity: DeviceBackup.Identity) -> Bool {
        guard identity.model.map(DeviceBackup.Identity.modelKey) == "intent3",
              let hiid = identity.hiidVersion, let release = identity.releasePackageVersion,
              let map = identity.runtimeMemoryMapVersion else { return false }
        return OticonFittedConfiguration.Identity(modelUID: 8513, genericModelUID: 8460,
            hiidVersion: hiid, releasePackageVersion: release, runtimeMemoryMapVersion: map).isSupported
    }

    /// New archives retain authoritative raw identity. Require it to agree
    /// with the selected format, including numeric model UIDs. Older archives
    /// without that optional payload keep their original identity gate.
    public static func supports(_ aid: DeviceBackup.Aid) -> Bool {
        guard supports(aid.identity) else { return false }
        guard let raw = aid.identification else { return true }
        guard let identity = try? OticonIdentification.decodeHiid(raw),
              let hardware = try? OticonHardwareProfile.decodeHiid(raw),
              identity.metadata.hiidVersion == aid.identity.hiidVersion,
              identity.metadata.releasePackageVersion == aid.identity.releasePackageVersion,
              identity.metadata.runtimeMemoryMapVersion == aid.identity.runtimeMemoryMapVersion,
              identity.metadata.model.map(DeviceBackup.Identity.modelKey) == "intent3",
              hardware.product.modelUID == 8513, hardware.product.genericModelUID == 8460 else { return false }
        return true
    }
    public static func decode(_ aid: DeviceBackup.Aid) throws -> OticonFittedConfiguration.Snapshot {
        let (blob, identity) = try supportedBlob(aid)
        return try OticonFittedConfiguration.decode(blob: blob, identity: identity)
    }

    public static func businessData(_ aid: DeviceBackup.Aid) throws -> OticonBusinessData.Snapshot {
        let (blob, _) = try supportedBlob(aid)
        return try OticonBusinessData.decode(blob.businessData)
    }

    private static func supportedBlob(_ aid: DeviceBackup.Aid) throws
        -> (OticonFittingRead.Blob, OticonFittedConfiguration.Identity) {
        guard supports(aid),
              let hiid = aid.identity.hiidVersion, let release = aid.identity.releasePackageVersion,
              let map = aid.identity.runtimeMemoryMapVersion else { throw ReadError.unsupportedIdentity }
        let identity = OticonFittedConfiguration.Identity(modelUID: 8513, genericModelUID: 8460,
            hiidVersion: hiid, releasePackageVersion: release, runtimeMemoryMapVersion: map)
        guard identity.isSupported else { throw ReadError.unsupportedIdentity }
        guard let record = aid.records.first(where: { $0.key == OticonFittingRead.recordKey }),
              record.bytes.count >= OticonFittingRead.headerSize else { throw ReadError.unavailable }
        let header = try OticonFittingRead.Header(data: Data(record.bytes.prefix(OticonFittingRead.headerSize)))
        let blob = try OticonFittingRead.decodeBlob(Data(record.bytes.dropFirst(OticonFittingRead.headerSize)),
            header: header, hiidVersion: hiid)
        return (blob, identity)
    }
}
