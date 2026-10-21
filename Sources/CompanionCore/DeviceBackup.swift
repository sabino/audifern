import CryptoKit
import Foundation

/// A local record of data actually read from the aids. Coverage is derived from
/// the payload, never from the presence of a service in the registry. In
/// particular this archive does not claim to be a restorable clinical fitting.
public struct DeviceBackup: Codable, Equatable, Sendable {
    public enum BackupError: Error, Equatable { case invalid, digestMismatch }
    public enum AcquisitionStage: String, Codable, Sendable {
        case consumerCheckpoint, partialRead, readCompleted
    }

    public struct Service: Codable, Equatable, Sendable {
        public let id: UInt32
        public let major: UInt8
        public let minor: UInt8
        public let available: Bool
        public init(_ service: UTLProtocol.Service) {
            id = service.id; major = service.major; minor = service.minor; available = service.isAvailable
        }
    }

    public struct Identity: Codable, Equatable, Sendable {
        /// Identifiers are retained only in private local backups, never in the
        /// shareable consumer snapshot or diagnostic export.
        public let peripheralID: UUID
        public let serialNumber: String?
        public let model: String?
        public let firmware: String?
        public let software: String?
        public let hiidVersion: String?
        public let releasePackageVersion: String?
        public let runtimeMemoryMapVersion: String?

        public init(peripheralID: UUID, serialNumber: String? = nil, model: String? = nil,
                    firmware: String? = nil, software: String? = nil, hiidVersion: String? = nil,
                    releasePackageVersion: String? = nil, runtimeMemoryMapVersion: String? = nil) {
            self.peripheralID = peripheralID; self.serialNumber = serialNumber; self.model = model
            self.firmware = firmware; self.software = software; self.hiidVersion = hiidVersion
            self.releasePackageVersion = releasePackageVersion; self.runtimeMemoryMapVersion = runtimeMemoryMapVersion
        }
    }

    public struct Record: Codable, Equatable, Sendable {
        public let key: UInt16
        public let bytes: Data
        public let sha256: String
        public init(key: UInt16, bytes: Data) throws {
            guard !bytes.isEmpty, bytes.count <= 65_535 else { throw BackupError.invalid }
            self.key = key; self.bytes = bytes; sha256 = DeviceBackup.digest(bytes)
        }
        fileprivate func validate() throws {
            guard !bytes.isEmpty, bytes.count <= 65_535 else { throw BackupError.invalid }
            guard sha256 == DeviceBackup.digest(bytes) else { throw BackupError.digestMismatch }
        }
    }

    public struct Aid: Codable, Equatable, Sendable {
        public let side: ConsumerProgramSnapshot.Side
        public let identity: Identity
        public let services: [Service]
        public let programs: [ConsumerProgramSnapshot.Program]
        public let programInventoryComplete: Bool
        public let records: [Record]
        public let endUserSettings: EndUserSettings?
        public let notes: [String]

        public init(side: ConsumerProgramSnapshot.Side, identity: Identity, services: [Service] = [],
                    programs: [ConsumerProgramSnapshot.Program] = [], programInventoryComplete: Bool = false,
                    records: [Record] = [], endUserSettings: EndUserSettings? = nil, notes: [String] = []) {
            self.side = side; self.identity = identity; self.services = services; self.programs = programs
            self.programInventoryComplete = programInventoryComplete
            self.records = records; self.notes = notes
            self.endUserSettings = endUserSettings
        }
    }

    /// Raw NVRAM CBOR returned by the advertised EUS2.1 scopes. Completeness is
    /// limited to that inventory, and says nothing about live RAM or firmware.
    public struct EndUserSettings: Codable, Equatable, Sendable {
        public struct ScopeRecord: Codable, Equatable, Sendable {
            public let scope: UInt8
            public let id: UInt8
            public let bytes: Data
            public let sha256: String
            public init(scope: UInt8, id: UInt8, bytes: Data) throws {
                self.scope = scope; self.id = id
                self.bytes = try OticonEndUserSettings.validateResponse(bytes)
                sha256 = DeviceBackup.digest(bytes)
            }
        }
        public let inventory: Data
        public let metadata: Data?
        public let records: [ScopeRecord]
        public init(inventory: Data, metadata: Data? = nil, records: [ScopeRecord]) throws {
            self.inventory = inventory; self.metadata = metadata; self.records = records
            try validate()
        }
        public var isComplete: Bool {
            guard let decoded = try? OticonEndUserSettings.decodeInventory(inventory), decoded.isComplete else { return false }
            return Set(decoded.reads.map { "\($0.scope)/\($0.id)" }) == Set(records.map { "\($0.scope)/\($0.id)" })
        }
        fileprivate func validate() throws {
            _ = try OticonEndUserSettings.validateResponse(inventory)
            let decoded = try? OticonEndUserSettings.decodeInventory(inventory)
            if let metadata { _ = try OticonEndUserSettings.validateResponse(metadata) }
            // New/unknown metadata can be preserved without guessing scope IDs.
            // No scope result may claim to belong to an unparsed inventory.
            let expected = Set((decoded?.reads ?? []).map { "\($0.scope)/\($0.id)" })
            let actual = records.map { "\($0.scope)/\($0.id)" }
            guard records.count <= 128, Set(actual).count == records.count,
                  Set(actual).isSubset(of: expected), records.reduce(0, { $0 + $1.bytes.count }) <= 196_608 else {
                throw BackupError.invalid
            }
            for record in records {
                _ = try OticonEndUserSettings.validateResponse(record.bytes)
                guard record.sha256 == DeviceBackup.digest(record.bytes) else { throw BackupError.digestMismatch }
            }
        }
    }

