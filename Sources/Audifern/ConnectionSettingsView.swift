import SwiftUI

struct ConnectionSettingsView: View {
    @ObservedObject var automation: ConnectionAutomation
    @EnvironmentObject private var navigation: AppNavigation
    @State private var section = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(L("Automatically reconnect app controls"), isOn: $automation.enabled)
                .toggleStyle(.switch).accessibilityIdentifier("auto-connection-enabled")
            Text(L(automation.status)).font(AppType.callout).foregroundStyle(Brand.accent)
                .accessibilityIdentifier("auto-connection-status")
            Picker(L("Connection settings"), selection: $section) {
                Text(L("Reconnect")).tag(0)
                Text(L("Nearby signal")).tag(1)
                Text(L("Mac audio output")).tag(2)
            }.pickerStyle(.segmented).labelsHidden()
            switch section {
            case 1: signal
            case 2: audio
            default: reconnect
            }
            Spacer(minLength: 0)
        }.onAppear { automation.refreshAudio() }
    }
    private var reconnect: some View {
            Surface {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("Connect only to your chosen hearing aids while this Mac is unlocked. Failed attempts wait longer before retrying."))
                        .font(AppType.callout).foregroundStyle(.secondary)
                    HStack {
                        Text(L("%d hearing aids remembered", automation.remembered.count)).font(AppType.callout)
                        Spacer()
                        Button(L("Use connected hearing aids")) { _ = automation.useConnectedAids() }
                            .disabled(!automation.canUseConnectedAids)
                        if !automation.remembered.isEmpty { Button(L("Forget")) { automation.forgetAids() } }
                    }
                    if automation.remembered.isEmpty {
                        Button(L("Choose hearing aids…")) { navigation.show(.devices) }
                    }
                    Toggle(L("Retry when hearing aids are nearby"), isOn: $automation.whenNearby)
                    Toggle(L("Try after waking or unlocking this Mac"), isOn: $automation.afterUnlock)
                    Toggle(L("Disconnect app controls when this Mac locks"), isOn: $automation.releaseOnLock)
                    HStack {
                        Button(automation.paused ? L("Resume app connection") : L("Pause app connection")) {
                            if automation.paused { automation.resume() } else { automation.pause() }
                        }.accessibilityIdentifier("auto-connection-pause")
                        Text(L("Pause stays in effect until you resume or connect manually."))
                            .font(AppType.caption).foregroundStyle(.secondary)
                    }
                }
            }
    }
    private var signal: some View {
            Surface {
                VStack(alignment: .leading, spacing: 16) {
                    Label(L("Nearby signal"), systemImage: "antenna.radiowaves.left.and.right").font(AppType.headline)
                    Toggle(L("Require a stronger signal before reconnecting"), isOn: $automation.limitSignal)
                    HStack {
                        Text(L("Minimum signal"))
                        Slider(value: $automation.minimumRSSI, in: -90 ... -35, step: 1)
                            .accessibilityIdentifier("auto-connection-signal")
                        Text(L("%d dBm", Int(automation.minimumRSSI))).monospacedDigit().frame(width: 84, alignment: .trailing)
                    }
                    HStack {
                        Text(automation.currentSignal.map { L("Current signal: %d dBm", $0) } ?? L("No fresh signal yet."))
                        Spacer()
                        Button(L("Measure signal")) { automation.calibrateSignal() }
                    }.font(AppType.callout)
                    Text(L("Use this at your desk to tune when reconnection starts. Signal strength is approximate: walls, your body and the room affect it. It is not a distance in meters."))
                        .font(AppType.caption).foregroundStyle(.secondary)
                }
            }
    }
    private var audio: some View {
            Surface {
                VStack(alignment: .leading, spacing: 16) {
                    Label(L("Mac audio output"), systemImage: "speaker.wave.2").font(AppType.headline)
                    Text(L("Current output: %@", automation.availableOutputs.first(where: { $0.id == automation.currentOutputUID })?.name ?? L("Unavailable")))
                        .font(AppType.callout)
                    Picker(L("Preferred output"), selection: $automation.preferredOutputUID) {
                        Text(L("Choose an output")).tag("")
                        if !automation.preferredOutputUID.isEmpty,
                           !automation.availableOutputs.contains(where: { $0.id == automation.preferredOutputUID }) {
                            Text(L("Saved output · unavailable")).tag(automation.preferredOutputUID)
                        }
                        ForEach(automation.availableOutputs) { Text($0.name).tag($0.id) }
                    }
                    Toggle(L("Select this output after app controls reconnect"), isOn: $automation.preferMacAudio)
                        .disabled(!automation.enabled)
                    Toggle(L("Restore my previous audio output when this Mac locks"), isOn: $automation.restoreAudioOnLock)
                        .disabled(!automation.enabled)
                    HStack {
                        Button(L("Use selected output now")) { automation.usePreferredAudio() }
                            .disabled(!automation.availableOutputs.contains(where: { $0.id == automation.preferredOutputUID }))
                        Button(L("Refresh outputs")) { automation.refreshAudio() }
                    }.font(AppType.callout)
                    Link(L("macOS Sound settings"), destination: URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                        .font(AppType.callout)
                    if automation.audioError { Text(L("macOS could not select that audio output.")).foregroundStyle(.red) }
                    Text(L("App controls and audio are separate connections. This selects an output already available to macOS. Android may still hold the audio connection; pausing Audifern does not disconnect macOS audio."))
                        .font(AppType.caption).foregroundStyle(.secondary)
                }
            }
    }
}

struct ConnectionQuickActions: View {
    @ObservedObject var automation: ConnectionAutomation
    var body: some View {
        Button(automation.paused ? L("Resume app connection") : L("Pause app connection")) {
            if automation.paused { automation.resume() } else { automation.pause() }
        }
    }
}
