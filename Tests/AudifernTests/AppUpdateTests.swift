import Foundation
import Combine
import SQLite3
import Testing
@testable import Audifern

@MainActor final class TestUpdateClient: ApplicationUpdating {
    private let changes = CurrentValueSubject<Bool, Never>(false)
    var automaticallyChecksForUpdates = false { didSet { changes.send(automaticallyChecksForUpdates) } }
    var automaticCheckChanges: AnyPublisher<Bool, Never> { changes.eraseToAnyPublisher() }
    var starts = 0
    var checks = 0
    func start() { starts += 1 }
    func checkForUpdates() { checks += 1 }
}

private func release(_ version: String, draft: Bool = false, prerelease: Bool = false, host: String = "github.com") -> AppRelease {
    AppRelease(tagName: "v" + version, name: "Audifern " + version, body: "Synthetic release notes",
               htmlURL: URL(string: "https://\(host)/sabino/audifern/releases/tag/v\(version)")!, draft: draft, prerelease: prerelease)
}

@Test func managedInstallReceiptMustOwnThisExactApp() throws {
    let app = URL(fileURLWithPath: "/Applications/Audifern.app")
    func receipt(_ fields: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: fields) }
    #expect(AppInstallationDetector.maltReceipt(try receipt(["installed": true, "app_path": app.path]), matches: app) == .malt)
    #expect(AppInstallationDetector.maltReceipt(try receipt(["installed": false]), matches: app) == nil)
    #expect(AppInstallationDetector.maltReceipt(try receipt(["installed": true, "app_path": "/Other/Audifern.app"]), matches: app) == nil)
    #expect(AppInstallationDetector.maltReceipt(try receipt(["installed": true]), matches: app) == .uncertain)
    #expect(AppInstallationDetector.maltReceipt(Data("not json".utf8), matches: app) == .uncertain)
}

@Test func nativeMaltReceiptReadDoesNotCreateADatabaseAndMatchesOnlyItsOwnedApp() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("malt.db")
    let app = URL(fileURLWithPath: "/Applications/Audifern.app")
    #expect(AppInstallationDetector.maltDatabase(databaseURL.path, matches: app) == nil)
    #expect(!FileManager.default.fileExists(atPath: databaseURL.path))
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    #expect(sqlite3_exec(database, "CREATE TABLE casks (token TEXT, app_path TEXT); INSERT INTO casks VALUES ('audifern','/Applications/Audifern.app')", nil, nil, nil) == SQLITE_OK)
    #expect(AppInstallationDetector.maltDatabase(databaseURL.path, matches: app) == .malt)
    #expect(AppInstallationDetector.maltDatabase(databaseURL.path, matches: directory.appendingPathComponent("Audifern.app")) == nil)
    #expect(sqlite3_exec(database, "UPDATE casks SET app_path=NULL", nil, nil, nil) == SQLITE_OK)
    #expect(AppInstallationDetector.maltDatabase(databaseURL.path, matches: app) == .uncertain)
}

