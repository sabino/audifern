import AppKit
import CompanionCore
import Foundation

/// Explicit, headless local acquisition. It only connects the matched pair
/// already known to macOS; it never chooses arbitrary scanning results.
@MainActor
final class DeviceBackupRunner {
    private let configuration: LaunchConfiguration
    private let store = BluetoothStore()
    private var task: Task<Void, Never>?
    init(configuration: LaunchConfiguration) { self.configuration = configuration }

    func start() {
        task = Task {
            var result: Int32 = 1
            do {
                guard let path = configuration.backupOutput else { throw DeviceBackup.BackupError.invalid }
                let output = URL(fileURLWithPath: path)
                guard !FileManager.default.fileExists(atPath: output.path),
                      !FileManager.default.fileExists(atPath: output.appendingPathExtension("checkpoint").path) else {
                    throw CocoaError(.fileWriteFileExists)
                }
                let deadline = Date().addingTimeInterval(configuration.backupSeconds)
                try await wait(deadline) { self.store.isPoweredOn }
                store.startScan(seconds: 10)
                try await wait(deadline) { self.store.pairCandidateIDs.count == 2 }
                store.stopScan(); store.connectPair()
                try await wait(deadline) {
                    let aids = self.store.connectedPair
                    return aids.count == 2 && aids.allSatisfy {
                        ["Left", "Right"].contains($0.sideLabel) && $0.volume != nil && $0.volumeRanges != nil
                            && $0.activeProgram != nil && !$0.advancedBusy
                    }
                }
                var checkpointCount = 0
                let backup = try await store.captureDeviceBackup(deadline: deadline) { checkpoint in
                    let file = checkpointCount == 0 ? output.appendingPathExtension("checkpoint")
                        : output.appendingPathExtension("partial-\(checkpoint.id.uuidString.lowercased())")
                    try PrivateDocuments.writeVerifiedBackup(checkpoint, to: file)
                    checkpointCount += 1
                }
                try PrivateDocuments.writeVerifiedBackup(backup, to: output)
                let records = backup.aids.reduce(0) { $0 + $1.records.count }
                print("Verified private backup: \(backup.aids.count) aids, \(records) fitting records. Clinical restore is not supported.")
                result = 0
            } catch {
                fputs("Read-only backup stopped: \(UTLSession.describe(error))\n", stderr)
            }
            await store.finishBackupConnections()
            // No GUI windows or app services were started in this process.
            exit(result)
        }
    }

    private func wait(_ deadline: Date, until condition: () -> Bool) async throws {
        while !condition() {
            try Task.checkCancellation()
            guard Date() < deadline else { throw UTLSession.SessionError.timeout }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
