import AppKit
import Combine
import Foundation
import Sparkle
import SQLite3
import SwiftUI

enum AppInstallation: Equatable, Sendable {
    case direct, malt, homebrew, development, uncertain
    var upgradeCommand: String? {
        switch self {
        case .malt: "mt tap --refresh sabino/tap\nmt upgrade --cask audifern"
        case .homebrew: "brew upgrade --cask audifern"
        default: nil
        }
    }
    var title: String {
        switch self {
        case .direct: L("Direct download")
        case .malt: "Malt"
        case .homebrew: "Homebrew"
        case .development: L("Development build")
        case .uncertain: L("Installation not identified")
        }
    }
}

enum AppInstallationDetector {
    static func maltDatabase(_ path: String, matches bundle: URL) -> AppInstallation? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }; return .uncertain
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 25)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT app_path FROM casks WHERE token = 'audifern' LIMIT 1", -1, &statement, nil) == SQLITE_OK else { return .uncertain }
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return .uncertain }
        let path = String(cString: text)
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL == bundle.resolvingSymlinksInPath().standardizedFileURL ? .malt : nil
    }
    static func quickOwnership(bundle: URL = Bundle.main.bundleURL) -> AppInstallation? {
        let environment = ProcessInfo.processInfo.environment
        let paths = (environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }.map(String.init)
        var prefixes = ["/opt/malt", "/opt/homebrew", "/usr/local"]
        for name in ["MALT_PREFIX", "HOMEBREW_PREFIX"] {
            if let prefix = environment[name], prefix.hasPrefix("/") { prefixes.append(prefix) }
        }
        for directory in paths {
            let executable = URL(fileURLWithPath: directory).appendingPathComponent("mt")
            if FileManager.default.isExecutableFile(atPath: executable.path) {
                prefixes.append(executable.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().path)
            }
        }
        for prefix in Set(prefixes).sorted() {
            if let source = maltDatabase(prefix + "/db/malt.db", matches: bundle) { return source }
            if FileManager.default.fileExists(atPath: prefix + "/Caskroom/audifern/.metadata") { return .homebrew }
        }
        return nil
    }
    static func maltReceipt(_ data: Data, matches bundle: URL) -> AppInstallation? {
        guard let receipt = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let installed = receipt["installed"] as? Bool else { return .uncertain }
        guard installed else { return nil }
        guard let path = receipt["app_path"] as? String else { return .uncertain }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL == bundle.resolvingSymlinksInPath().standardizedFileURL ? .malt : nil
    }
    static func detect(bundle: URL = Bundle.main.bundleURL, identifier: String? = Bundle.main.bundleIdentifier,
                       development: Bool = Bundle.main.object(forInfoDictionaryKey: "AudifernDevelopmentBuild") as? Bool == true) -> AppInstallation {
        guard !development, bundle.pathExtension == "app", identifier == "org.audifern.app" else { return .development }
        if let source = quickOwnership(bundle: bundle) { return source }
        let fm = FileManager.default
        // A known receipt owns the install even if the user has replaced its
        // files manually. Never silently bypass a package manager's database.
        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }.map(String.init)
        let maltPaths = Set(["/usr/local/bin/mt", "/opt/malt/bin/mt", "/opt/homebrew/bin/mt"] + searchPaths.map { $0 + "/mt" })
        for executable in maltPaths.sorted() where fm.isExecutableFile(atPath: executable) {
            guard let data = command(executable, ["info", "--cask", "audifern", "--json"]) else { return .uncertain }
            if let installation = maltReceipt(data, matches: bundle) { return installation }
        }
        var rooms = ["/opt/homebrew/Caskroom/audifern", "/usr/local/Caskroom/audifern"]
        let brewPaths = Set(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] + searchPaths.map { $0 + "/brew" })
        for executable in brewPaths.sorted() where fm.isExecutableFile(atPath: executable) {
            guard let data = command(executable, ["--caskroom", "audifern"]), let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), path.hasPrefix("/") else { return .uncertain }
            rooms.append(path)
        }
        if rooms.contains(where: { fm.fileExists(atPath: $0 + "/.metadata") }) { return .homebrew }
        return .direct
    }
    private static func command(_ executable: String, _ arguments: [String]) -> Data? {
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"; environment["HOMEBREW_NO_ANALYTICS"] = "1"
        process.environment = environment
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { process.terminate(); return nil }
        guard process.terminationStatus == 0 else { return nil }
        return try? pipe.fileHandleForReading.read(upToCount: 65_536)
    }
}

struct AppRelease: Identifiable, Decodable, Sendable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    var id: String { tagName }
    var version: String { String(tagName.dropFirst()) }
    var isTrustedStable: Bool {
        !draft && !prerelease && tagName.range(of: #"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil
            && htmlURL.scheme == "https" && htmlURL.host == "github.com" && htmlURL.user == nil && htmlURL.password == nil
            && htmlURL.path == "/sabino/audifern/releases/tag/" + tagName && htmlURL.query == nil && htmlURL.fragment == nil
    }
    static func newer(_ candidate: String, than installed: String) -> Bool {
        func components(_ string: String) -> [Int]? {
            let parts = string.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            let numbers = parts.compactMap { Int($0) }
            return numbers.count == 3 && numbers.allSatisfy { $0 >= 0 } ? numbers : nil
        }
        guard let candidate = components(candidate), let installed = components(installed) else { return false }
        return installed.lexicographicallyPrecedes(candidate)
    }
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", htmlURL = "html_url", name, body, draft, prerelease
    }
}

