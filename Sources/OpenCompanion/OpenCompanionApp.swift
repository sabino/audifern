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
    @StateObject private var services = OpenCompanionServices()

    var body: some Scene {
        WindowGroup("Open Companion") {
            ContentView(store: services.bluetooth).environmentObject(services.presets)
        }
            .defaultSize(width: 1250, height: 880)
            .commands { CommandGroup(replacing: .newItem) {} }
        Window("Audiogram", id: "audiogram") {
            AudiogramEditorView(onSaved: { exam in
                services.presets.linkedAudiogramID = exam.id
                services.presets.linkedAudiogramLabel = exam.name + (exam.examDate.map { " · \($0)" } ?? "")
            })
        }.defaultSize(width: 1100, height: 850)
        Settings {
            BatteryNotificationSettingsView(manager: services.batteryNotifications)
                .frame(minWidth: 480, idealWidth: 540)
        }
    }
}

/// Monitoring belongs to the app lifetime, including when its windows close.
@MainActor
final class OpenCompanionServices: ObservableObject {
    let bluetooth: BluetoothStore
    let presets: SoundPresetStore
    let batteryNotifications: BatteryNotificationManager
    private var batteryObservation: AnyCancellable?

    init() {
        bluetooth = BluetoothStore()
        presets = SoundPresetStore()
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
