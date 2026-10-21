import AppIntents
import Foundation
import WidgetKit

// The extension never opens its own Bluetooth connection. Requests expire and
// the running app confirms readback through its existing consumer executor.
enum IntentEar: String, AppEnum {
    case both, left, right
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Hearing aids"
    static let caseDisplayRepresentations: [IntentEar: DisplayRepresentation] = [.both: "Both ears", .left: "Left", .right: "Right"]
    var target: QuickTarget { QuickTarget(rawValue: rawValue)! }
}
enum IntentAction: String, AppEnum {
    case volumeDown, volumeUp, mute, unmute, speechOn, speechOff, connect, pause, audioOn, audioOff
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Action"
    static let caseDisplayRepresentations: [IntentAction: DisplayRepresentation] = [
        .volumeDown: "Volume down", .volumeUp: "Volume up", .mute: "Mute", .unmute: "Unmute",
        .speechOn: "SpeechBooster on", .speechOff: "SpeechBooster off", .connect: "Reconnect", .pause: "Pause",
        .audioOn: "Mac audio", .audioOff: "Other output"]
    var kind: QuickCommand.Kind {
        switch self { case .volumeDown, .volumeUp: .volume; case .mute, .unmute: .mute; case .speechOn, .speechOff: .speechBooster; case .connect, .pause: .connection; case .audioOn, .audioOff: .audio }
    }
    var flag: Bool? {
        switch self { case .volumeDown, .volumeUp: nil; case .mute, .speechOn, .connect, .audioOn: true; default: false }
    }
    var delta: Int? { self == .volumeUp ? 1 : self == .volumeDown ? -1 : nil }
}
struct QuickWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Hearing aids"
    static let description = IntentDescription("Choose both ears or one hearing aid.")
    @Parameter(title: "Hearing aids", default: .both) var ear: IntentEar
}
@available(macOS 26.0, *)
struct QuickControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Hearing aids"
    @Parameter(title: "Hearing aids", default: .both) var ear: IntentEar
}
struct QuickActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Audifern quick control"
    static let openAppWhenRun = false
    @Parameter(title: "Action") var action: IntentAction
    @Parameter(title: "Hearing aids", default: .both) var ear: IntentEar
    init() { action = .mute; ear = .both }
    init(_ action: IntentAction, ear: IntentEar = .both) { self.action = action; self.ear = ear }
    func perform() async throws -> some IntentResult {
        try await WidgetActionClient.perform(action, ear: ear)
        return .result()
    }
}
struct SetMuteIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Mute"
    static let openAppWhenRun = false
    @Parameter(title: "Mute") var value: Bool
    @Parameter(title: "Hearing aids", default: .both) var ear: IntentEar
    init() { ear = .both }
    init(ear: IntentEar) { self.ear = ear }
    func perform() async throws -> some IntentResult { try await WidgetActionClient.perform(value ? .mute : .unmute, ear: ear); return .result() }
}
struct SetSpeechIntent: SetValueIntent {
    static let title: LocalizedStringResource = "SpeechBooster"
    static let openAppWhenRun = false
    @Parameter(title: "SpeechBooster") var value: Bool
    @Parameter(title: "Hearing aids", default: .both) var ear: IntentEar
    init() { ear = .both }
    init(ear: IntentEar) { self.ear = ear }
    func perform() async throws -> some IntentResult { try await WidgetActionClient.perform(value ? .speechOn : .speechOff, ear: ear); return .result() }
}
struct SetConnectionIntent: SetValueIntent {
    static let title: LocalizedStringResource = "App connection"
    static let openAppWhenRun = false
    @Parameter(title: "Connected") var value: Bool
    func perform() async throws -> some IntentResult { try await WidgetActionClient.perform(value ? .connect : .pause); return .result() }
}
struct SetMacAudioIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Mac audio"
    static let openAppWhenRun = false
    @Parameter(title: "Mac audio") var value: Bool
    func perform() async throws -> some IntentResult { try await WidgetActionClient.perform(value ? .audioOn : .audioOff); return .result() }
}

enum WidgetActionClient {
    struct Unavailable: LocalizedError {
        var errorDescription: String? { String(localized: "Open Audifern and connect your hearing aids before using quick controls.") }
    }
    static func current() throws -> QuickAccessState {
        guard let state = QuickAccessStorage.applicationGroup()?.state(), state.isFresh(at: Date()) else { throw Unavailable() }
        return state
    }
    static func perform(_ action: IntentAction, ear: IntentEar = .both) async throws {
        guard let storage = QuickAccessStorage.applicationGroup() else { throw Unavailable() }
        let state = try current()
        let command = QuickCommand(session: state.session, kind: action.kind, target: ear.target, delta: action.delta, flag: action.flag)
        try storage.enqueue(command)
        defer { storage.removeReceipt(command.id) }
        let end = Date().addingTimeInterval(18)
        while Date() < end {
            if let receipt = storage.receipt(command.id) {
                guard receipt.accepted else { throw Unavailable() }
                WidgetCenter.shared.reloadAllTimelines()
                if #available(macOS 26.0, *) { ControlCenter.shared.reloadAllControls() }
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Unavailable()
    }
}