    public let schemaVersion: Int
    public let id: UUID
    public let capturedAt: Date
    public let consumerControls: ConsumerProgramSnapshot
    public let aids: [Aid]
    /// Absent in early schema-one archives. Partial captures retain completed
    /// reads even when subsequent connection or consumer-state checks fail.
    public let acquisitionStage: AcquisitionStage?
    /// No restore implementation is shipped. Even a successful read of HIID1009
    /// does not include all EUS scopes, calibration, firmware or clinical state.
    public let clinicalRestoreSupported: Bool

    public init(id: UUID = UUID(), capturedAt: Date = Date(), consumerControls: ConsumerProgramSnapshot,
                aids: [Aid], acquisitionStage: AcquisitionStage? = nil) throws {
        schemaVersion = 1; self.id = id; self.capturedAt = capturedAt
        self.consumerControls = consumerControls; self.aids = aids; self.acquisitionStage = acquisitionStage
        clinicalRestoreSupported = false
        try validate()
    }

    public func validate() throws {
        guard schemaVersion == 1, !clinicalRestoreSupported, capturedAt.timeIntervalSince1970.isFinite,
              (1...2).contains(aids.count), Set(aids.map(\.side)).count == aids.count,
              Set(aids.map { $0.identity.peripheralID }).count == aids.count,
              Set(aids.map(\.side)) == Set(consumerControls.aids.map(\.side)) else { throw BackupError.invalid }
        try consumerControls.validate()
        for aid in aids {
            let identity = aid.identity
            for text in [identity.serialNumber, identity.model, identity.firmware, identity.software,
                         identity.hiidVersion, identity.releasePackageVersion, identity.runtimeMemoryMapVersion].compactMap({ $0 }) {
                guard !text.isEmpty, text.utf8.count <= 256,
                      !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw BackupError.invalid }
            }
            guard aid.services.count <= 256, Set(aid.services.map(\.id)).count == aid.services.count,
                  aid.programs.count <= 32, Set(aid.programs.map(\.programID)).count == aid.programs.count,
                  !aid.programInventoryComplete || !aid.programs.isEmpty,
                  aid.records.count <= 64, Set(aid.records.map(\.key)).count == aid.records.count,
                  aid.notes.count <= 32, aid.notes.allSatisfy({ $0.utf8.count <= 512 }) else { throw BackupError.invalid }
            for program in aid.programs {
                _ = try ConsumerProgramSnapshot.Program(programID: program.programID, name: program.name,
                    category: program.category, boostable: program.boostable, tinnitus: program.tinnitus, mic: program.mic)
            }
            for record in aid.records {
                try record.validate()
                if record.key == OticonFittingRead.recordKey {
                    guard record.bytes.count >= OticonFittingRead.headerSize else { throw BackupError.invalid }
                    _ = try OticonFittingRead.validateRecord(header: Data(record.bytes.prefix(OticonFittingRead.headerSize)),
                        payload: Data(record.bytes.dropFirst(OticonFittingRead.headerSize)))
                }
            }
            try aid.endUserSettings?.validate()
        }
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumArchiveBytes else { throw BackupError.invalid }
        return data
    }

    public static let maximumArchiveBytes = 1_048_576
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumArchiveBytes else { throw BackupError.invalid }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(Self.self, from: data)
        try result.validate()
        return result
    }
    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Integrity envelope. Validate the digest before decoding the bounded payload;
/// this detects accidental corruption, not a maliciously rewritten archive.
public struct DeviceBackupArchive: Codable, Sendable {
    public let schemaVersion: Int
    public let sha256: String
    public let payload: Data
    public static let maximumBytes = (DeviceBackup.maximumArchiveBytes * 4 / 3) + 4096

    public init(_ backup: DeviceBackup) throws {
        schemaVersion = 1; payload = try backup.encoded(); sha256 = DeviceBackup.digest(payload)
    }
    public func encoded() throws -> Data {
        _ = try verifiedBackup()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw DeviceBackup.BackupError.invalid }
        return data
    }
    public func verifiedBackup() throws -> DeviceBackup {
        guard schemaVersion == 1, payload.count <= DeviceBackup.maximumArchiveBytes else { throw DeviceBackup.BackupError.invalid }
        guard sha256 == DeviceBackup.digest(payload) else { throw DeviceBackup.BackupError.digestMismatch }
        return try DeviceBackup.decode(payload)
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw DeviceBackup.BackupError.invalid }
        let result = try JSONDecoder().decode(Self.self, from: data)
        _ = try result.verifiedBackup()
        return result
    }
}
