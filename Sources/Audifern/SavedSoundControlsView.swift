import CompanionCore
import SwiftUI

struct SavedSoundControlsView: View {
    let controls: OticonSavedControls.Snapshot
    let slot: OticonFittedConfiguration.Slot
    private var program: OticonSavedControls.Program? { controls.programs.first { $0.slot == slot } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let program {
                if let enabled = program.frequencyLoweringEnabled {
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            header(L("Frequency lowering"), symbol: "waveform.path", enabled: enabled)
                            LabeledContent(L("Strength"), value: choice(controls.frequencyLowering.weight))
                            LabeledContent(L("Retain source frequencies"), value: controls.frequencyLowering.retainsSource ? L("Yes") : L("No"))
                            DisclosureGroup(L("Saved frequency configuration")) {
                                VStack(alignment: .leading, spacing: 10) {
                                    LabeledContent(L("Configuration index"), value: String(controls.frequencyLowering.configurationIndex))
                                    LabeledContent(L("Prescribed index"), value: String(controls.frequencyLowering.prescribedConfigurationIndex))
                                    Text(L("These are stored configuration indices. Audifern has not established their cutoff frequencies or source-to-destination frequency map."))
                                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }.padding(.top, 10)
                            }
                        }.font(.callout)
                    }
                }
                if program.transientControl != nil || program.windControl != nil {
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            Label(L("Sudden sounds and wind"), systemImage: "wind").font(.headline)
                            if let value = program.transientControl { LabeledContent(L("Transient control"), value: choice(value)) }
                            if let value = program.windControl { LabeledContent(L("Wind control"), value: choice(value)) }
                        }.font(.callout)
                    }
                }
                if let tinnitus = program.tinnitus {
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            header(L("Saved tinnitus setup"), symbol: "waveform", enabled: tinnitus.signalGeneratorEnabled)
                            LabeledContent(L("Stored noise type"), value: choice(tinnitus.noiseType))
                            LabeledContent(L("Stored modulation"), value: choice(tinnitus.modulation))
                            LabeledContent(L("Level steering"), value: tinnitus.levelSteeringEnabled ? L("Enabled") : L("Disabled"))
                            Text(L("Reading this saved configuration generates no sound. Stored defaults do not enable therapy. Treatment levels and spectral shaping remain in the private backup."))
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.font(.callout)
                    }.tint(.orange)
                }
                Surface {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent(L("Microphone balance"), value: choice(controls.streaming.microphoneBalance))
                            LabeledContent(L("Phone stream loudness"), value: choice(controls.streaming.mfiLoudness))
                            LabeledContent(L("TV stream loudness"), value: choice(controls.streaming.televisionLoudness))
                            LabeledContent(L("Remote microphone loudness"), value: choice(controls.streaming.remoteMicrophoneLoudness))
                            Divider()
                            LabeledContent(L("Program microphone input"), value: choice(program.inputs.microphone))
                            LabeledContent(L("Program auxiliary input"), value: choice(program.inputs.auxiliary))
                            LabeledContent(L("Wireless sound quality"), value: choice(program.inputs.wirelessSoundQuality))
                            if let bass = program.bassBoost { LabeledContent(L("Bass preference · stored choice"), value: choice(bass)) }
                            LabeledContent(L("CROS source · stored choice"), value: choice(program.inputs.crosSource))
                            LabeledContent(L("CROS balance · raw coordinate"), value: program.inputs.crosBalance.formatted(.number.precision(.fractionLength(0...1))))
                            Text(L("Stored accessory preferences do not establish that a source is paired, playing or supported in the selected program. The CROS balance unit is not established by this reader."))
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.font(.callout).padding(.top, 14)
                    } label: { Label(L("Saved streaming and input preferences"), systemImage: "antenna.radiowaves.left.and.right").font(.headline) }
                }
            }
        }.accessibilityIdentifier("saved-sound-controls")
    }

    private func header(_ title: String, symbol: String, enabled: Bool) -> some View {
        HStack {
            Label(title, systemImage: symbol).font(.headline)
            Spacer(minLength: 12)
            Text(enabled ? L("Enabled in saved program") : L("Disabled in saved program"))
                .font(.caption.weight(.medium)).foregroundStyle(enabled ? Brand.accent : Color.secondary)
        }
    }
    private func choice(_ value: OticonSavedControls.Choice) -> String {
        value.label.map { L($0) } ?? L("Unknown code %d", value.code)
    }
}
