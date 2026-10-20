import AppKit
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
    @StateObject private var store = BluetoothStore()

    var body: some Scene {
        WindowGroup("Open Companion") { ContentView(store: store) }
            .defaultSize(width: 1080, height: 760)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
