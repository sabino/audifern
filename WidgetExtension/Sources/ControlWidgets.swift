import AppIntents
import SwiftUI
import WidgetKit

struct EarControlValue { let enabled: Bool; let ear: IntentEar }

@available(macOS 26.0, *)
struct MuteProvider: AppIntentControlValueProvider {
    func previewValue(configuration: QuickControlConfiguration) -> EarControlValue { .init(enabled: false, ear: configuration.ear) }
    func currentValue(configuration: QuickControlConfiguration) async throws -> EarControlValue {
        let ears = try WidgetActionClient.current().targets(configuration.ear.target)
        guard !ears.isEmpty, ears.allSatisfy(\.canChangeVolume) else { throw WidgetActionClient.Unavailable() }
        return .init(enabled: ears.allSatisfy { $0.muted == true }, ear: configuration.ear)
    }
}
@available(macOS 26.0, *)
struct SpeechProvider: AppIntentControlValueProvider {
    func previewValue(configuration: QuickControlConfiguration) -> EarControlValue { .init(enabled: false, ear: configuration.ear) }
    func currentValue(configuration: QuickControlConfiguration) async throws -> EarControlValue {
        let ears = try WidgetActionClient.current().targets(configuration.ear.target)
        guard !ears.isEmpty, ears.allSatisfy(\.canChangeSpeechBooster) else { throw WidgetActionClient.Unavailable() }
        return .init(enabled: ears.allSatisfy { $0.speechBooster == true }, ear: configuration.ear)
    }
}
@available(macOS 26.0, *)
struct ConnectionProvider: ControlValueProvider {
    let previewValue = false
    func currentValue() async throws -> Bool { let state = try WidgetActionClient.current(); return !state.paused && state.ears.contains(where: \.connected) }
}
@available(macOS 26.0, *)
struct AudioProvider: ControlValueProvider {
    let previewValue = false
    func currentValue() async throws -> Bool {
        let state = try WidgetActionClient.current()
        guard state.canSwitchAudio else { throw WidgetActionClient.Unavailable() }
        return state.macAudio
    }
}
@available(macOS 26.0, *)
struct VolumeProvider: AppIntentControlValueProvider {
    func previewValue(configuration: QuickControlConfiguration) -> IntentEar { configuration.ear }
    func currentValue(configuration: QuickControlConfiguration) async throws -> IntentEar {
        let ears = try WidgetActionClient.current().targets(configuration.ear.target)
        guard !ears.isEmpty, ears.allSatisfy(\.canChangeVolume) else { throw WidgetActionClient.Unavailable() }
        return configuration.ear
    }
}
@available(macOS 26.0, *)
struct MuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "org.audifern.control.mute", provider: MuteProvider()) { value in
            ControlWidgetToggle("Mute", isOn: value.enabled, action: SetMuteIntent(ear: value.ear)) { value in
                Label(value ? "Muted" : "Sound on", systemImage: value ? "speaker.slash.fill" : "speaker.wave.2")
            }
        }.displayName("Mute").description("Mute or unmute the selected hearing aids.")
    }
}
@available(macOS 26.0, *)
struct SpeechControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "org.audifern.control.speech", provider: SpeechProvider()) { value in
            ControlWidgetToggle("SpeechBooster", isOn: value.enabled, action: SetSpeechIntent(ear: value.ear)) { _ in Image(systemName: "mic") }
        }.displayName("SpeechBooster").description("Toggle supported speech support.")
    }
}
@available(macOS 26.0, *)
struct ConnectionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "org.audifern.control.connection", provider: ConnectionProvider()) { value in
            ControlWidgetToggle("App connection", isOn: value, action: SetConnectionIntent()) { connected in
                Label(connected ? "Connected" : "Disconnected", systemImage: connected ? "link" : "link.badge.plus")
            }
        }.displayName("App connection").description("Pause or reconnect Audifern’s app controls.")
    }
}
@available(macOS 26.0, *)
struct MacAudioControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "org.audifern.control.audio", provider: AudioProvider()) { value in
            ControlWidgetToggle("Mac audio", isOn: value, action: SetMacAudioIntent()) { _ in Image(systemName: "speaker.wave.2") }
        }.displayName("Mac audio").description("Switch between your preferred and other Mac audio outputs.")
    }
}
@available(macOS 26.0, *)
struct VolumeDownControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "org.audifern.control.volume-down", provider: VolumeProvider()) { ear in
            ControlWidgetButton(action: QuickActionIntent(.volumeDown, ear: ear)) { Label("Volume down", systemImage: "speaker.minus") }
        }.displayName("Volume down").description("Lower the selected hearing aids by one step.")
    }
}
@available(macOS 26.0, *)
struct VolumeUpControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "org.audifern.control.volume-up", provider: VolumeProvider()) { ear in
            ControlWidgetButton(action: QuickActionIntent(.volumeUp, ear: ear)) { Label("Volume up", systemImage: "speaker.plus") }
        }.displayName("Volume up").description("Raise the selected hearing aids by one step.")
    }
}