@MainActor protocol ApplicationUpdating: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticCheckChanges: AnyPublisher<Bool, Never> { get }
    func start()
    func checkForUpdates()
}

@MainActor private final class SparkleUpdateClient: ApplicationUpdating {
    private let controller: SPUStandardUpdaterController
    init(delegate: any SPUUpdaterDelegate) {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: nil)
    }
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var automaticCheckChanges: AnyPublisher<Bool, Never> { controller.updater.publisher(for: \.automaticallyChecksForUpdates).eraseToAnyPublisher() }
    func start() { controller.startUpdater() }
    func checkForUpdates() { controller.checkForUpdates(nil) }
}

@MainActor final class AppUpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var installation: AppInstallation = .development
    @Published private(set) var detecting = false
    @Published private(set) var checking = false
    @Published private(set) var releases: [AppRelease] = []
    @Published private(set) var checkedAt: Date?
    @Published private(set) var failed = false
    @Published var automaticallyChecks = false {
        didSet { if !updatingPreference { client?.automaticallyChecksForUpdates = automaticallyChecks } }
    }
    let installedVersion: String
    let installedBuild: String
    private let demo: Bool
    private var client: (any ApplicationUpdating)?
    private let makeUpdater: ((AppUpdateController) -> any ApplicationUpdating)?
    private var observations: [AnyCancellable] = []
    private var updatingPreference = false
    private let detect: @Sendable () -> AppInstallation
    private let fetch: @Sendable () async throws -> [AppRelease]

    init(demo: Bool = false, version: String? = nil,
         detect: @escaping @Sendable () -> AppInstallation = { AppInstallationDetector.detect() },
         fetch: @escaping @Sendable () async throws -> [AppRelease] = { try await AppUpdateController.fetchReleases() },
         startAutomatically: Bool = true, makeUpdater: ((AppUpdateController) -> any ApplicationUpdating)? = nil) {
        self.demo = demo; self.detect = detect; self.fetch = fetch
        self.makeUpdater = makeUpdater
        installedVersion = version ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.9.0"
        installedBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "21"
        super.init()
        if !demo && startAutomatically { Task { [weak self] in await self?.refreshInstallation() } }
    }
    var latest: AppRelease? { releases.first }
    var updateAvailable: Bool { latest.map { AppRelease.newer($0.version, than: installedVersion) } ?? false }
    var canInstall: Bool { installation == .direct && client != nil && updateAvailable && !checking && !detecting }
    var updaterReady: Bool { client != nil }

    func refreshInstallation() async {
        guard !demo, !detecting else { return }
        detecting = true
        let probe = detect
        installation = await Task.detached(priority: .utility) { probe() }.value
        detecting = false
        if installation == .direct, client == nil, makeUpdater != nil || Self.hasUpdateConfiguration {
            let client = makeUpdater?(self) ?? SparkleUpdateClient(delegate: self)
            self.client = client
            client.start()
            observations.append(client.automaticCheckChanges.sink { [weak self] value in
                guard let self else { return }
                self.updatingPreference = true; self.automaticallyChecks = value; self.updatingPreference = false
            })
        } else if installation != .direct, let client {
            client.automaticallyChecksForUpdates = false
        }
    }
    func checkForUpdates(presentingInstaller: Bool = false) async {
        guard !demo, !checking else { return }
        checking = true; failed = false
        await refreshInstallation()
        defer { checking = false }
        do {
            releases = try await fetch().filter(\.isTrustedStable).sorted { AppRelease.newer($0.version, than: $1.version) }
            checkedAt = Date()
        } catch { failed = true }
        // A manual update check uses the signed feed even if GitHub's separate
        // release-history API is unavailable or rate limited. Opening Settings
        // only loads the history; it must not present an installer dialog.
        if presentingInstaller, installation == .direct { client?.checkForUpdates() }
    }
    func installUpdate() async {
        await refreshInstallation()
        guard canInstall else { return }
        client?.checkForUpdates()
    }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        try requireDirectInstallation()
    }
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        try requireDirectInstallation()
    }
    private func requireDirectInstallation() throws {
        // Recheck receipts before Sparkle proceeds as well as before the app's
        // own Install button. Adopting the app into a manager must not leave a
        // previously started background updater able to overwrite that install.
        guard !demo, installation == .direct, AppInstallationDetector.quickOwnership() == nil else {
            throw NSError(domain: "org.audifern.updates", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Use your package manager to update Audifern.")])
        }
    }
    private static var hasUpdateConfiguration: Bool {
        Bundle.main.bundleIdentifier == "org.audifern.app"
            && (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String).flatMap { Data(base64Encoded: $0) }?.count == 32
            && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String == "https://github.com/sabino/audifern/releases/latest/download/appcast.xml"
    }
    nonisolated static func fetchReleases() async throws -> [AppRelease] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil; configuration.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/sabino/audifern/releases?per_page=20")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Audifern", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 2_000_000,
              response.url?.host == "api.github.com" else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([AppRelease].self, from: data)
    }
}

private struct AppUpdatesKey: EnvironmentKey { static let defaultValue: AppUpdateController? = nil }
extension EnvironmentValues {
    var appUpdates: AppUpdateController? {
        get { self[AppUpdatesKey.self] }
        set { self[AppUpdatesKey.self] = newValue }
    }
}
