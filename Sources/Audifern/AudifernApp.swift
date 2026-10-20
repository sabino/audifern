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
        if configuration.isProbe {
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
                        notifications: services.batteryNotifications)
                .environmentObject(services.presets)
                .environmentObject(services.navigation)
                .environmentObject(services.preferences)
                .environmentObject(services.equalizerDrafts)
                .defaultAppStorage(services.defaults)
        }
            .defaultSize(width: 1240, height: 920)
            .commands { CompanionCommands(navigation: services.navigation, preferences: services.preferences) }
        MenuBarExtra {
            CompanionMenuBarView(store: services.bluetooth, navigation: services.navigation)
                .environmentObject(services.preferences)
        } label: {
            CompanionMenuBarLabel(store: services.bluetooth, preferences: services.preferences)
        }.menuBarExtraStyle(.menu)
    }
}

/// Closing a window leaves the app-lifetime services alive. Quit is explicit.
@MainActor
final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private struct CompanionMenuBarLabel: View {
    @ObservedObject var store: BluetoothStore
    @ObservedObject var preferences: AppPreferences
    var body: some View {
        Image(nsImage: AppResources.brandMark).renderingMode(.template).resizable().frame(width: 18, height: 18)
            .accessibilityLabel(L("Audifern, %d hearing aids connected", store.connectedCount))
    }
}

private struct CompanionMenuBarView: View {
    @ObservedObject var store: BluetoothStore
    @ObservedObject var navigation: AppNavigation
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(store.connectedCount > 0 ? LP("%ld hearing aid connected", "%ld hearing aids connected", count: store.connectedCount) : L("Hearing aids disconnected"))
        ForEach(store.orderedConnections.filter(\.isConnected)) { aid in
            Text("\(L(aid.sideLabel)) · \(aid.battery.map { "\($0)%" } ?? L("Battery unknown"))\(aid.activeProgramName.map { " · \($0)" } ?? "")")
        }
        Divider()
        Button(L("Open Audifern")) { showMain() }
        Button(L("Sound…")) { navigation.page = .sound; showMain() }
        Button(L("Programs…")) { navigation.page = .programs; showMain() }
        Button(L("Device information…")) { navigation.page = .devices; showMain() }
        Button(L("Audiogram…")) { navigation.page = .audiogram; showMain() }
        Button(L("Settings…")) { navigation.page = .settings; showMain() }
        if store.connectedCount < 2 && store.pairCandidateIDs.count == 2 {
            Divider()
            Button(L("Connect both hearing aids")) { store.connectPair() }.disabled(!store.isPoweredOn)
        }
        Divider()
        Text(L("Closing the window keeps Bluetooth and alerts running."))
        Button(L("Quit Audifern")) { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private func showMain() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct CompanionCommands: Commands {
    @ObservedObject var navigation: AppNavigation
    @ObservedObject var preferences: AppPreferences
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("Open Audifern")) { show(.hearingAids) }.keyboardShortcut("1", modifiers: .command)
        }
        CommandGroup(after: .appInfo) {
            Button(L("Settings…")) { show(.settings) }.keyboardShortcut(",", modifiers: .command)
        }
    }
    private func show(_ page: AppPage) {
        navigation.page = page
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
    let equalizerDrafts = EqualizerDraftStore()
    let defaults: UserDefaults
    private var batteryObservation: AnyCancellable?

    init() {
        let demo = CommandLine.arguments.contains("--demo")
        let defaults = demo ? UserDefaults(suiteName: "org.audifern.preview")! : .standard
        self.defaults = defaults
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
        bluetooth = BluetoothStore(demo: demo)
        let previewFolder = FileManager.default.temporaryDirectory.appendingPathComponent("audifern-preview-\(ProcessInfo.processInfo.processIdentifier)")
        presets = SoundPresetStore(file: demo ? previewFolder.appendingPathComponent("presets.json") : nil)
        navigation = AppNavigation()
        if demo, let index = CommandLine.arguments.firstIndex(of: "--page"), index + 1 < CommandLine.arguments.count,
           let page = AppPage(rawValue: CommandLine.arguments[index + 1]) { navigation.page = page }
        audiograms = AudiogramEditorStore(preview: demo)
        let notifications = demo ? BatteryNotificationManager(delivery: PreviewNotificationDelivery(),
            persistence: BatteryNotificationFile(file: previewFolder.appendingPathComponent("alerts.json"))) : BatteryNotificationManager()
        batteryNotifications = notifications
        let drafts = equalizerDrafts
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
    }
}
