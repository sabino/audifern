import AppIntents
import SwiftUI
import WidgetKit

struct QuickEntry: TimelineEntry {
    let date: Date
    let state: QuickAccessState?
    let configuration: QuickWidgetConfiguration
    var preview = false
}
struct QuickProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickEntry { .init(date: Date(), state: sampleState(), configuration: .init(), preview: true) }
    func snapshot(for configuration: QuickWidgetConfiguration, in context: Context) async -> QuickEntry {
        .init(date: Date(), state: context.isPreview ? sampleState() : QuickAccessStorage.applicationGroup()?.state(), configuration: configuration, preview: context.isPreview)
    }
    func timeline(for configuration: QuickWidgetConfiguration, in context: Context) async -> Timeline<QuickEntry> {
        let now = Date(), state = QuickAccessStorage.applicationGroup()?.state()
        let entries = (0..<6).map { QuickEntry(date: now.addingTimeInterval(Double($0) * 60), state: state, configuration: configuration) }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(300)))
    }
}
struct BatteriesWidget: Widget {
    let kind = "org.audifern.batteries"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: QuickWidgetConfiguration.self, provider: QuickProvider()) { entry in
            WidgetContent(entry: entry, controls: false)
        }.configurationDisplayName("Hearing-aid batteries")
            .description("Both hearing aids, battery levels and estimated time remaining.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
struct SoundControlsWidget: Widget {
    let kind = "org.audifern.quick-controls"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: QuickWidgetConfiguration.self, provider: QuickProvider()) { entry in
            WidgetContent(entry: entry, controls: true)
        }.configurationDisplayName("Quick sound controls")
            .description("Battery status, volume, mute and quick connection controls.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
struct WidgetContent: View {
    let entry: QuickEntry
    let controls: Bool
    @Environment(\.widgetFamily) private var family
    private var target: QuickTarget { entry.configuration.ear.target }
    private var ears: [QuickEar] { entry.state?.targets(target) ?? [] }
    private var muted: Bool { !ears.isEmpty && ears.allSatisfy { $0.muted == true } }
    // Timeline entries may outlive the host's latest heartbeat. Intent execution
    // always re-reads and validates the current snapshot; an old timeline must
    // not disable a still-running host's controls after ninety seconds.
    private var canVolume: Bool { entry.state?.sharingEnabled == true && !ears.isEmpty && ears.allSatisfy(\.canChangeVolume) && !entry.preview }
    var body: some View {
        QuickWidgetView(state: entry.state, date: entry.date,
            size: family == .systemSmall ? .small : family == .systemLarge ? .large : .medium,
            target: target, artwork: Bundle.main.url(forResource: "HearingAid", withExtension: "png"),
            mark: Bundle.main.url(forResource: "BrandMark", withExtension: "png")) {
            if controls {
                VStack(spacing: 8) {
                    HStack(spacing: 7) {
                        Button(intent: QuickActionIntent(.volumeDown, ear: entry.configuration.ear)) { Image(systemName: "minus").frame(maxWidth: .infinity, minHeight: 23) }.disabled(!canVolume)
                        Button(intent: QuickActionIntent(muted ? .unmute : .mute, ear: entry.configuration.ear)) {
                            Label("Mute", systemImage: muted ? "speaker.slash.fill" : "speaker.wave.2").frame(maxWidth: .infinity, minHeight: 23)
                        }.tint(muted ? .orange : .accentColor).disabled(!canVolume)
                        Button(intent: QuickActionIntent(.volumeUp, ear: entry.configuration.ear)) { Image(systemName: "plus").frame(maxWidth: .infinity, minHeight: 23) }.disabled(!canVolume)
                    }.buttonStyle(.bordered).font(.system(size: 12))
                    if family == .systemLarge {
                        HStack(spacing: 7) {
                            let speech = !ears.isEmpty && ears.allSatisfy { $0.speechBooster == true }
                            Button(intent: QuickActionIntent(speech ? .speechOff : .speechOn, ear: entry.configuration.ear)) {
                                Label("SpeechBooster", systemImage: "mic").frame(maxWidth: .infinity, minHeight: 25)
                            }.tint(speech ? .purple : .accentColor).disabled(entry.preview || ears.isEmpty || !ears.allSatisfy(\.canChangeSpeechBooster))
                            Button(intent: QuickActionIntent(entry.state?.paused == true ? .connect : .pause)) {
                                Image(systemName: entry.state?.paused == true ? "link.badge.plus" : "link").frame(minWidth: 28, minHeight: 25)
                            }.disabled(entry.preview || entry.state?.sharingEnabled != true)
                            Button(intent: QuickActionIntent(entry.state?.macAudio == true ? .audioOff : .audioOn)) {
                                Image(systemName: "speaker.wave.2").frame(minWidth: 28, minHeight: 25)
                            }.disabled(entry.preview || entry.state?.canSwitchAudio != true)
                        }.buttonStyle(.bordered).font(.system(size: 12))
                    }
                }
            }
        }.containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(URL(string: controls ? "audifern://feature/volume" : "audifern://feature/battery-time"))
    }
}
func sampleState() -> QuickAccessState {
    let now = Date()
    let ears: [QuickEar] = [(.left, 76, 57_600), (.right, 68, 50_400)].map { side, battery, seconds in
        .init(side: side, connected: true, battery: battery,
            runtime: .init(percentage: battery, measuredAt: now, secondsAtMeasurement: Double(seconds), isCharging: false, isCharged: false),
            level: 0, muted: false, minimum: -8, maximum: 4, canChangeVolume: true, speechBooster: false, canChangeSpeechBooster: true)
    }
    return .init(session: UUID(), updatedAt: now, sharingEnabled: true, ears: ears, paused: false, canReconnect: true, macAudio: false, canSwitchAudio: true)
}
@main struct AudifernWidgetBundle: WidgetBundle {
    var body: some Widget {
        BatteriesWidget()
        SoundControlsWidget()
        if #available(macOS 26.0, *) {
            MuteControl()
            SpeechControl()
            ConnectionControl()
            MacAudioControl()
            VolumeDownControl()
            VolumeUpControl()
        }
    }
}
