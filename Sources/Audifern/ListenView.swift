import CompanionCore
import SwiftUI

/// Daily controls contain no device identifiers or protocol/debug fields.
struct ListenView: View {
    @ObservedObject var store: BluetoothStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var preferences: AppPreferences
    @AppStorage("linkedHearingAidControls") private var linked = true
    @AppStorage("linkedHearingAidSpeechBooster") private var linkedSpeech = false

    private var aids: [AidConnection] {
        store.orderedConnections.sorted { $0.sideLabel == "Left" && $1.sideLabel != "Left" }
    }
    private var pair: [AidConnection]? {
        guard let left = aids.first(where: { $0.sideLabel == "Left" }),
              let right = aids.first(where: { $0.sideLabel == "Right" }) else { return nil }
        return [left, right]
    }
    private var canLink: Bool { pair != nil && store.connectedPair.count == 2 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(title: L("Your hearing"), subtitle: L("Everyday controls, always close at hand.")) { ConnectionBadge(store: store) }
                if store.isDemo {
                    Label(L("Preview only. Sample devices; Bluetooth and sound changes are disabled."), systemImage: "eye")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let error = store.lastError { Label(M(error), systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(.callout) }
                if let pair {
                    Surface {
                        VStack(spacing: 22) {
                            HStack(alignment: .center, spacing: 18) {
                                earSummary(pair[0])
                                VStack(spacing: 18) {
                                    VStack(spacing: 6) {
                                        Text(L("Listening program")).font(.caption).foregroundStyle(.secondary)
                                        Button { navigation.page = .programs } label: {
                                            HStack(spacing: 7) { Text(pair[0].activeProgramName ?? L("Read program")); Image(systemName: "chevron.down").font(.caption2) }
                                                .padding(.horizontal, 8).padding(.vertical, 3)
                                        }.buttonStyle(.bordered).accessibilityIdentifier("open-listening-programs")
                                    }
                                    EarLinkButton(title: "Volume and mute", linked: $linked, available: canLink, identifier: "link-volume", accent: Brand.accent)
                                    Text(linked ? L("Changes affect both ears") : L("Adjust each ear independently"))
                                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                }.frame(width: 180)
                                earSummary(pair[1])
                            }.frame(maxWidth: 760)
                            Divider()
                            if linked { LinkedControlsView(store: store).disabled(store.isDemo) }
                            else {
                                EarSettingsRow {
                                    VolumeButtonsView(store: store, aid: pair[0])
                                } center: { EmptyView() } right: {
                                    VolumeButtonsView(store: store, aid: pair[1])
                                }.disabled(store.isDemo)
                            }
                            if let status = store.linkedActionStatus {
                                Label(M(status), systemImage: store.linkedActionFailed ? "exclamationmark.circle" : "checkmark.circle")
                                    .font(.caption).foregroundStyle(store.linkedActionFailed ? Color.orange : .secondary)
                                    .accessibilityIdentifier("sound-change-status")
                            }
                        }
                    }
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            Label(L("Speech boost"), systemImage: "waveform").font(.headline)
                            EarSettingsRow {
                                SpeechBoosterCell(store: store, aid: pair[0], targetIDs: linkedSpeech && canLink ? pair.map(\.id) : [pair[0].id])
                            } center: {
                                EarLinkButton(title: "SpeechBooster", linked: $linkedSpeech, available: canLink,
                                              identifier: "link-speech-booster", accent: Brand.accent)
                            } right: {
                                SpeechBoosterCell(store: store, aid: pair[1], targetIDs: linkedSpeech && canLink ? pair.map(\.id) : [pair[1].id])
                            }.disabled(store.isDemo)
                        }
                    }
                } else if let aid = aids.first {
                    Surface {
                        VStack(spacing: 20) {
                            earSummary(aid)
                            VolumeButtonsView(store: store, aid: aid).disabled(store.isDemo)
                            if let status = aid.actionStatus { Text(M(status)).font(.caption).foregroundStyle(.secondary) }
                            Button(L("Connect the other ear")) { navigation.page = .devices }
                        }
                    }
                } else {
                    Surface {
                        ContentUnavailableView {
                            Label(L("Ready when you are"), systemImage: "ear.badge.waveform")
                        } description: { Text(L("Keep your hearing aids nearby, then connect over Bluetooth.")) }
                        actions: {
                            if store.pairCandidateIDs.count == 2 {
                                Button(L("Connect hearing aids")) { store.connectPair() }.buttonStyle(.borderedProminent).disabled(!store.isPoweredOn)
                            }
                            Button(L("Find hearing aids")) { navigation.page = .devices }
                        }.frame(minHeight: 330)
                    }
                }
                navigationCard(title: L("Sound presets"), subtitle: L("Save a sound you like and return to it later."), symbol: "bookmark", page: .programs)
                navigationCard(title: L("Advanced sound controls"), subtitle: L("Equalizers, streaming sound and fitted tinnitus relief."), symbol: "slider.horizontal.3", page: .sound)
            }.padding(30).frame(maxWidth: 1080)
        }
    }

    private func earSummary(_ aid: AidConnection) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(aid.isConnected ? Brand.accent : Color.secondary).frame(width: 5, height: 5)
                Text(L(aid.sideLabel)).font(.headline)
            }
            HearingAidArtwork(right: aid.sideLabel == "Right")
            Text(aid.model ?? L("Hearing aid")).font(.caption).foregroundStyle(.secondary)
            AidBatteryView(store: store, aid: aid).frame(maxWidth: .infinity, alignment: .center)
        }.frame(maxWidth: .infinity)
    }
    private func navigationCard(title: String, subtitle: String, symbol: String, page: AppPage) -> some View {
        Button { navigation.page = page } label: {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.title2).foregroundStyle(Brand.accent).frame(width: 32)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.callout.weight(.medium)).foregroundStyle(.tertiary)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        }.buttonStyle(.plain)
    }
}
