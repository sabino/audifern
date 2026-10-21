import SwiftUI

/// Explicit button surfaces, including the aid's own fitted program name.
struct DeviceSoundButtons: View {
    let aid: AidConnection
    @EnvironmentObject private var navigation: AppNavigation
    var body: some View {
        HStack(spacing: 6) {
            Button(L("Details…")) { navigation.present(.device(aid.id)) }
                .help(L("Device details"))
                .accessibilityLabel(L("Device details") + ": " + L(aid.sideLabel))
                .accessibilityIdentifier("device-details-\(aid.sideLabel.lowercased())")
            if let program = aid.activeProgramName {
                Button { navigation.show(.programs) } label: {
                    Label(program, systemImage: "music.note.list").lineLimit(1)
                }.help(L("Listening program"))
                    .accessibilityLabel(L("%@ program", L(aid.sideLabel)) + ": " + program)
                    .accessibilityIdentifier("device-program-\(aid.sideLabel.lowercased())")
            }
        }.font(AppType.small).buttonStyle(.bordered).controlSize(.regular)
    }
}