private struct InstallationFixture {
    let root: URL
    let app: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Audifern-installation-" + UUID().uuidString)
        app = root.appendingPathComponent("Audifern.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func database(prefix name: String, owner: URL, wal: Bool = false) throws -> URL {
        let prefix = root.appendingPathComponent(name)
        let directory = prefix.appendingPathComponent("db")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("malt.db").path
        var database: OpaquePointer?
        try #require(sqlite3_open(path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        try #require(sqlite3_exec(database, "CREATE TABLE casks (token TEXT, app_path TEXT)", nil, nil, nil) == SQLITE_OK)
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(database, "INSERT INTO casks VALUES ('audifern', ?)", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        try owner.path.withCString { path in
            try #require(sqlite3_bind_text(statement, 1, path, -1, nil) == SQLITE_OK)
            try #require(sqlite3_step(statement) == SQLITE_DONE)
        }
        if wal {
            try #require(sqlite3_exec(database, "PRAGMA journal_mode=WAL", nil, nil, nil) == SQLITE_OK)
            try #require(sqlite3_wal_checkpoint_v2(database, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil) == SQLITE_OK)
        }
        return prefix
    }
    func cli(_ name: String = "mt", receipt: [String: Any]) throws -> URL {
        let executable = root.appendingPathComponent(name)
        try JSONSerialization.data(withJSONObject: receipt).write(to: root.appendingPathComponent(name + ".json"))
        // Use a real Process/pipe and receipt file, without invoking the host's managers.
        try """
        #!/bin/sh
        [ "$*" = 'info --cask audifern --json' ] || exit 64
        exec /bin/cat "$0.json"
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return executable
    }
    func detect(prefixes: [URL], executables: [URL]) -> AppInstallation {
        AppInstallationDetector.detect(bundle: app, identifier: "org.audifern.app", development: false,
                                       locations: .init(prefixes: prefixes.map(\.path), maltExecutables: executables.map(\.path), brewExecutables: []))
    }
}

@Test func missingReadOnlyWALJournalsFallBackToTheExactMaltCLIReceipt() throws {
    let fixture = try InstallationFixture()
    defer { fixture.remove() }
    let prefix = try fixture.database(prefix: "malt", owner: fixture.app, wal: true)
    let directory = prefix.appendingPathComponent("db")
    let path = directory.appendingPathComponent("malt.db").path
    // Only this closed, checkpointed synthetic database is changed. Never remove
    // the live package manager's journals or bypass them with immutable=1.
    for suffix in ["-wal", "-shm"] where FileManager.default.fileExists(atPath: path + suffix) {
        try FileManager.default.removeItem(atPath: path + suffix)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
    #expect(AppInstallationDetector.maltDatabase(path, matches: fixture.app) == .uncertain)
    let cli = try fixture.cli(receipt: ["installed": true, "app_path": fixture.app.path])
    #expect(fixture.detect(prefixes: [prefix], executables: [cli]) == .malt)
    #expect(!FileManager.default.fileExists(atPath: path + "-wal"))
    #expect(!FileManager.default.fileExists(atPath: path + "-shm"))

    for receipt: [String: Any] in [["installed": false], ["installed": true, "app_path": "/Other/Audifern.app"], ["installed": true]] {
        _ = try fixture.cli(receipt: receipt)
        #expect(fixture.detect(prefixes: [prefix], executables: [cli]) == .uncertain)
    }
}

@Test func anUnreadableReceiptOrFailedExecutableDoesNotHideAnotherMatchingReceipt() throws {
    let fixture = try InstallationFixture()
    defer { fixture.remove() }
    let broken = fixture.root.appendingPathComponent("broken")
    try FileManager.default.createDirectory(at: broken.appendingPathComponent("db"), withIntermediateDirectories: true)
    try Data("not a SQLite database".utf8).write(to: broken.appendingPathComponent("db/malt.db"))
    let matching = try fixture.database(prefix: "matching", owner: fixture.app)
    let locations = AppInstallationDetector.Locations(prefixes: [broken.path, matching.path], maltExecutables: [], brewExecutables: [])
    #expect(AppInstallationDetector.quickOwnership(bundle: fixture.app, locations: locations) == .malt)
    #expect(fixture.detect(prefixes: [broken, matching], executables: []) == .malt)

    let failedCLI = try fixture.cli("failed-mt", receipt: [:])
    try "#!/bin/sh\nexit 1\n".write(to: failedCLI, atomically: true, encoding: .utf8)
    let goodCLI = try fixture.cli(receipt: ["installed": true, "app_path": fixture.app.path])
    #expect(fixture.detect(prefixes: [broken], executables: [failedCLI, goodCLI]) == .malt)
    #expect(fixture.detect(prefixes: [broken], executables: [failedCLI]) == .uncertain)
    #expect(fixture.detect(prefixes: [], executables: [failedCLI]) == .uncertain)
    #expect(fixture.detect(prefixes: [], executables: []) == .direct)
}

@Test func nativeMaltOwnershipIncludesCommittedChangesStillInTheWAL() throws {
    let fixture = try InstallationFixture()
    defer { fixture.remove() }
    let prefix = try fixture.database(prefix: "malt", owner: fixture.root.appendingPathComponent("Old.app"), wal: true)
    let path = prefix.appendingPathComponent("db/malt.db").path
    var writer: OpaquePointer?
    try #require(sqlite3_open(path, &writer) == SQLITE_OK)
    defer { sqlite3_close(writer) }
    var statement: OpaquePointer?
    try #require(sqlite3_prepare_v2(writer, "UPDATE casks SET app_path = ?", -1, &statement, nil) == SQLITE_OK)
    try fixture.app.path.withCString { path in
        try #require(sqlite3_bind_text(statement, 1, path, -1, nil) == SQLITE_OK)
        try #require(sqlite3_step(statement) == SQLITE_DONE)
    }
    sqlite3_finalize(statement)
    #expect(AppInstallationDetector.maltDatabase(path, matches: fixture.app) == .malt)
    #expect(fixture.detect(prefixes: [prefix], executables: []) == .malt)
}

@Test func releaseComparisonAndURLsRejectUnrelatedOrUnstableDownloads() {
    #expect(AppRelease.newer("0.10.0", than: "0.9.9"))
    #expect(!AppRelease.newer("0.9.0", than: "0.9.0"))
    #expect(!AppRelease.newer("0.8.4", than: "0.9.0"))
    #expect(!AppRelease.newer("0.10.0-preview", than: "0.9.0"))
    #expect(release("0.9.0").isTrustedStable)
    #expect(!release("0.9.0", draft: true).isTrustedStable)
    #expect(!release("0.9.0", prerelease: true).isTrustedStable)
    #expect(!release("0.9.0", host: "example.com").isTrustedStable)
    #expect(!release("0.9.0-beta.1").isTrustedStable)
}

@MainActor @Test func managedUpdatesOfferTheMatchingCommandAndCannotStartTheInAppInstaller() async {
    for installation in [AppInstallation.malt, .homebrew, .uncertain] {
        let controller = AppUpdateController(version: "0.8.4", detect: { installation }, fetch: { [release("0.9.0"), release("0.8.3"), release("1.0.0", draft: true)] }, startAutomatically: false,
                                             makeUpdater: { _ in Issue.record("A managed install created the native installer"); return TestUpdateClient() })
        await controller.checkForUpdates(presentingInstaller: true)
        #expect(controller.installation == installation)
        #expect(controller.updateAvailable && controller.latest?.version == "0.9.0")
        #expect(!controller.canInstall && !controller.updaterReady)
        await controller.installUpdate()
        #expect(!controller.canInstall && !controller.updaterReady)
        #expect(controller.responds(to: NSSelectorFromString("updater:mayPerformUpdateCheck:error:")))
        #expect(controller.responds(to: NSSelectorFromString("updater:shouldProceedWithUpdate:updateCheck:error:")))
    }
    #expect(AppInstallation.malt.upgradeCommand == "mt tap --refresh sabino/tap\nmt upgrade --cask audifern")
    #expect(AppInstallation.homebrew.upgradeCommand == "brew upgrade --cask audifern")
    #expect(AppInstallation.direct.upgradeCommand == nil)
}

@MainActor @Test func directDownloadsUseTheUpdaterOnlyForANewerReleaseAndPreserveAutomaticCheckPreference() async {
    let client = TestUpdateClient()
    let controller = AppUpdateController(version: "0.8.4", detect: { .direct }, fetch: { [release("0.9.0")] },
                                         startAutomatically: false, makeUpdater: { _ in client })
    await controller.checkForUpdates()
    #expect(controller.canInstall && client.starts == 1 && client.checks == 0)
    controller.automaticallyChecks = true
    #expect(client.automaticallyChecksForUpdates)
    await controller.installUpdate()
    #expect(client.starts == 1 && client.checks == 1 && controller.automaticallyChecks)
    let current = AppUpdateController(version: "0.9.0", detect: { .direct }, fetch: { [release("0.9.0")] },
                                      startAutomatically: false, makeUpdater: { _ in client })
    await current.checkForUpdates(); await current.installUpdate()
    #expect(!current.canInstall && client.checks == 1)
}

@MainActor @Test func aFailedReleaseHistoryCheckDoesNotInventAnAvailableRelease() async {
    let controller = AppUpdateController(version: "0.8.4", detect: { .uncertain }, fetch: { throw URLError(.notConnectedToInternet) }, startAutomatically: false)
    await controller.checkForUpdates()
    #expect(controller.failed && !controller.checking && !controller.canInstall && controller.releases.isEmpty)
}

@MainActor @Test func manualDirectUpdateChecksStillUseTheSignedFeedWhenReleaseHistoryIsUnavailable() async {
    let client = TestUpdateClient()
    let controller = AppUpdateController(version: "0.9.0", detect: { .direct }, fetch: { throw URLError(.cannotConnectToHost) },
                                         startAutomatically: false, makeUpdater: { _ in client })
    await controller.checkForUpdates()
    #expect(controller.failed && client.starts == 1 && client.checks == 0)
    await controller.checkForUpdates(presentingInstaller: true)
    #expect(controller.failed && client.checks == 1)
}

@MainActor @Test func previewUpdatePagesNeverProbePackageManagersOrTheNetwork() async {
    let controller = AppUpdateController(demo: true, detect: { Issue.record("Preview probed a package manager"); return .direct },
                                         fetch: { Issue.record("Preview fetched release data"); return [] })
    await controller.checkForUpdates(); await controller.refreshInstallation(); await controller.installUpdate()
    #expect(!controller.updaterReady && !controller.canInstall && controller.checkedAt == nil)
}
