import Foundation

/// A comparison of captured data, never a sound-quality assessment or restore
/// plan. Missing observations and different instruments cannot mean unchanged.
public struct DeviceBackupComparison: Sendable {
    public enum Difference: String, Sendable {
        case notCaptured, firstOnly, secondOnly, identical, changed
    }
    public enum IdentityMatch: Sendable { case serialNumber, localIdentifier, differentAid, missingEar }
    public enum Section: String, CaseIterable, Sendable { case acoustics, fittedParameters, fittingMetadata }
    public enum ConsumerField: String, CaseIterable, Sendable {
        case program, mainVolume, streamingVolume, tinnitusVolume, microphoneEQ, streamingEQ, speechBooster
    }
    public struct Scope: Equatable, Sendable {
        public let scope: UInt8
        public let id: UInt8
        public let difference: Difference
    }
    public struct Aid: Sendable {
        public let side: ConsumerProgramSnapshot.Side
        public let identity: IdentityMatch
        public let fittingRecord: Difference?
        /// Available only for both matching, researched fitting profiles.
        public let sections: [Section: Difference]
        public let consumer: [ConsumerField: Difference]
        public let scopeInventory: Difference?
        public let scopeMetadata: Difference?
        public let scopes: [Scope]
        public var isComparable: Bool { identity == .serialNumber || identity == .localIdentifier }
    }
    public let aids: [Aid]

    public init(first: DeviceBackup, second: DeviceBackup) throws {
        try first.validate(); try second.validate()
        aids = [ConsumerProgramSnapshot.Side.left, .right].compactMap { side in
            let a = first.aids.first { $0.side == side }, b = second.aids.first { $0.side == side }
            guard a != nil || b != nil else { return nil }
            let identity = Self.identityMatch(a?.identity, b?.identity)
            guard let a, let b, identity == .serialNumber || identity == .localIdentifier else {
                return Aid(side: side, identity: identity, fittingRecord: nil, sections: [:], consumer: [:],
                           scopeInventory: nil, scopeMetadata: nil, scopes: [])
            }
            let recordA = a.records.first { $0.key == OticonFittingRead.recordKey }
            let recordB = b.records.first { $0.key == OticonFittingRead.recordKey }
            var sections: [Section: Difference] = [:]
            if SavedFitting.supports(a), SavedFitting.supports(b),
               let blobA = try? Self.blob(recordA, identity: a.identity),
               let blobB = try? Self.blob(recordB, identity: b.identity) {
                sections = [.acoustics: Self.difference(blobA.selection, blobB.selection),
                            .fittedParameters: Self.difference(blobA.prodRegs, blobB.prodRegs),
                            .fittingMetadata: Self.difference(blobA.businessData, blobB.businessData)]
            }
            let consumerA = first.consumerControls.aids.first { $0.side == side }
            let consumerB = second.consumerControls.aids.first { $0.side == side }
            let consumer: [ConsumerField: Difference] = [
                .program: Self.difference(consumerA?.program, consumerB?.program),
                .mainVolume: Self.difference(consumerA?.volume, consumerB?.volume),
                .streamingVolume: Self.difference(consumerA?.streamingVolume, consumerB?.streamingVolume),
                .tinnitusVolume: Self.difference(consumerA?.tinnitusVolume, consumerB?.tinnitusVolume),
                .microphoneEQ: Self.difference(consumerA?.microphoneEqualizer, consumerB?.microphoneEqualizer),
                .streamingEQ: Self.difference(consumerA?.streamingEqualizer, consumerB?.streamingEqualizer),
                .speechBooster: Self.difference(consumerA?.speechBoosterEnabled, consumerB?.speechBoosterEnabled)
            ]
            let scopesA = a.endUserSettings?.records ?? [], scopesB = b.endUserSettings?.records ?? []
            let keys = Set((scopesA + scopesB).map { (Int($0.scope) << 8) | Int($0.id) }).sorted()
            let scopes = keys.map { key -> Scope in
                let scope = UInt8(key >> 8), id = UInt8(key & 255)
                return Scope(scope: scope, id: id, difference: Self.difference(
                    scopesA.first { $0.scope == scope && $0.id == id }?.bytes,
                    scopesB.first { $0.scope == scope && $0.id == id }?.bytes))
            }
            return Aid(side: side, identity: identity, fittingRecord: Self.difference(recordA?.bytes, recordB?.bytes),
                sections: sections, consumer: consumer,
                scopeInventory: Self.difference(a.endUserSettings?.inventory, b.endUserSettings?.inventory),
                scopeMetadata: Self.difference(a.endUserSettings?.metadata, b.endUserSettings?.metadata), scopes: scopes)
        }
    }

    private static func identityMatch(_ first: DeviceBackup.Identity?, _ second: DeviceBackup.Identity?) -> IdentityMatch {
        guard let first, let second else { return .missingEar }
        // A serial conflict outweighs a reused local CoreBluetooth identifier.
        if let a = first.serialNumber, let b = second.serialNumber {
            return a == b ? .serialNumber : .differentAid
        }
        return first.peripheralID == second.peripheralID ? .localIdentifier : .differentAid
    }
    private static func difference<T: Equatable>(_ first: T?, _ second: T?) -> Difference {
        switch (first, second) {
        case (nil, nil): .notCaptured
        case (.some, nil): .firstOnly
        case (nil, .some): .secondOnly
        case (let a?, let b?): a == b ? .identical : .changed
        }
    }
    private static func blob(_ record: DeviceBackup.Record?, identity: DeviceBackup.Identity) throws -> OticonFittingRead.Blob? {
        guard let record, let hiid = identity.hiidVersion else { return nil }
        let header = try OticonFittingRead.Header(data: Data(record.bytes.prefix(OticonFittingRead.headerSize)))
        // Unknown-but-CRC-valid formats remain comparable as opaque records.
        guard header.isKnownFormat else { return nil }
        return try OticonFittingRead.decodeBlob(Data(record.bytes.dropFirst(OticonFittingRead.headerSize)), header: header, hiidVersion: hiid)
    }
}
