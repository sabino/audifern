import AppKit
import Combine
import CompanionCore
import SwiftUI

@main
enum AudifernEntryPoint {
    @MainActor
    static func main() {
        let configuration = LaunchConfiguration()
        if let error = configuration.error {
            fputs("\(error)\n", stderr)
            exit(2)
        }
        if configuration.isBackup {
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)
            let runner = DeviceBackupRunner(configuration: configuration)
            runner.start()
            withExtendedLifetime(runner) { application.run() }
        } else if configuration.isProbe {
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)
            let store = BluetoothStore()
            store.startProbe(configuration)
            withExtendedLifetime(store) { application.run() }
        } else {
            AudifernApp.main()
        }
    }
}

struct AudifernApp: App {
    @NSApplicationDelegateAdaptor(CompanionAppDelegate.self) private var appDelegate
    @StateObject private var services = AudifernServices()

    var body: some Scene {
        Window(services.bluetooth.isDemo ? L("Audifern Preview") : Brand.name, id: "main") {
            ContentView(store: services.bluetooth, audiogramStore: services.audiograms,
                        notifications: services.batteryNotifications,
                        fittingWorkspace: services.fittingWorkspace, backups: services.backups, connectionAutomation: services.connectionAutomation)
                .environmentObject(services.presets)
                .environmentObject(services.navigation)
                .environmentObject(services.preferences)
                .environmentObject(services.equalizerDrafts)
                .environmentObject(services.help)
                .modifier(HelpPresentationAccess(help: services.help))
                .defaultAppStorage(services.defaults)
                .onAppear { services.installMenuBar() }
        }
            .defaultSize(width: 1240, height: 920)
            .commands { CompanionCommands(navigation: services.navigation, preferences: services.preferences, help: services.help) }
    }
}

/// Closing a window leaves the app-lifetime services alive. Quit is explicit.
@MainActor
final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private struct CompanionCommands: Commands {
    @ObservedObject var navigation: AppNavigation
    @ObservedObject var preferences: AppPreferences
    let help: AppHelpController
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L("About Audifern")) { navigation.present(.about); showMain() }
        }
        CommandGroup(replacing: .newItem) {
            Button(L("Open Audifern")) { show(.hearingAids) }.keyboardShortcut("1", modifiers: .command)
        }
        CommandGroup(after: .appInfo) {
            Button(L("Settings…")) { show(.settings) }.keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .help) {
            Button(L("Audifern Help")) { help.openHelp() }.keyboardShortcut("?", modifiers: .command)
            Button(L("Search features…")) { help.openHelp() }
        }
    }
    private func show(_ page: AppPage) {
        navigation.show(page)
        showMain()
    }
    private func showMain() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

/// Monitoring belongs to the app lifetime, including when its windows close.
@MainActor
final class AudifernServices: ObservableObject {
    let bluetooth: BluetoothStore
    let presets: SoundPresetStore
    let batteryNotifications: BatteryNotificationManager
    let navigation: AppNavigation
    let audiograms: AudiogramEditorStore
    let preferences: AppPreferences
    let fittingWorkspace: FittingWorkspaceStore
    let backups: DeviceBackupStore
    let connectionAutomation: ConnectionAutomation
    let help: AppHelpController
    let equalizerDrafts = EqualizerDraftStore()
    private var quickAccess: QuickAccessHost?
    private var menuBar: MenuBarController?
    let defaults: UserDefaults
    private var batteryObservation: AnyCancellable?
    private var preferenceObservation: AnyCancellable?
    private var connectionObservation: AnyCancellable?

    func installMenuBar() {
        guard menuBar == nil else { return }
        menuBar = MenuBarController(store: bluetooth, automation: connectionAutomation, help: help, preferences: preferences, defaults: defaults)
    }

    init(demo: Bool = CommandLine.arguments.contains("--demo")) {
        let defaults = demo ? UserDefaults(suiteName: "org.audifern.preview")! : .standard
        self.defaults = defaults
        if defaults.object(forKey: "groupedHearingAidControls") == nil {
            defaults.set(defaults.object(forKey: "linkedHearingAidControls") as? Bool ?? true, forKey: "groupedHearingAidControls")
        }
        let preferences = AppPreferences(defaults: defaults)
        self.preferences = preferences
        if demo {
            func option(_ key: String) -> String? {
                guard let index = CommandLine.arguments.firstIndex(of: key), index + 1 < CommandLine.arguments.count else { return nil }
                return CommandLine.arguments[index + 1]
            }
            if let value = option("--language"), let language = AppLanguage(rawValue: value) { preferences.language = language }
            if let value = option("--appearance"), let appearance = AppAppearance(rawValue: value) { preferences.appearance = appearance }
            preferences.showIdentifiers = false
        }
        bluetooth = BluetoothStore(demo: demo, batteryCache: BatteryRuntimeCache(defaults: defaults))
        let audio: any MacAudioOutputClient = demo ? PreviewMacAudioOutput() : SystemMacAudioOutput()
        connectionAutomation = ConnectionAutomation(defaults: defaults, transport: bluetooth, audio: audio,
            runTimer: !demo, observeSession: !demo)
        let automation = connectionAutomation
        bluetooth.onManualConnect = { [weak automation] in automation?.manualConnectionRequested() }
        bluetooth.onManualDisconnect = { [weak automation] in automation?.pause(disconnect: false) }
        let previewFolder = FileManager.default.temporaryDirectory.appendingPathComponent("audifern-preview-\(ProcessInfo.processInfo.processIdentifier)")
        fittingWorkspace = FittingWorkspaceStore(preview: demo)
        backups = DeviceBackupStore(folder: demo ? previewFolder.appendingPathComponent("backups", isDirectory: true) : nil)
        presets = SoundPresetStore(file: demo ? previewFolder.appendingPathComponent("presets.json") : nil)
        navigation = AppNavigation()
        help = AppHelpController(navigation: navigation, defaults: defaults)
        if demo, let index = CommandLine.arguments.firstIndex(of: "--page"), index + 1 < CommandLine.arguments.count,
           let page = AppPage(rawValue: CommandLine.arguments[index + 1]) { navigation.page = page }
        audiograms = AudiogramEditorStore(preview: demo)
        let notifications = demo ? BatteryNotificationManager(delivery: PreviewNotificationDelivery(),
            persistence: BatteryNotificationFile(file: previewFolder.appendingPathComponent("alerts.json"))) : BatteryNotificationManager()
        batteryNotifications = notifications
        let drafts = equalizerDrafts
        preferenceObservation = preferences.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        connectionObservation = bluetooth.$connections.debounce(for: .milliseconds(120), scheduler: RunLoop.main).sink { [weak automation] _ in automation?.connectionStateChanged() }
        batteryObservation = bluetooth.$connections.sink { [weak notifications, weak drafts] connections in
            drafts?.reconcile(connections)
            notifications?.retainConnectedDevices(Set(connections.values.filter(\.isConnected).map(\.id)))
            for aid in connections.values where aid.isConnected {
                guard let percentage = aid.battery else { continue }
                if aid.sideLabel == "Left" {
                    notifications?.observe(deviceID: aid.id, side: .left, percentage: percentage)
                } else if aid.sideLabel == "Right" {
                    notifications?.observe(deviceID: aid.id, side: .right, percentage: percentage)
                }
            }
        }
        quickAccess = QuickAccessHost(store: bluetooth, automation: connectionAutomation, preferences: preferences)
    }
}
