import AppKit
import Combine
import CompanionCore
import SwiftUI

@main
enum OpenCompanionEntryPoint {
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
            OpenCompanionApp.main()
        }
    }
}

struct OpenCompanionApp: App {
    @NSApplicationDelegateAdaptor(CompanionAppDelegate.self) private var appDelegate
    @StateObject private var services = OpenCompanionServices()

    var body: some Scene {
        Window("Open Companion", id: "main") {
            ContentView(store: services.bluetooth, audiogramStore: services.audiograms,
                        notifications: services.batteryNotifications)
                .environmentObject(services.presets)
                .environmentObject(services.navigation)
        }
            .defaultSize(width: 1250, height: 880)
            .commands { CompanionCommands(navigation: services.navigation) }
        MenuBarExtra {
            CompanionMenuBarView(store: services.bluetooth, navigation: services.navigation)
        } label: {
            CompanionMenuBarLabel(store: services.bluetooth)
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
    var body: some View {
        Image(systemName: store.connectedCount > 0 ? "ear.badge.waveform" : "ear")
            .accessibilityLabel("Open Companion, \(store.connectedCount) hearing aids connected")
    }
}

private struct CompanionMenuBarView: View {
    @ObservedObject var store: BluetoothStore
    @ObservedObject var navigation: AppNavigation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(store.connectedCount > 0 ? "\(store.connectedCount) hearing aids connected" : "Hearing aids disconnected")
        ForEach(store.orderedConnections.filter(\.isConnected)) { aid in
            Text("\(aid.sideLabel) · \(aid.battery.map { "\($0)%" } ?? "Battery unknown")\(aid.activeProgramName.map { " · \($0)" } ?? "")")
        }
        Divider()
        Button("Open Companion") { showMain() }
        Button("Device information…") { navigation.page = .devices; showMain() }
        Button("Audiogram…") { navigation.page = .audiogram; showMain() }
        Button("Settings…") { navigation.page = .settings; showMain() }
        if store.connectedCount < 2 && store.pairCandidateIDs.count == 2 {
            Divider()
            Button("Connect both hearing aids") { store.connectPair() }.disabled(!store.isPoweredOn)
        }
        Divider()
        Text("Closing the window keeps Bluetooth and alerts running.")
        Button("Quit Open Companion") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private func showMain() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct CompanionCommands: Commands {
    @ObservedObject var navigation: AppNavigation
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Companion") { show(.hearingAids) }.keyboardShortcut("1", modifiers: .command)
        }
        CommandGroup(after: .appInfo) {
            Button("Settings…") { show(.settings) }.keyboardShortcut(",", modifiers: .command)
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
final class OpenCompanionServices: ObservableObject {
    let bluetooth: BluetoothStore
    let presets: SoundPresetStore
    let batteryNotifications: BatteryNotificationManager
    let navigation: AppNavigation
    let audiograms: AudiogramEditorStore
    private var batteryObservation: AnyCancellable?

    init() {
        bluetooth = BluetoothStore()
        presets = SoundPresetStore()
        navigation = AppNavigation()
        audiograms = AudiogramEditorStore()
        let notifications = BatteryNotificationManager()
        batteryNotifications = notifications
        batteryObservation = bluetooth.$connections.sink { [weak notifications] connections in
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
