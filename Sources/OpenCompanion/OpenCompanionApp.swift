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
    @StateObject private var presetStore = SoundPresetStore()

    var body: some Scene {
        WindowGroup("Open Companion") {
            ContentView(store: store).environmentObject(presetStore)
        }
            .defaultSize(width: 1250, height: 880)
            .commands { CommandGroup(replacing: .newItem) {} }
        Window("Audiogram", id: "audiogram") {
            AudiogramEditorView(onSaved: { exam in
                presetStore.linkedAudiogramID = exam.id
                presetStore.linkedAudiogramLabel = exam.name + (exam.examDate.map { " · \($0)" } ?? "")
            })
        }.defaultSize(width: 1100, height: 850)
    }
}
